#!/usr/bin/env python3
"""Stage the exact shipped Composer as an isolated native baseline module."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SOURCE = "Packages/HanlinPresentationSDK/Sources/HanlinChatUI/Composer/HanlinMorphComposer.swift"
SHIPPED = "de9ccac5d38c44f597b2a057701de4757587d6a8"
baseline = subprocess.run(["git", "show", f"{SHIPPED}:{SOURCE}"], cwd=ROOT,
                          capture_output=True, check=True).stdout
if not baseline.startswith(b"// Adapted from Hanlin_Composer_MorphView_Bubble_Experiment.swift"):
    raise SystemExit("Unexpected baseline source")
destination = HERE / "Baseline" / "HanlinMorphComposer.swift"
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_bytes(baseline)
evidence = HERE / "evidence"
evidence.mkdir(exist_ok=True)
receipt = {
    "baseline_app_commit": SHIPPED,
    "baseline_source": SOURCE,
    "baseline_sha256": hashlib.sha256(baseline).hexdigest(),
    "candidate_app_commit": subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                                            capture_output=True, check=True, text=True).stdout.strip(),
    "candidate_sha256": hashlib.sha256((ROOT / SOURCE).read_bytes()).hexdigest(),
    "scope": "Two actual Composer implementations rendered by the same native UIKit host. No Runtime, accounts, live tools, or physical-device acceptance."
}
(evidence / "native-source-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
print(json.dumps(receipt))
