"""Retain native XCTest end lines immediately; they do not replace xcresult proof."""
import json
from pathlib import Path
import re
import sys


def case_end(line):
    match = re.search(r"Test Case '-\[[^\]]*ParityUITests (test\w+)\]' (passed|failed|skipped)\b", line)
    if not match:
        return None
    return {"selector": "ParityUITests/" + match[1], "result": match[2], "raw_line": line.rstrip()}


if __name__ == "__main__":
    folder = Path(sys.argv[1])
    with (folder / "test.log").open("w", encoding="utf-8") as log, (folder / "case-end-lines.jsonl").open("w", encoding="utf-8") as events:
        for line in sys.stdin:
            log.write(line)
            log.flush()
            print(line, end="", flush=True)
            event = case_end(line)
            if event:
                events.write(json.dumps(event) + "\n")
                events.flush()
