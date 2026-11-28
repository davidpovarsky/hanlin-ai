import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
report = payload.get("canonicalShadow")
if report is None:
    raise SystemExit("Shell acceptance did not emit canonical shadow evidence")
domains = {item["domain"]: item for item in report["domains"]}
if report["summary"]["mismatchCount"] != 0:
    raise SystemExit("Shell canonical shadow reported a mismatch")
if domains.get("runtime.core", {}).get("status") != "passed":
    raise SystemExit("Shell RuntimeCore canonical shadow did not pass")
print(
    "HANLIN_CANONICAL_SHADOW_CI acceptance=shell "
    f"passed={report['summary']['passedCount']} "
    f"warnings={report['summary']['warningCount']} "
    f"mismatches={report['summary']['mismatchCount']} "
    f"skipped={report['summary']['skippedCount']}"
)
