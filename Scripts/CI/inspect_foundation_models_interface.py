#!/usr/bin/env python3
"""Read bounded public FoundationModels declarations from this job's Apple SDK.

This does not execute a model, request permission, download a runtime or claim
model availability. Its receipt preserves the exact installed interface hash.
"""
from pathlib import Path
import argparse, hashlib, json, re, subprocess

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
        print(json.dumps(receipt))
        return
    raw = selected.read_bytes()
    lines = raw.decode("utf-8").splitlines()
    needles = ("LanguageModelExecutorGenerationRequest", "LanguageModelExecutorGenerationChannel",
               "executorConfiguration", "struct Executor", "class Executor", "protocol Executor",
               "extension FoundationModels.SystemLanguageModel.Executor",
               "DynamicProfile", "struct Profile", "class Profile", "protocol Profile",
               "extension FoundationModels.LanguageModelSession.Profile",
               "func onToolCall", "func historyTransform",
               "struct Transcript", "extension FoundationModels.Transcript")
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
    print(json.dumps(receipt))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    inspect(parser.parse_args().output)
