#!/usr/bin/env python3
"""Read bounded public FoundationModels declarations from this job's Apple SDK.

The default only reads declarations. An explicit --query-availability compiles
and runs a bounded availability-only program on the macOS runner host. Neither
mode generates model output, invokes tools, requests permission or downloads a
runtime. Receipts distinguish queried availability from model execution.
"""
from pathlib import Path
import argparse, hashlib, json, os, platform, re, selectors, signal, subprocess, tempfile, time

# Exactly the public availability projection used by HanlinAppleOnDeviceProvider.
# No LanguageModelSession, generation, tools, prompt, networking or credentials.
AVAILABILITY_SOURCE = """import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@main
struct HanlinFoundationModelsAvailabilityQuery {
    static func main() throws {
        let availability: String
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: availability = "available"
            case .unavailable(.deviceNotEligible): availability = "deviceNotEligible"
            case .unavailable(.appleIntelligenceNotEnabled): availability = "intelligenceDisabled"
            case .unavailable(.modelNotReady): availability = "modelNotReady"
            case .unavailable: availability = "unavailable"
            @unknown default: availability = "unavailable"
            }
        } else {
            availability = "unsupportedOS"
        }
        #else
        availability = "frameworkUnavailable"
        #endif
        let result: [String: Any] = [
            "schemaVersion": 1, "query": "SystemLanguageModel.default.availability",
            "availability": availability, "platform": "macOS",
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "modelExecution": "NOT_RUN", "toolExecution": "NOT_RUN"
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
"""
AVAILABILITY_VALUES = {"available", "deviceNotEligible", "intelligenceDisabled",
    "modelNotReady", "unavailable", "unsupportedOS", "frameworkUnavailable"}


def bounded_command(args, output, name, timeout, output_limit=65536):
    """Retain bounded exact stdout/stderr; stop this command's group at the limit."""
    record = {"command": list(map(str, args)), "timeoutSeconds": timeout,
              "outputLimitBytesPerStream": output_limit, "status": "FAIL"}
    started = time.monotonic()
    buffers = {"stdout": bytearray(), "stderr": bytearray()}
    try:
        process = subprocess.Popen(record["command"], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, start_new_session=True)
    except OSError as error:
        record["error"] = str(error)
    else:
        with selectors.DefaultSelector() as selector:
            for name_, pipe in (("stdout", process.stdout), ("stderr", process.stderr)):
                selector.register(pipe, selectors.EVENT_READ, name_)
            while selector.get_map():
                remaining = timeout - (time.monotonic() - started)
                if remaining <= 0:
                    record["termination"] = "TIMEOUT"
                    break
                for key, _ in selector.select(min(remaining, 0.1)):
                    chunk = os.read(key.fileobj.fileno(), 8192)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    buffer = buffers[key.data]
                    room = output_limit - len(buffer)
                    buffer.extend(chunk[:room])
                    if len(chunk) > room:
                        record["termination"] = "OUTPUT_LIMIT"
                        break
                if "termination" in record:
                    break
            if "termination" in record:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            try:
                record["returncode"] = process.wait(timeout=max(0.01, timeout - (time.monotonic() - started)))
            except subprocess.TimeoutExpired:
                record["termination"] = "TIMEOUT"
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    record["returncode"] = process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    record["returncode"] = None
                    record["error"] = "Process did not exit after bounded group termination"
            process.stdout.close()
            process.stderr.close()
        if record["returncode"] == 0 and "termination" not in record:
            record["status"] = "PASS"
    record["elapsedSeconds"] = round(time.monotonic() - started, 4)
    for stream, data in buffers.items():
        filename = f"{name}.{stream}.log"
        (output / filename).write_bytes(data)
        record[stream] = {"path": filename, "bytes": len(data),
                         "sha256": hashlib.sha256(data).hexdigest()}
    return record


def query_availability(output):
    """Use the installed native macOS framework, separately from simulator API capture."""
    output.mkdir(parents=True, exist_ok=True)
    source = output / "availability.swift"
    source.write_text(AVAILABILITY_SOURCE)
    receipt = {"schemaVersion": 1, "status": "BLOCKED", "availability": "NOT_QUERIED",
        "executionTarget": "macOS runner host; not iOS Simulator",
        "hostSystem": platform.system(), "hostArchitecture": platform.machine(),
        "modelExecution": "NOT_RUN", "toolExecution": "NOT_RUN",
        "toolCapability": "NOT_QUERIED", "source": source.name,
        "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(), "commands": []}

    def execute(name, args, timeout=10):
        record = bounded_command(args, output, name, timeout)
        receipt["commands"].append(record)
        if record["status"] != "PASS":
            raise RuntimeError(f"{name}: {record.get('termination', 'command failed')}")
        return (output / record["stdout"]["path"]).read_text().strip()

    try:
        if platform.system() != "Darwin":
            receipt["reason"] = "The opt-in availability query requires a macOS runner host."
            return receipt
        receipt["xcode"] = execute("xcode-version", ["xcodebuild", "-version"])
        sdk = execute("sdk-path", ["xcrun", "--sdk", "macosx", "--show-sdk-path"])
        receipt["sdkPath"] = sdk
        receipt["sdkVersion"] = execute("sdk-version", ["xcrun", "--sdk", "macosx", "--show-sdk-version"])
        receipt["compiler"] = execute("compiler-version", ["xcrun", "--sdk", "macosx", "swiftc", "--version"])
        # Compiler caches and the ephemeral executable are owned by this query;
        # retain their identity without uploading an unbounded module cache.
        with tempfile.TemporaryDirectory(prefix="hanlin-foundation-models-availability-") as temporary:
            executable = Path(temporary) / "availability-query"
            execute("compile", ["xcrun", "--sdk", "macosx", "swiftc", "-sdk", sdk,
                "-parse-as-library", "-module-cache-path", str(Path(temporary) / "module-cache"),
                str(source), "-o", str(executable)], timeout=60)
            receipt["executableSHA256"] = hashlib.sha256(executable.read_bytes()).hexdigest()
            observation = json.loads(execute("query", [str(executable)], timeout=10))
        if (not isinstance(observation, dict) or type(observation.get("schemaVersion")) is not int
            or observation.get("schemaVersion") != 1
            or observation.get("query") != "SystemLanguageModel.default.availability"
            or observation.get("platform") != "macOS"
            or not isinstance(observation.get("osVersion"), str)
            or not isinstance(observation.get("availability"), str)
            or observation.get("availability") not in AVAILABILITY_VALUES
            or observation.get("modelExecution") != "NOT_RUN"
            or observation.get("toolExecution") != "NOT_RUN"):
            raise ValueError("Unexpected availability-only program output")
        receipt.update(status="PASS", availability=observation["availability"], observation=observation)
    except (OSError, RuntimeError, ValueError) as error:
        receipt.update(status="FAIL", reason=str(error))
    finally:
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def command(*args):
    p = subprocess.run(args, capture_output=True, text=True, check=True)
    return p.stdout.strip()

def inspect(output):
    output.mkdir(parents=True, exist_ok=True)
    sdk = Path(command("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"))
    root = sdk / "System/Library/Frameworks/FoundationModels.framework/Modules/FoundationModels.swiftmodule"
    candidates = sorted(root.glob("*.swiftinterface"))
    candidates = [p for p in candidates if ".private." not in p.name]
    # One arm64 public interface describes the exact simulator compilation API.
    selected = next((p for p in candidates if p.name.startswith("arm64-")), None)
    selected = selected or next((p for p in candidates if p.name.startswith("arm64e-")), None)
    selected = selected or (candidates[0] if candidates else None)
    receipt = {"schemaVersion": 1, "xcode": command("xcodebuild", "-version"),
        "sdkVersion": command("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"),
        "modelExecution": "NOT_RUN", "availability": "NOT_QUERIED"}
    if selected is None:
        receipt["status"] = "PUBLIC_INTERFACE_NOT_FOUND"
        receipt["searchedPath"] = str(root)
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        return receipt
    raw = selected.read_bytes()
    lines = raw.decode("utf-8").splitlines()
    needles = ("LanguageModelExecutorGenerationRequest", "LanguageModelExecutorGenerationChannel",
               "executorConfiguration", "struct Executor", "class Executor", "protocol Executor",
               "extension FoundationModels.SystemLanguageModel.Executor",
               "DynamicProfile", "struct Profile", "class Profile", "protocol Profile",
               "extension FoundationModels.LanguageModelSession.Profile",
               "func onToolCall", "func historyTransform",
               "struct Transcript", "extension FoundationModels.Transcript",
               # SDK 27 interfaces also qualify names with ::. Match public type
               # identities so complete extensions and tool continuations survive.
               "GenerationOptions", "ToolCallingMode", "GenerationSchema", "GeneratedContent",
               "protocol Tool", "struct Tool", "ToolDefinition", "ToolCall", "ToolOutput",
               "Transcript", "LanguageModelSession", "SystemLanguageModel",
               "LanguageModelCapabilities", "ContextOptions")
    ranges = []
    for i, line in enumerate(lines):
        relevant = any(x in line for x in needles)
        response = ("func respond" in line or "func streamResponse" in line)
        if not (relevant or response):
            continue
        start = max(0, i-3)
        end = min(len(lines), i+15)
        # Include the complete visible declaration body. Swift interfaces use
        # indentation to close public type/extension blocks at their own level.
        if relevant and "{" in line and re.search(r"\b(struct|class|enum|protocol|extension)\b", line):
            indentation = len(line) - len(line.lstrip())
            for j in range(i+1, min(len(lines), i+500)):
                if lines[j].strip() == "}" and len(lines[j])-len(lines[j].lstrip()) == indentation:
                    end = j+1
                    break
        ranges.append((start, end))
    merged = []
    for start, end in sorted(ranges):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    text = "\n\n".join("\n".join(f"{j+1}: {lines[j]}" for j in range(start,end)) for start,end in merged)
    if len(text.encode("utf-8")) > 250_000:
        raise RuntimeError("Requested public declaration excerpt exceeds the bounded output limit")
    (output / "declarations.txt").write_text(text + "\n")
    receipt.update(status="DECLARATIONS_READ", interface=str(selected.relative_to(sdk)),
        interfaceSHA256=hashlib.sha256(raw).hexdigest(), interfaceBytes=len(raw),
        excerptSHA256=hashlib.sha256((text+"\n").encode()).hexdigest(),
        excerptRanges=[{"startLine":a+1,"endLine":b} for a,b in merged])
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2)+"\n")
    return receipt

def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--query-availability", action="store_true",
        help="Opt in to a bounded native macOS availability query; no model generation or tool calls")
    args = parser.parse_args(argv)
    receipt = inspect(args.output)
    if args.query_availability:
        availability = query_availability(args.output / "availability-query")
        receipt["availability"] = availability["availability"]
        receipt["availabilityQuery"] = {"status": availability["status"],
            "receipt": "availability-query/receipt.json",
            "executionTarget": availability["executionTarget"]}
        (args.output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt))

if __name__ == "__main__":
    main()
