#!/usr/bin/env python3
"""Retain the unchanged original CI unittest discovery on an admitted Git source."""
import argparse
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


parser = argparse.ArgumentParser()
parser.add_argument("--source", required=True)
parser.add_argument("--worktree", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
assert re.fullmatch(r"[0-9a-f]{40}", args.source)
assert args.worktree.is_absolute() and args.output.is_absolute()
git_command = ["runuser", "-u", "chatgpt-agent", "--", "git", "-C", str(args.worktree)]


def git(*arguments):
    return subprocess.run(git_command + list(arguments), check=True, capture_output=True).stdout


assert git("rev-parse", "HEAD").decode().strip() == args.source
assert git("status", "--porcelain") == b""
paths = [os.fsdecode(p) for p in git("ls-files", "-z").split(b"\0") if p]
missing = [p for p in paths if not os.path.lexists(args.worktree / p)]
assert not missing, missing[:20]
sparse = subprocess.run(git_command + ["config", "--get", "core.sparseCheckout"], capture_output=True)
assert sparse.returncode == 1 or sparse.stdout.strip() == b"false", sparse.stdout
assert not args.output.exists(), "Use a fresh evidence directory; never overwrite a prior run."
args.output.mkdir(parents=True)

env = os.environ.copy()
env["PATH"] = "/mnt/development/projects/toolchains/node-v24.5.0-linux-arm64/bin:" + env["PATH"]
env.pop("NODE_OPTIONS", None)
env.pop("HANLIN_RUN_PACKAGING_NETWORK", None)
environment_command = ["runuser", "-u", "chatgpt-agent", "--", "python3", "-c",
    "import json,sys,yaml,subprocess,os;print(json.dumps({'python':sys.version,'pythonExecutable':sys.executable,'pyyaml':yaml.__version__,'pyyamlPath':yaml.__file__,'node':subprocess.check_output(['node','--version'],text=True).strip(),'nodePath':subprocess.check_output(['which','node'],text=True).strip(),'NODE_OPTIONS':os.environ.get('NODE_OPTIONS'),'HANLIN_RUN_PACKAGING_NETWORK':os.environ.get('HANLIN_RUN_PACKAGING_NETWORK')}))"]
environment = json.loads(subprocess.run(environment_command, env=env, check=True, capture_output=True, text=True).stdout)
assert environment["node"] == "v24.5.0", environment
assert environment["pyyaml"] == "6.0.1", environment
assert environment["NODE_OPTIONS"] is None
assert environment["HANLIN_RUN_PACKAGING_NETWORK"] is None

inputs = []
for relative in paths:
    path = args.worktree / relative
    digest = hashlib.sha256()
    if path.is_symlink():
        data = os.fsencode(os.readlink(path))
        digest.update(data)
        size = len(data)
    else:
        size = path.stat().st_size
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
    inputs.append({"path": relative, "bytes": size, "sha256": digest.hexdigest(), "symlink": path.is_symlink()})
source = {"sourceCommit": args.source, "tree": git("rev-parse", "HEAD^{tree}").decode().strip(),
    "trackedFiles": len(inputs), "missing": [], "files": inputs, "environment": environment,
    "testModules": [p for p in paths if p.startswith("Scripts/CI/Tests/test_") and p.endswith(".py")],
    "trackedIndexSHA256": sha(git("ls-files", "--stage", "-z")), "statusBefore": ""}
write(args.output / "source-inputs.json", source)
command = ["runuser", "-u", "chatgpt-agent", "--", "python3", "-m", "unittest", "discover", "-s", "Scripts/CI/Tests", "-p", "test_*.py", "-v"]
started = utc()
begin = time.monotonic()
with (args.output / "stdout.log").open("wb") as stdout, (args.output / "stderr.log").open("wb") as stderr:
    process = subprocess.Popen(command, cwd=args.worktree, env=env, stdout=stdout, stderr=stderr)
    write(args.output / "start.json", {"startedAt": started, "source": args.source, "cwd": str(args.worktree), "command": command, "controllerPID": os.getpid(), "processPID": process.pid, "environment": environment})
    exit_code = process.wait()
finished = utc()
duration = time.monotonic() - begin
stderr_text = (args.output / "stderr.log").read_text(errors="replace")
summary = re.findall(r"^Ran \d+ tests? in .+$|^OK(?: \(.*\))?$|^FAILED(?: \(.*\))?$", stderr_text, re.MULTILINE)
skips = [line for line in stderr_text.splitlines() if " ... skipped " in line]
files = {}
for name in ("stdout.log", "stderr.log", "source-inputs.json", "start.json"):
    path = args.output / name
    data = path.read_bytes()
    files[name] = {"bytes": len(data), "sha256": sha(data)}
    if name.endswith(".log"):
        compressed = gzip.compress(data, mtime=0)
        path.with_name(name + ".gz").write_bytes(compressed)
        assert gzip.decompress(compressed) == data
        files[name]["gzip"] = {"path": name + ".gz", "bytes": len(compressed), "sha256": sha(compressed), "encoding": "lossless gzip; original bytes unchanged"}
receipt = {"sourceCommit": args.source, "command": command, "cwd": str(args.worktree), "startedAt": started,
    "finishedAt": finished, "durationSeconds": duration, "exitCode": exit_code,
    "originalRunnerSummary": summary, "skips": skips, "statusAfter": git("status", "--porcelain").decode(),
    "headAfter": git("rev-parse", "HEAD").decode().strip(), "files": files,
    "nativeExecutedByController": False, "originalTestCommandChanged": False,
    "controllerImposedTestTimeout": None}
write(args.output / "receipt.json", receipt)
print(json.dumps({k: v for k, v in receipt.items() if k != "files"}), flush=True)
raise SystemExit(exit_code)
