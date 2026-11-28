#!/usr/bin/env python3
"""Generate deterministic .scripting fixture archives for ScriptUI acceptance tests."""

import io
import json
from pathlib import Path
from typing import List, Optional
import zipfile

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_FIXTURES_DIR = ROOT / "AI_HLYUITests" / "Fixtures"

FIXTURE_NAMES = [
    "HanlinScriptUIValid.scripting",
    "HanlinScriptUIMalformed.scripting",
    "HanlinScriptUIAppB.scripting",
]


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

# Distinct second ScriptUI package (App B) for A -> B -> A state isolation tests
APP_B_MANIFEST = json.dumps({
    "name": "Hanlin ScriptUI App B",
    "version": "1.0.0",
    "entry": "index.tsx",
    "runInApp": True
}, indent=2) + "\n"

APP_B_CODE = """import { Button, Navigation, Text, VStack, useState } from "scripting"

function AppB() {
  const [value, setValue] = useState("App B Ready")
  return <VStack spacing={8}>
    <Text>{value}</Text>
    <Button title="Mutate B" action={() => setValue("App B Mutated")} />
  </VStack>
}

Navigation.present({ element: <AppB /> })
"""


def create_fixtures(fixtures_dir: Optional[Path] = None) -> List[str]:
    out_dir = fixtures_dir or DEFAULT_FIXTURES_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    valid_zip = make_zip({"script.json": VALID_MANIFEST, "index.tsx": VALID_CODE})
    malformed_zip = make_zip({"script.json": MALFORMED_MANIFEST})
    app_b_zip = make_zip({"script.json": APP_B_MANIFEST, "index.tsx": APP_B_CODE})

    (out_dir / "HanlinScriptUIValid.scripting").write_bytes(valid_zip)
    (out_dir / "HanlinScriptUIMalformed.scripting").write_bytes(malformed_zip)
    (out_dir / "HanlinScriptUIAppB.scripting").write_bytes(app_b_zip)

    return FIXTURE_NAMES


if __name__ == "__main__":
    generated = create_fixtures()
    for name in generated:
        p = DEFAULT_FIXTURES_DIR / name
        print(f"Wrote {name}: {p.stat().st_size} bytes")
