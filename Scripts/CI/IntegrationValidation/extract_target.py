"""Generate a disposable project for the exact registered MiniApps target.

The full project also resolves unrelated missing Runtime binary targets. Keep
the registered target/settings/source membership unchanged while pruning those
unrelated project references. Product sources stay in their original checkout.
This is extracted-target proof, not full-project or live-provider acceptance.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import shutil

from project_graph import parse_project, validate_graph


def render(value, level=0):
    tab = "\t" * level
    if isinstance(value, dict):
        return "{\n" + "".join("\t" + tab + json.dumps(key) + " = " + render(child, level + 1)
                                 + ";\n" for key, child in value.items()) + tab + "}"
    if isinstance(value, list):
        return "(" + "".join(render(child, level) + ", " for child in value) + ")"
    return json.dumps(value, ensure_ascii=False)


def extract(root, output):
    project = parse_project((root / "AI_HLY.xcodeproj/project.pbxproj").read_text(encoding="utf-8"))
    validate_graph(project)
    original = project["objects"]
    target = next(key for key, value in original.items()
                  if value.get("isa") == "PBXNativeTarget" and value.get("name") == "HanlinMiniApps")
    objects = {}

    def retain(key):
        if key in objects:
            return
        objects[key] = copy.deepcopy(original[key])
        visit(objects[key])

    def visit(value):
        if isinstance(value, dict):
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
        elif isinstance(value, str) and re.fullmatch(r"[A-F0-9]{24}", value) and value in original:
            retain(value)

    retain(target)
    original_root = original[project["rootObject"]]
    retain(original_root["buildConfigurationList"])
    # Keep genuine project-level compiler settings, with only the one target,
    # two local package references, source group and product in this temp graph.
    products = copy.deepcopy(original[original_root["productRefGroup"]])
    products["children"] = [original[target]["productReference"]]
    objects[original_root["productRefGroup"]] = products
    main = copy.deepcopy(original[original_root["mainGroup"]])
    main["children"] = original[target]["fileSystemSynchronizedGroups"] + [original_root["productRefGroup"]]
    objects[original_root["mainGroup"]] = main
    new_root = copy.deepcopy(original_root)
    new_root["targets"] = [target]
    new_root["packageReferences"] = [key for key, value in objects.items()
                                    if value["isa"] == "XCLocalSwiftPackageReference"]
    new_root["attributes"]["TargetAttributes"] = {target: {"CreatedOnToolsVersion": "27.0"}}
    objects[project["rootObject"]] = new_root
    for value in objects.values():
        if value["isa"] == "PBXFileSystemSynchronizedRootGroup":
            value["path"] = str((root / value["path"]).resolve())
            value["sourceTree"] = "<absolute>"
        elif value["isa"] == "XCLocalSwiftPackageReference":
            value["relativePath"] = str((root / value["relativePath"]).resolve())
    assert objects[target] == original[target], "Extracted target must remain byte-structurally equivalent"
    project["objects"] = objects
    output.mkdir(parents=True, exist_ok=False)
    (output / "project.pbxproj").write_text("// !$*UTF8*$!\n" + render(project) + "\n", encoding="utf-8")
    schemes = output / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True)
    shutil.copyfile(root / "AI_HLY.xcodeproj/xcshareddata/xcschemes/HanlinMiniApps.xcscheme",
                    schemes / "HanlinMiniApps.xcscheme")
    return {"status": "EXTRACTED_NOT_COMPILED", "target_structurally_identical": True,
            "source_copy_or_substitution": False, "target_id": target,
            "retained_objects": len(objects), "full_project_acceptance": False,
            "project_sha256": hashlib.sha256((output / "project.pbxproj").read_bytes()).hexdigest()}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(extract(Path(__file__).resolve().parents[3], args.output), indent=2))
