#!/usr/bin/env python3
"""Generate deterministic .scripting fixture archives for ScriptUI acceptance tests."""

import base64
import io
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES_DIR = ROOT / "AI_HLYUITests" / "Fixtures"
FIXTURES_DIR.mkdir(parents=True, exist_ok=True)

def make_zip(files: dict[str, str]) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, content in sorted(files.items()):
            info = zipfile.ZipInfo(name)
            info.date_time = (2026, 1, 1, 0, 0, 0)
            info.external_attr = 0o644 << 16
            zf.writestr(info, content.encode("utf-8"))
    return buf.getvalue()

# Valid ScriptUI App with network capability (fetch) and interactive state
VALID_MANIFEST = json.dumps({
    "name": "Hanlin ScriptUI Valid",
    "version": "1.0.0",
    "entry": "index.tsx",
    "runInApp": True
}, indent=2) + "\n"

VALID_CODE = """import { Button, Navigation, Text, VStack, useState, fetch } from "scripting"

function App() {
  const [count, setCount] = useState(0)
  return <VStack spacing={8}>
    <Text>Count {count}</Text>
    <Button title="Increment" action={() => setCount(value => value + 1)} />
  </VStack>
}

Navigation.present({ element: <App /> })
"""

# Malformed ScriptUI package: missing entrypoint
MALFORMED_MANIFEST = json.dumps({
    "name": "Hanlin ScriptUI Malformed",
    "version": "1.0.0",
    "runInApp": True
}, indent=2) + "\n"

valid_zip = make_zip({"script.json": VALID_MANIFEST, "index.tsx": VALID_CODE})
malformed_zip = make_zip({"script.json": MALFORMED_MANIFEST})

(FIXTURES_DIR / "HanlinScriptUIValid.scripting").write_bytes(valid_zip)
(FIXTURES_DIR / "HanlinScriptUIMalformed.scripting").write_bytes(malformed_zip)

print("Wrote HanlinScriptUIValid.scripting:", len(valid_zip), "bytes")
print("Wrote HanlinScriptUIMalformed.scripting:", len(malformed_zip), "bytes")
print("VALID_BASE64:", base64.b64encode(valid_zip).decode("ascii"))
print("MALFORMED_BASE64:", base64.b64encode(malformed_zip).decode("ascii"))
