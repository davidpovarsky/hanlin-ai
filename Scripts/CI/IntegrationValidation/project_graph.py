"""Read the checked-in OpenStep project without Xcode or third-party packages."""
import re
import hashlib


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
            assert {k: v for k, v in clone.items() if k != "files"} == {
                k: v for k, v in original.items() if k != "files"
            }, "Native preparation must reuse the existing build command"
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
                assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == "com.itorah.hanlinminiapps.integration"
                assert settings["SUPPORTED_PLATFORMS"] == "iphonesimulator"
                assert settings["CODE_SIGNING_ALLOWED"] == "NO"
                assert settings["CODE_SIGNING_REQUIRED"] == "NO"
                assert "CODE_SIGN_ENTITLEMENTS" not in settings
                assert "DEVELOPMENT_TEAM" not in settings
                assert "baseConfigurationReference" not in objects[key]
            else:
                assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == "com.itorah.chavrusachat"
    return {"miniapps_products": sorted(products), "miniapps_source_groups": groups,
            "deployment_target": "27.0", "signed_or_install_proof": False}
