"""Select an installed stable Xcode by its actual build, including aliases/symlinks."""
from pathlib import Path
import re
import subprocess
import sys


def select(applications: Path = Path("/Applications")) -> Path:
    candidates = []
    seen = set()
    for app in applications.glob("Xcode*.app"):
        resolved = app.resolve()
        if "beta" in str(app).lower() or "beta" in str(resolved).lower() or resolved in seen:
            continue
        seen.add(resolved)
        executable = resolved / "Contents/Developer/usr/bin/xcodebuild"
        if not executable.is_file():
            continue
        result = subprocess.run([str(executable), "-version"], capture_output=True, text=True, timeout=15)
        print(f"{app}: {result.stdout.strip()}", file=sys.stderr)
        match = re.fullmatch(r"Xcode (\d+(?:\.\d+)*)\nBuild version (\d+[A-Z]\d+[a-z]?)\s*", result.stdout)
        if result.returncode == 0 and match:
            # Apple promoted this exact RC build to the public Xcode 27 release
            # on 2026-09-14. A letter suffix alone does not make it a beta.
            # https://developer.apple.com/news/releases/
            if not match[2][-1].isdigit() and (match[1], match[2]) != ("27.0", "27A266a"):
                continue
            version = tuple(map(int, match[1].split(".")))
            if version[0] >= 27:
                candidates.append((version, resolved))
    if not candidates:
        raise RuntimeError("No installed stable Xcode 27+; beta fallback is not authorized")
    return max(candidates)[1]


if __name__ == "__main__":
    print(select())
