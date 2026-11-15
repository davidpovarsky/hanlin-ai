"""Read only a bounded receipt from a digest-authenticated GitHub artifact ZIP."""
import io
import json
import sys
import zipfile

archive = sys.stdin.buffer.read(16_777_217)
if len(archive) > 16_777_216:
    raise SystemExit("Proof archive exceeds 16MiB")
with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
    members = [item for item in bundle.infolist() if item.filename == 'candidate-receipt.json']
    if len(members) != 1 or members[0].file_size > 65_536:
        raise SystemExit("Missing/duplicate/oversized candidate receipt")
    data = bundle.read(members[0])
    if len(data) > 65_536:
        raise SystemExit("Receipt exceeds limit")
    receipt = json.loads(data)
    if receipt.get('schemaVersion') != 1:
        raise SystemExit("Unsupported receipt")
    print(json.dumps(receipt))
