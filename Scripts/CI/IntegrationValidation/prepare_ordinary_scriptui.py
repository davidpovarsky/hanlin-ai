"""Package unchanged ordinary production-compiler corpus input for real import.

No installed registry, snapshot, provider or runtime output is synthesized.
The app must preview, compile, install, discover and run this actual package.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "AI_HLYTests/Fixtures/ScriptingFixtures.bundle/ProductionCompilerCorpus/ValidScriptUI"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    hashes = {}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(args.output, "w", compression=ZIP_DEFLATED) as archive:
        for name in ("script.json", "index.tsx"):
            source = FIXTURE / name
            data = source.read_bytes()
            relative = source.relative_to(ROOT).as_posix()
            assert data == subprocess.check_output(["git", "show", f"HEAD:{relative}"], cwd=ROOT), relative
            hashes[relative] = hashlib.sha256(data).hexdigest()
            entry = ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.compress_type = ZIP_DEFLATED
            archive.writestr(entry, data)
    print(json.dumps({"kind": "ordinary installed app, unchanged default JSC corpus source",
                      "input_sha256": hashes,
                      "package_sha256": hashlib.sha256(args.output.read_bytes()).hexdigest()}, indent=2))
