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
            # Reverse only the exact reviewed lookup adaptation, then verify the
            # complete upstream file hash; validation changes remain forbidden.
            packaged_lookup = b"""            // Both public package layouts, in SwiftPM's Apple and Linux spellings.
            // Prefer the aggregate SDK without bypassing any present corrupt bundle.
            for name in [
                "HanlinSDK_HanlinExactJSONSchema.bundle",
                "HanlinSDK_HanlinExactJSONSchema.resources",
                "HanlinAgentSDK_HanlinExactJSONSchema.bundle",
                "HanlinAgentSDK_HanlinExactJSONSchema.resources",
            ] {"""
            upstream_lookup = b"""            // SwiftPM's Apple/Swift Build and Linux resource directory spellings.
            for name in ["Swift-JSON_JSONSchema.bundle", "Swift-JSON_JSONSchema.resources"] {"""
            assert data.count(packaged_lookup) == 1, name
            data = data.replace(packaged_lookup, upstream_lookup)
            # Preserve the original WASI command-relative standalone adaptation.
            data = data.replace(b"HanlinAgentSDK_HanlinExactJSONSchema.bundle", b"Swift-JSON_JSONSchema.bundle")
        assert hashlib.sha256(data).hexdigest() == record["upstream_sha256"], name
    return {"status": "VERIFIED_SOURCE_IDENTITY", "revision": proof["revision"],
            "files": len(proof["files"]), "adaptations": proof["adaptations"]}


if __name__ == "__main__":
    print(json.dumps(verify(Path(__file__).resolve().parents[2]), indent=2))
