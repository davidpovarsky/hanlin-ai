"""Raw local execution evidence and source/compiler/output-verified module reuse."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import subprocess
import sys
import uuid


def digest(path):
    path = Path(path)
    return {"path": str(path), "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def intact(record):
    path = Path(record["path"])
    return path.is_file() and digest(path) == record


class EvidenceRun:
    def __init__(self, root, suite):
        self.root = root
        self.directory = root / "docs/product-split/evidence/durability-fix" / str(uuid.uuid4())
        self.directory.mkdir(parents=True)
        self.trace = self.directory / "commands.jsonl"
        self.index = 0
        self.event({"kind": "invocation", "argv": sys.argv, "cwd": str(root), "suite": suite,
                    "python": sys.version, "python_executable": digest(sys.executable)})

    def event(self, value):
        value = {"utc": datetime.now(timezone.utc).isoformat(), **value}
        with self.trace.open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(json.dumps(value, sort_keys=True) + "\n")

    def record(self, command, label, code, stdout, stderr, pid=None):
        self.index += 1
        prefix = f"raw-{self.index:03d}-{label}"
        out = self.directory / (prefix + ".stdout.log")
        err = self.directory / (prefix + ".stderr.log")
        out.write_bytes(stdout); err.write_bytes(stderr)
        event = {"kind": "completed", "argv": list(map(str, command)), "cwd": str(self.root),
                 "exit_code": code, "pid": pid, "stdout": digest(out), "stderr": digest(err)}
        self.event(event)
        return event

    def execute(self, command, label, env=None, timeout=None):
        command = list(map(str, command))
        self.event({"kind": "start", "label": label, "argv": command, "cwd": str(self.root)})
        result = subprocess.run(command, cwd=self.root, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=timeout)
        event = self.record(command, label, result.returncode, result.stdout, result.stderr)
        if result.returncode:
            raise RuntimeError(f"{label}: exit {result.returncode}; see {event['stderr']['path']}")
        return result.stdout.decode("utf-8", errors="replace"), event

    def module(self, name, inputs, command, outputs, compiler, toolchain, dependencies, force=False):
        descriptor = {"compiler": digest(compiler), "toolchain": toolchain,
                      "argv": list(map(str, command)), "cwd": str(self.root),
                      "sources": [digest(p) for p in inputs], "dependency_outputs": dependencies}
        stamp = outputs[0].parent / (name + ".verified-provenance.json")
        cached = json.loads(stamp.read_text(encoding="utf-8")) if stamp.exists() else None
        reusable = (not force and cached and cached.get("inputs") == descriptor
                    and all(intact(r) for r in cached["outputs"] + cached["origin_logs"]))
        if reusable:
            provenance = cached
            status = "REUSED_VERIFIED_OUTPUT_AND_ORIGIN_HASHES"
            self.event({"kind": "verified_module_reuse", "name": name,
                        "provenance": digest(stamp), "outputs": provenance["outputs"]})
        else:
            _, event = self.execute(command, "compile-" + name)
            artifacts = list(outputs)
            base = "HanlinPlatformContracts" if name == "contracts" else "HanlinMiniAppCore"
            for suffix in [".swiftdoc", ".swiftsourceinfo", ".lib", ".exp"]:
                candidate = outputs[0].parent / (base + suffix)
                if candidate.exists() and candidate not in artifacts:
                    artifacts.append(candidate)
            provenance = {"inputs": descriptor, "outputs": [digest(p) for p in artifacts],
                          "origin_logs": [event["stdout"], event["stderr"]], "compile_event": event}
            stamp.write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8", newline="\n")
            status = "FRESH_COMPILED_RECORDED_LINEAGE"
        retained = self.directory / (name + "-provenance.json")
        retained.write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8", newline="\n")
        return {"status": status, "provenance": digest(retained), "outputs": provenance["outputs"]}

    def finish(self):
        records = [digest(p) for p in sorted(self.directory.iterdir()) if p.is_file()]
        manifest = self.directory / "manifest.json"
        manifest.write_text(json.dumps({"files": records}, indent=2) + "\n", encoding="utf-8", newline="\n")
        return digest(manifest)
