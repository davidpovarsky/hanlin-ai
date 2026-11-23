#!/usr/bin/env python3
"""Run two endpoint cases against exact production declarations, without providers or network.
This is a Foundation-only partial-module regression, not a native/app/transport test.
"""
import argparse, hashlib, json, os, pathlib, resource, subprocess

p = argparse.ArgumentParser()
p.add_argument("--repository", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[4])
p.add_argument("--revision", required=True)
p.add_argument("--output", type=pathlib.Path, required=True)
p.add_argument("--expected", choices=["crash", "pass"], required=True)
a = p.parse_args()
def git(*args):
    return subprocess.run(["git", *args], cwd=a.repository, check=True, text=True, capture_output=True).stdout
revision = git("rev-parse", "--verify", a.revision + "^{commit}").strip()
paths = [
    "Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinChatModelConfiguration.swift",
    "Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKModels.swift",
    "Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKProviderFactory.swift",
]
original = [git("show", revision + ":" + path) for path in paths]
def section(text, first, after):
    start = text.index(first)
    return text[start:text.index(after, start)]
declarations = [
    original[0],
    section(original[1], "public enum HanlinAISDKProviderKind", "public enum HanlinAISDKMessagePart"),
    section(original[2], "public enum HanlinAISDKProviderFactory", "struct HanlinAISDKResolvedProvider"),
]
main = r"""
let cases: [(String, [String: String])] = [
    ("https://myproxy.org/v1/chat/completions?team=ai&version=2",
     ["team": "ai", "version": "2"]),
    ("https://myproxy.org/v1/chat/completions?team=old&team=ai&team&empty=first&empty=&label=%D7%A9%D7%9C%D7%95%D7%9D&%74eam=final&flag&single=one&Team=capital",
     ["team": "final", "empty": "", "label": "שלום", "single": "one", "Team": "capital"])
]
for (index, entry) in cases.enumerated() {
    let configuration = HanlinChatModelConfiguration(
        modelID: "custom-model", company: "Proxy", apiType: "openai",
        endpoint: entry.0, credential: "test")
    let descriptor = HanlinAISDKProviderFactory.descriptor(for: configuration)
    precondition(descriptor.kind == .openAICompatible)
    precondition(descriptor.baseURL.absoluteString == "https://myproxy.org/v1")
    precondition(descriptor.queryParameters == entry.1)
    print("CASE \(index + 1) PASS")
}
"""
a.output.mkdir(parents=True, exist_ok=True)
source = a.output / "EndpointProof.swift"
source.write_text("\n".join(declarations) + "\n" + main)
def no_core():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
env = dict(os.environ, SWIFT_BACKTRACE="enable=no")
build = subprocess.run(["swiftc", "-swift-version", "6", str(source), "-o", str(a.output / "proof")],
                       capture_output=True, text=True, timeout=45, env=env, preexec_fn=no_core)
(a.output / "build.log").write_text(build.stdout + build.stderr)
if build.returncode:
    raise SystemExit("Production declaration compilation failed; no execution result.")
run = subprocess.run([str((a.output / "proof").resolve())], capture_output=True, text=True,
                     timeout=10, env=env, preexec_fn=no_core)
(a.output / "execution.log").write_text(run.stdout + run.stderr)
passed = (run.returncode == 0 and run.stdout.strip() == "CASE 1 PASS\nCASE 2 PASS") if a.expected == "pass" else (
    run.returncode != 0 and "Duplicate values for key" in run.stderr)
receipt = {"scope": __doc__, "revision": revision, "expected": a.expected,
           "build_exit": build.returncode, "execution_exit": run.returncode, "matched": passed,
           "inputs": [{"path": path, "sha256": hashlib.sha256(text.encode()).hexdigest()}
                      for path, text in zip(paths, original)],
           "declaration_sha256": [hashlib.sha256(text.encode()).hexdigest() for text in declarations]}
(a.output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps(receipt))
raise SystemExit(0 if passed else 1)
