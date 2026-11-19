#!/usr/bin/env python3
import sys
import json
import urllib.request
import urllib.parse

def main():
    if len(sys.argv) < 2:
        print("Usage: browse.py <sys_id>", file=sys.stderr)
        sys.exit(1)

    sys_id = sys.argv[1]
    encoded = urllib.parse.quote(sys_id)
    url = f"https://api.genizah.org/v1/browse?sys_id={encoded}"

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Hanlin-Genizah/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read()
            parsed = json.loads(data)
            print(json.dumps(parsed, indent=2, ensure_ascii=False))
    except Exception as e:
        print(f"Error querying Cairo Genizah API: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
