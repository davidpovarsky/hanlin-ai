#!/usr/bin/env python3
"""Verify Node's dependency tree is excluded from the actual app source group."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path, PurePosixPath

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "CI" / "IntegrationValidation"))
from project_graph import parse_project

NODE_MODULES = PurePosixPath("Downstream/RuntimeCore/Node/Host/node_modules")


def validate_project(text: str) -> dict[str, object]:
    objects = parse_project(text)["objects"]
    targets = [(key, value) for key, value in objects.items()
               if value.get("isa") == "PBXNativeTarget" and value.get("name") == "HanlinApp"]
    if len(targets) != 1:
        raise ValueError("RuntimeCore requires exactly one HanlinApp app target.")
    target_id, target = targets[0]
    groups = [(key, objects[key]) for key in target.get("fileSystemSynchronizedGroups", [])
              if objects[key].get("isa") == "PBXFileSystemSynchronizedRootGroup"
              and objects[key].get("path") == "AI_HLY"]
    if len(groups) != 1:
        raise ValueError("RuntimeCore requires the app's actual synchronized AI_HLY group.")
    group_id, group = groups[0]
    proof = []
    for exception_id in group.get("exceptions", []):
        exception = objects[exception_id]
        if (exception.get("isa") != "PBXFileSystemSynchronizedBuildFileExceptionSet"
                or exception.get("target") != target_id):
            continue
        for entry in exception.get("membershipExceptions", []):
            path = PurePosixPath(entry)
            if (entry and str(path) != "." and not path.is_absolute()
                    and ".." not in path.parts and NODE_MODULES.is_relative_to(path)):
                proof.append({"exception": exception_id, "excludedPath": entry})
    if not proof:
        raise ValueError(
            "RuntimeCore requires Node Host node_modules to be excluded from "
            "the app's synchronized AI_HLY group; another target or comment is not evidence."
        )
    return {"target": target_id, "group": group_id,
            "excludedNodeModules": str(NODE_MODULES), "membershipProof": proof}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(validate_project(args.project.read_text()), sort_keys=True))


if __name__ == "__main__":
    main()
