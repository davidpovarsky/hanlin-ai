"""Read the checked-in OpenStep project without Xcode or third-party packages."""
import re
import hashlib
from pathlib import Path


def parse_project(text):
    tokens = re.findall(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,"]+', text)
    tokens = [t for t in tokens if not t.startswith(("//", "/*"))]
    position = 0

    def take(expected=None):
        nonlocal position
        if position >= len(tokens):
            raise ValueError("Unexpected end of project")
        token = tokens[position]
        position += 1
        if expected is not None and token != expected:
            raise ValueError(f"Expected {expected}, got {token}")
        return token

    def value():
        token = take()
        if token == "{":
            result = {}
            while tokens[position] != "}":
                key = value()
                if not isinstance(key, str) or key in result:
                    raise ValueError(f"Invalid or duplicate project key: {key}")
                take("=")
                result[key] = value()
                take(";")
            take("}")
            return result
        if token == "(":
            result = []
            while tokens[position] != ")":
                result.append(value())
                if tokens[position] != ")":
                    take(",")
            take(")")
            return result
        if token.startswith('"'):
            # OpenStep quoted strings; preserve literal backslashes except its
            # escaped quote/backslash. Build-setting interpolation stays literal.
            return re.sub(r'\\(["\\])', r'\1', token[1:-1])
        if token in "{}()=;,":
            raise ValueError(f"Unexpected delimiter: {token}")
        return token

    project = value()
    if position != len(tokens):
        raise ValueError("Trailing project tokens")
    return project


def validate_graph(project, provider_manifest=None):
    objects = project["objects"]
    root = objects[project["rootObject"]]
    targets = [objects[key] for key in root["targets"]]
    mini = next(target for target in targets if target["name"] == "HanlinMiniApps")
    ai = next(target for target in targets if target["name"] == "AI_Hanlin")
    assert mini["productType"] == "com.apple.product-type.application"
    assert mini["dependencies"] == [], "MiniApps must not depend on the AI app/extensions"
    groups = [objects[key]["path"] for key in mini["fileSystemSynchronizedGroups"]]
    assert groups == ["HanlinMiniAppsApp"], "MiniApps must not compile the AI source tree"
    assert "HanlinMiniAppsApp" not in [objects[key]["path"] for key in ai["fileSystemSynchronizedGroups"]]
    phases = {objects[key]["isa"] for key in mini["buildPhases"]}
    expected_phases = {"PBXSourcesBuildPhase", "PBXFrameworksBuildPhase", "PBXResourcesBuildPhase"}
    if provider_manifest:
        expected_phases |= {"PBXShellScriptBuildPhase", "PBXCopyFilesBuildPhase"}
        expected_clones = set()
        for original_id in provider_manifest["inherited_build_phases"]:
            clone_id = "F9" + hashlib.sha256(("phase:" + original_id).encode()).hexdigest()[:22].upper()
            expected_clones.add(clone_id)
            clone, original = objects[clone_id], objects[original_id]
            # The standalone target keeps the exact native command and flags.
            # Only its two sandboxed scripts declare target-specific filesystem IO.
            expected = {k: v for k, v in original.items() if k != "files"}
            io_stem = {"A10000000000000000000051": "metadata",
                       "A10000000000000000000050": "python"}.get(original_id)
            if io_stem:
                for kind in ("input", "output"):
                    expected[kind + "FileListPaths"] = [
                        "$(SRCROOT)/Scripts/ProductSplit/BuildIO/" +
                        io_stem + "-" + kind + "s.xcfilelist"]
            assert {k: v for k, v in clone.items() if k != "files"} == expected, \
                "Native preparation must reuse the existing build command and declared IO"
            if "files" in original:
                assert [objects[key] for key in clone["files"]] == [objects[key] for key in original["files"]]
        actual_clones = {key for key in mini["buildPhases"]
                         if objects[key]["isa"] in {"PBXShellScriptBuildPhase", "PBXCopyFilesBuildPhase"}}
        assert actual_clones == expected_clones, "Unreviewed native build phase"
        source_phase = next(objects[key] for key in mini["buildPhases"] if objects[key]["isa"] == "PBXSourcesBuildPhase")
        source_paths = {objects[objects[key]["fileRef"]]["path"] for key in source_phase["files"]}
        assert source_paths == set(provider_manifest["swift_sources"] + provider_manifest["native_sources"])
        assert not source_paths.intersection(provider_manifest["excluded_ai_sources"])
        resource_phase = next(objects[key] for key in mini["buildPhases"] if objects[key]["isa"] == "PBXResourcesBuildPhase")
        assert {objects[objects[key]["fileRef"]]["path"] for key in resource_phase["files"]} == set(provider_manifest["resources"])
    assert phases == expected_phases, "Unexpected source/build phase"
    products = {objects[key]["productName"] for key in mini["packageProductDependencies"]}
    assert products == (set(provider_manifest["products"]) if provider_manifest else {
        "HanlinPlatformContracts", "HanlinMiniAppCore", "HanlinProductSplit"})
    frameworks = next(objects[key] for key in mini["buildPhases"]
                      if objects[key]["isa"] == "PBXFrameworksBuildPhase")
    linked = {objects[objects[key]["productRef"]]["productName"] for key in frameworks["files"]
              if "productRef" in objects[key]}
    assert linked == products, "Every declared MiniApps product must actually be linked"
    native_refs = {objects[key]["fileRef"] for key in frameworks["files"] if "fileRef" in objects[key]}
    assert native_refs == (set(provider_manifest["native_framework_refs"]) if provider_manifest else set())
    for target in (mini, ai):
        configs = objects[target["buildConfigurationList"]]["buildConfigurations"]
        for key in configs:
            settings = objects[key]["buildSettings"]
            assert settings["IPHONEOS_DEPLOYMENT_TARGET"] == "27.0"
            assert settings["SWIFT_VERSION"] == "6.0"
            if target is mini:
                production = provider_manifest and provider_manifest.get("product_stage") == "standalone-production-bundle"
                assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == ("com.itorah.hanlinminiapps" if production else "com.itorah.hanlinminiapps.integration")
                assert settings["SUPPORTED_PLATFORMS"] == ("iphoneos iphonesimulator" if production else "iphonesimulator")
                if production:
                    # The standalone product must retain its App Group entitlements
                    # under a normal Xcode Run, not only under CI command overrides.
                    assert settings["CODE_SIGNING_ALLOWED"] == "YES"
                    assert settings["CODE_SIGNING_REQUIRED"] == "YES"
                    assert settings["CODE_SIGN_STYLE"] == "Automatic"
                    assert settings["DEVELOPMENT_TEAM"] == "NA6HPWARQ2"
                    assert settings["CODE_SIGN_ENTITLEMENTS"] == "HanlinMiniAppsApp/HanlinMiniApps.entitlements"
                    assert settings["INFOPLIST_FILE"] == "HanlinMiniAppsApp/Info.plist"
                else:
                    assert settings["CODE_SIGNING_ALLOWED"] == "NO"
                    assert settings["CODE_SIGNING_REQUIRED"] == "NO"
                    assert "CODE_SIGN_ENTITLEMENTS" not in settings
                    assert "DEVELOPMENT_TEAM" not in settings
                assert "baseConfigurationReference" not in objects[key]
            else:
                assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == "com.itorah.chavrusachat"
    return {"miniapps_products": sorted(products), "miniapps_source_groups": groups,
            "deployment_target": "27.0", "signed_or_install_proof": False}


def validate_agent_sdk_linkage(project, repository):
    """Verify real target membership, without claiming Xcode compilation."""
    objects = project["objects"]
    root = objects[project["rootObject"]]
    packages = [key for key in root["packageReferences"]
                if objects[key].get("relativePath") == "Packages/HanlinAgentSDK"]
    assert len(packages) == 1, "Exactly one canonical local SDK package is required"
    package = packages[0]
    expected = {"HanlinHostContracts", "HanlinAgentCore", "HanlinPersistenceAdapters"}
    products = {key: value["productName"] for key, value in objects.items()
                if value.get("isa") == "XCSwiftPackageProductDependency"
                and value.get("package") == package}
    assert len(products) == 3 and set(products.values()) == expected, "SDK product identity mismatch"
    targets = {objects[key]["name"]: (key, objects[key]) for key in root["targets"]}
    assert {"AI_Hanlin", "AI_HLYTests", "HanlinMiniApps"} <= targets.keys()
    for name, (_, target) in targets.items():
        required = expected if name == "AI_Hanlin" else {"HanlinAgentCore"} if name == "AI_HLYTests" else set()
        declared = [products[key] for key in target.get("packageProductDependencies", []) if key in products]
        linked = [products[objects[file]["productRef"]]
                  for phase in target["buildPhases"] if objects[phase]["isa"] == "PBXFrameworksBuildPhase"
                  for file in objects[phase]["files"] if objects[file].get("productRef") in products]
        assert len(declared) == len(required) and set(declared) == required, name + ": unexpected SDK dependency"
        assert len(linked) == len(required) and set(linked) == required, name + ": SDK product is not actually linked"
    ai_id, ai = targets["AI_Hanlin"]
    groups = [objects[key] for key in ai["fileSystemSynchronizedGroups"]
              if objects[key].get("path") == "AI_HLY"]
    assert len(groups) == 1, "AI must retain its synchronized source folder"
    adapter = "Model/HanlinAppleModelCatalogAdapter.swift"
    for exception_id in groups[0].get("exceptions", []):
        exception = objects[exception_id]
        if exception.get("target") == ai_id:
            assert not any(adapter == path or adapter.startswith(path.rstrip("/") + "/")
                           for path in exception.get("membershipExceptions", [])), "Native adapter excluded from AI"
    repository = Path(repository)
    assert (repository / "AI_HLY" / adapter).is_file(), "Canonical native adapter source is missing"
    for sibling in ("HanlinAgentSDK", "HanlinPlatform"):
        for filename in ("Package.swift", "Package.resolved"):
            assert (repository / "Packages" / sibling / filename).is_file(), "Incomplete literal sibling package graph"
    return {"ai_products": sorted(expected), "unit_test_products": ["HanlinAgentCore"],
            "miniapps_sdk_products": [], "synchronized_adapter": adapter,
            "apple_compilation": "NOT_RUN"}
