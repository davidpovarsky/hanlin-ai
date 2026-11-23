#!/usr/bin/env python3
"""Run the SwiftSyntax resource-routing audit; --apply is explicit and idempotent."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

source = Path(__file__).with_suffix(".swift")
compiler = shutil.which("swiftc")
if sys.platform == "darwin":
    compiler = subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip()
if not compiler:
    raise SystemExit("Swift toolchain required")
host = Path(compiler).resolve().parent.parent / "lib/swift/host"
if not (host / "SwiftSyntax.swiftmodule").exists():
    raise SystemExit("Selected Swift toolchain does not provide its matching SwiftSyntax module")
with tempfile.TemporaryDirectory(prefix="hanlin-resource-routing-") as temporary:
    executable = Path(temporary) / "route"
    subprocess.run([compiler, "-I", str(host), "-L", str(host), "-lSwiftSyntax", "-lSwiftParser",
                    "-Xlinker", "-rpath", "-Xlinker", str(host), str(source), "-o", str(executable)], check=True)
    subprocess.run([str(executable), *sys.argv[1:]], check=True)
