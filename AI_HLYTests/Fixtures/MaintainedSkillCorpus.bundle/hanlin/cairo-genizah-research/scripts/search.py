#!/usr/bin/env python3
import sys
import json
import urllib.request
import urllib.parse

def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    if len(sys.argv) < 2:
        print("Usage: search.py <query> [limit]", file=sys.stderr)
        sys.exit(1)

    query = sys.argv[1]
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 5

    encoded = urllib.parse.quote(query)
    url = f"https://api.genizah.org/v1/search?q={encoded}&mode=fuzzy&limit={limit}"

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
