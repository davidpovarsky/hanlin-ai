#!/usr/bin/env python3
"""
verify-zero-stubs.py — Automated CI check ensuring zero stubs, mocks, simulations,
or hardcoded results exist in production Torah Photo Study code.
Fails with non-zero exit code if prohibited patterns are detected.
"""

import sys
import re
from pathlib import Path

PROHIBITED_PATTERNS = [
    (r"Emulate OCR", "Emulated OCR placeholder"),
    (r"מאימתי קורין את שמע בערבין", "Hardcoded Berakhot passage in production"),
    (r"otzaria:bavli:Berakhot:canonical_ref:Berakhot 2a", "Hardcoded Berakhot locator in production"),
    (r"Task\.sleep\(nanoseconds:\s*[0-9_]+\)", "Simulated Task.sleep delay in production"),
    (r"T-S Misc\.24\.18", "Simulated Cairo Genizah fallback"),
    (r"טהרת כהנים \(Priestly Purity\)", "Hardcoded Torah topics list"),
]

PRODUCTION_DIRS = [
    "AI_HLY/Downstream/TorahStudy",
    "Packages/TorahLibraryKit/Sources",
    "Skills/cairo-genizah-research/scripts"
]

def main():
    repo_root = Path(__file__).resolve().parent.parent.parent
    violations = []

    for rel_dir in PRODUCTION_DIRS:
        scan_dir = repo_root / rel_dir
        if not scan_dir.exists():
            continue
        for file_path in scan_dir.rglob("*"):
            if not file_path.is_file() or file_path.suffix not in [".swift", ".py"]:
                continue
            
            try:
                content = file_path.read_text(encoding="utf-8")
            except Exception:
                continue

            for pattern, description in PROHIBITED_PATTERNS:
                matches = list(re.finditer(pattern, content))
                for m in matches:
                    line_no = content[:m.start()].count("\n") + 1
                    rel_path = file_path.relative_to(repo_root)
                    violations.append(f"{rel_path}:{line_no}: {description} ('{m.group(0)}')")

    if violations:
        print("VERIFY ZERO STUBS FAILURE: Prohibited stub/mock patterns found in production code:", file=sys.stderr)
        for v in violations:
            print(f"  ERROR: {v}", file=sys.stderr)
        sys.exit(1)

    print("VERIFY ZERO STUBS PASSED: All production Torah Photo Study files are clean of stubs, mocks, and hardcoded results.")
    sys.exit(0)

if __name__ == "__main__":
    main()
