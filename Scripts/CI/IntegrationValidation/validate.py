"""Scoped graph checks; these do not claim compilation or feature acceptance."""
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

from project_graph import parse_project, validate_graph

ROOT = Path(__file__).resolve().parents[3]
BASE = "dd700c03e9fe9d22e95a031d4684275512ee6e6f"
PROJECT = "AI_HLY.xcodeproj/project.pbxproj"


def validate():
    project = parse_project((ROOT / PROJECT).read_text(encoding="utf-8"))
    result = validate_graph(project)
    original = parse_project(subprocess.check_output(
        ["git", "show", f"{BASE}:{PROJECT}"], cwd=ROOT, encoding="utf-8"))
    objects, old = project["objects"], original["objects"]
    old_root = old[original["rootObject"]]
    extensions = {original["rootObject"]: {"packageReferences", "targets"},
                  old_root["mainGroup"]: {"children"}, old_root["productRefGroup"]: {"children"}}
    for key, value in old.items():
        current = objects[key]
        for field in value.keys() | current.keys():
            if field in extensions.get(key, set()):
                assert [item for item in current[field] if item in old] == value[field], (key, field)
            else:
                assert current.get(field) == value.get(field), f"Changed existing object {key}/{field}"
    manifest = json.loads(subprocess.check_output(
        ["swift", "package", "--package-path", str(ROOT / "Packages/HanlinProductSplit"), "dump-package"],
        cwd=ROOT, encoding="utf-8"))
    targets = {target["name"]: target for target in manifest["targets"]}
    assert set(targets) == {"HanlinProductSplit", "RegisteredIntegrationTests"}
    excluded = {"SplitFixtureStore.swift", "SplitReceiverFixturePersistence.swift",
                "SplitMigrationFixturePersistence.swift"}
    assert set(targets["HanlinProductSplit"]["exclude"]) == excluded
    assert targets["RegisteredIntegrationTests"]["path"] == "Tests/RegisteredIntegrationTests"
    source_root = ROOT / "Packages/HanlinProductSplit/Sources/HanlinProductSplit"
    production = sorted(p.name for p in source_root.glob("*.swift") if p.name not in excluded)
    assert production, "Empty production target"
    assert all("@main" not in (source_root / name).read_text(encoding="utf-8") for name in production)
    scheme = ET.parse(ROOT / "AI_HLY.xcodeproj/xcshareddata/xcschemes/HanlinMiniApps.xcscheme")
    refs = scheme.findall(".//BuildableReference")
    mini_id = next(key for key, value in objects.items()
                   if value.get("isa") == "PBXNativeTarget" and value.get("name") == "HanlinMiniApps")
    assert refs and all(ref.get("BlueprintIdentifier") == mini_id for ref in refs)
    assert not scheme.findall(".//TestableReference"), "Leaf tests run through their real package scheme"
    result.update(status="GRAPH_CHECKS_PASS", base=BASE, production_sources=production,
                  registered_suite="RegisteredSplitIntegrationTests", registered_cases=5,
                  project_sha256=hashlib.sha256((ROOT / PROJECT).read_bytes()).hexdigest(),
                  native_build="NOT_RUN", feature_acceptance="NOT_RUN")
    return result


if __name__ == "__main__":
    print(json.dumps(validate(), indent=2))
