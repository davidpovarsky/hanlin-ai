"""Reproducible pure wrapper for the native extension linked into Hanlin's app."""
import base64
import csv
import hashlib
import io
import json
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[2] / "AI_HLY/Downstream/RuntimeCore/Python/Resources"
filename = "hanlin_native-1.0.0-py3-none-any.whl"
info = "hanlin_native-1.0.0.dist-info"
files = {
    "hanlin_native/__init__.py": b'from _hanlin_native import challenge, registry\n__version__ = "1.0.0"\n',
    info + "/METADATA": b"Metadata-Version: 2.3\nName: hanlin-native\nVersion: 1.0.0\nRequires-Python: >=3.14\nSummary: Wrapper for Hanlin's signed built-in CPython extension\n\n",
    info + "/WHEEL": b"Wheel-Version: 1.0\nGenerator: Hanlin\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
}
record = io.StringIO(newline="")
writer = csv.writer(record, lineterminator="\n")
for name, content in files.items():
    digest = base64.urlsafe_b64encode(hashlib.sha256(content).digest()).rstrip(b"=").decode()
    writer.writerow((name, "sha256=" + digest, str(len(content))))
writer.writerow((info + "/RECORD", "", ""))
files[info + "/RECORD"] = record.getvalue().encode()
target = root / filename
with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for name, content in sorted(files.items()):
        entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
        entry.compress_type = zipfile.ZIP_DEFLATED
        entry.external_attr = 0o100644 << 16
        archive.writestr(entry, content)
manifest = {"schemaVersion": 1, "extensions": [{
    "distribution": "hanlin-native", "version": "1.0.0", "module": "_hanlin_native",
    "importName": "hanlin_native", "wheel": filename,
    "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
    "linkage": "signed-app-builtin", "source": "Python/Native/HanlinPythonNativeExtensions.mm",
}]}
(root / "HanlinPythonNativeExtensions.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
print(filename, manifest["extensions"][0]["sha256"])
