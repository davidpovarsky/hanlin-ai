"""Verify the one original exact JSON validator and its sole packaging adaptation."""
import hashlib
import json
from pathlib import Path


def verify(root: Path) -> dict:
    vendor = root / "Packages/HanlinAgentSDK/Vendor/Swift-JSON"
    proof = json.loads((vendor / "PROVENANCE.json").read_text())
    assert proof["revision"] == "f2a0d12da7028edfbcb0cb307f19a921a3a12d03"
    adapted = "Sources/JSONSchema/Document/JSONSchemaBuiltins.swift"
    assert set(proof["adaptations"]) == {adapted}
    actual = {p.relative_to(vendor).as_posix() for p in vendor.rglob("*") if p.is_file()}
    assert actual == set(proof["files"]) | {"PROVENANCE.json"}
    for name, record in proof["files"].items():
        data = (vendor / name).read_bytes()
        assert hashlib.sha256(data).hexdigest() == record["local_sha256"], name
        if name == adapted:
            data = data.replace(b"HanlinAgentSDK_HanlinExactJSONSchema.bundle", b"Swift-JSON_JSONSchema.bundle")
            data = data.replace(b"HanlinAgentSDK_HanlinExactJSONSchema.resources", b"Swift-JSON_JSONSchema.resources")
        assert hashlib.sha256(data).hexdigest() == record["upstream_sha256"], name
    return {"status": "VERIFIED_SOURCE_IDENTITY", "revision": proof["revision"],
            "files": len(proof["files"]), "adaptations": proof["adaptations"]}


if __name__ == "__main__":
    print(json.dumps(verify(Path(__file__).resolve().parents[2]), indent=2))
