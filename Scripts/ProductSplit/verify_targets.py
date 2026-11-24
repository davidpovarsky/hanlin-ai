"""Validate actual production target boundaries; source validation is not iOS proof."""
from pathlib import Path
import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts/CI/IntegrationValidation"))
from project_graph import parse_project, validate_graph, validate_agent_sdk_linkage


def validate_native_test_membership():
    """Catch an omitted XCTest file before an expensive real application build."""
    project = parse_project((ROOT / "AI_HLY.xcodeproj/project.pbxproj").read_text(encoding="utf-8"))
    objects = project["objects"]
    target = next(value for value in objects.values()
                  if value.get("isa") == "PBXNativeTarget" and value.get("name") == "HanlinMiniAppsUITests")
    source_phases = [objects[key] for key in target["buildPhases"]
                     if objects[key].get("isa") == "PBXSourcesBuildPhase"]
    paths = [objects[objects[key]["fileRef"]]["path"]
             for phase in source_phases for key in phase["files"]]
    expected = {path.relative_to(ROOT).as_posix()
                for path in (ROOT / "HanlinMiniAppsUITests").glob("*.swift")}
    # The original provider test is intentionally shared outside the target directory.
    expected.add("Scripts/CI/IntegrationValidation/MiniAppsProviderUITests.swift")
    if not expected or len(paths) != len(set(paths)) or set(paths) != expected:
        raise RuntimeError("MiniApps UI-test target membership mismatch: " + json.dumps({
            "omitted": sorted(expected - set(paths)), "unexpected": sorted(set(paths) - expected),
            "duplicates": len(paths) != len(set(paths))}))
    return sorted(paths)



def native_ui_typecheck_command(architecture, sdk_path, platform_path, sources):
    """Typecheck the actual XCTest-only UI target before expensive app compilation."""
    project = parse_project((ROOT / "AI_HLY.xcodeproj/project.pbxproj").read_text(encoding="utf-8"))
    objects = project["objects"]
    target = next(value for value in objects.values()
                  if value.get("isa") == "PBXNativeTarget" and value.get("name") == "HanlinMiniAppsUITests")
    scheme = ET.parse(ROOT / "AI_HLY.xcodeproj/xcshareddata/xcschemes/HanlinMiniApps.xcscheme")
    configuration = scheme.getroot().find("TestAction").attrib["buildConfiguration"]
    settings = {}
    for owner in (objects[project["rootObject"]], target):
        config = next(objects[key] for key in objects[owner["buildConfigurationList"]]["buildConfigurations"]
                      if objects[key]["name"] == configuration)
        settings.update(config["buildSettings"])
    # Match the actual UI compiler command captured in run 45316423267.
    # This target imports XCTest only; no app or third-party replacement module
    # is used, and its full original Xcode build and execution remain required.
    swift_version = str(settings["SWIFT_VERSION"]).split(".")[0]
    deployment = settings["IPHONEOS_DEPLOYMENT_TARGET"]
    command = ["xcrun", "--sdk", "iphonesimulator", "swiftc", "-typecheck",
               "-module-name", "HanlinMiniAppsUITests", "-swift-version", swift_version,
               "-target", f"{architecture}-apple-ios{deployment}-simulator", "-sdk", str(sdk_path),
               "-F", str(Path(platform_path) / "Developer/Library/Frameworks"),
               "-F", str(Path(sdk_path) / "Developer/Library/Frameworks"),
               "-enable-experimental-feature", "DebugDescriptionMacro"]
    conditions = settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "").split()
    for condition in conditions:
        if condition != "$(inherited)":
            command += ["-D", condition]
    if settings.get("SWIFT_DEFAULT_ACTOR_ISOLATION"):
        command += ["-default-isolation", settings["SWIFT_DEFAULT_ACTOR_ISOLATION"]]
    if settings.get("SWIFT_STRICT_CONCURRENCY"):
        command += ["-strict-concurrency=" + settings["SWIFT_STRICT_CONCURRENCY"]]
    return command + list(sources)


def main():
    validate_native_test_membership()
    # The parser rejects duplicate IDs/keys and reads quoted and ordinary OpenStep alike.
    project_text = (ROOT / "AI_HLY.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    project = parse_project(project_text)
    objects = project["objects"]
    root = objects[project["rootObject"]]
    targets = {objects[key]["name"]: (key, objects[key]) for key in root["targets"]}
    assert len(targets) == len(root["targets"]), "Duplicate target names"
    provider = json.loads((ROOT / "Scripts/CI/IntegrationValidation/miniapps_provider_sources.json").read_text())
    membership = json.loads((ROOT / "docs/product-split/target-membership.json").read_text())
    assert provider["product_stage"] == "standalone-production-bundle"
    graph_result = validate_graph(project, provider)
    sdk_result = validate_agent_sdk_linkage(project, ROOT)
    sources = membership["shared_sources"]
    assert len(sources) == len(set(sources)), "Duplicate shared sources"
    assert set(sources) == set(provider["swift_sources"] + provider["native_sources"])
    for source in sources:
        assert (ROOT / source).is_file(), source
        assert not any(part in source for part in ["/ChatInput/", "/ChatView.swift", "/Views/Components/Chat", "/Model/APIKeys.swift"]), source
    assert not set(membership["excludes"]).intersection(sources)
    assert set(membership["shared_resources"]) == set(provider["resources"])
    for resource in membership["shared_resources"]:
        if resource == "AI_HLY/Assets.xcassets":
            catalog = ROOT / resource
            assert catalog.is_dir() and (catalog / "Contents.json").is_file()
            icon = catalog / "AppIcon.appiconset"
            images = json.loads((icon / "Contents.json").read_text())["images"]
            assert images and all((icon / item["filename"]).is_file() for item in images)
        elif resource != "AI_HLY/RuntimeHostResources.zip":
            assert (ROOT / resource).is_file(), resource
    mini_id, mini = targets["HanlinMiniApps"]
    # Validate the executable OpenStep string literals, which the graph
    # parser does not newline-decode. Generic JSON serialization previously
    # double-escaped the copied MiniApps scripts.
    def script_literal(identifier):
        object_start = re.search(r'"?' + identifier + r'"?[^\n]*= \{', project_text)
        assert object_start, identifier
        value = re.search(r'"?shellScript"? = ("(?:\\.|[^"\\])*")', project_text[object_start.end():])
        assert value, identifier
        return value.group(1)

    ai = objects["D7B6C3C02D50A55D004E3AD6"]
    scripts = lambda target: {objects[key]["name"]: key for key in target["buildPhases"]
                              if objects[key].get("isa") == "PBXShellScriptBuildPhase"}
    ai_scripts, mini_scripts = scripts(ai), scripts(mini)
    for name in ["Generate NativeScript metadata", "Process Python libraries"]:
        original = script_literal(ai_scripts[name])
        assert script_literal(mini_scripts[name]) == original, name + " script encoding drift"
        assert "\n" in json.loads(original), name + " lost executable line breaks"
    # Both products execute the same original metadata/Python scripts. These
    # scripts create dynamic directory contents; Xcode's dependency sandbox
    # cannot represent recursive output trees. Preserve original AI build
    # semantics. This setting does not alter the iOS app sandbox or permissions.
    io_root = ROOT / "Scripts/ProductSplit/BuildIO"
    io_manifest = json.loads((io_root / "manifest.json").read_text())
    runtime_lock = json.loads((ROOT / "RuntimeDependencies.lock.json").read_text())
    assert io_manifest["python_archive_sha256"] == runtime_lock["python"]["archive"]["sha256"]
    for filename, expected in io_manifest["file_lists"].items():
        actual = (io_root / filename).read_text().splitlines()
        assert actual == expected and len(actual) == len(set(actual)), filename
        assert all(path.startswith("$(") for path in actual), filename
        assert "$(SRCROOT)" not in actual and "/" not in actual, filename
    for name, stem in [("Generate NativeScript metadata", "metadata"), ("Process Python libraries", "python")]:
        phase = objects[mini_scripts[name]]
        for kind in ["input", "output"]:
            assert phase[kind + "FileListPaths"] == [
                "$(SRCROOT)/Scripts/ProductSplit/BuildIO/" + stem + "-" + kind + "s.xcfilelist"], name
    original_build_settings = {
        objects[key]["name"]: objects[key]["buildSettings"]
        for key in objects[ai["buildConfigurationList"]]["buildConfigurations"]
    }
    for config_id in objects[mini["buildConfigurationList"]]["buildConfigurations"]:
        configuration = objects[config_id]
        settings = configuration["buildSettings"]
        original = original_build_settings[configuration["name"]]
        assert settings["ENABLE_USER_SCRIPT_SANDBOXING"] == original["ENABLE_USER_SCRIPT_SANDBOXING"] == "NO"
        assert settings["PYTHONDONTWRITEBYTECODE"] == "1"
        assert settings["ASSETCATALOG_COMPILER_APPICON_NAME"] == original["ASSETCATALOG_COMPILER_APPICON_NAME"] == "AppIcon"
        assert "@executable_path/Frameworks" in settings.get("LD_RUNPATH_SEARCH_PATHS", []), "Standalone product must find its own embedded frameworks"
    for name in ["HanlinMiniAppsTests", "HanlinMiniAppsUITests", "HanlinMiniAppsBootstrapTests"]:
        target_id, target = targets[name]
        if name != "HanlinMiniAppsBootstrapTests":
            assert any(objects[key].get("target") == mini_id for key in target["dependencies"]), name
        for config_id in objects[target["buildConfigurationList"]]["buildConfigurations"]:
            settings = objects[config_id]["buildSettings"]
            assert settings["IPHONEOS_DEPLOYMENT_TARGET"] == "27.0", name
            assert settings["SWIFT_VERSION"] == "6.0", name
    scheme = ET.parse(ROOT / "AI_HLY.xcodeproj/xcshareddata/xcschemes/HanlinMiniApps.xcscheme")
    refs = scheme.findall(".//Testables//BuildableReference")
    assert {node.attrib["BlueprintName"] for node in refs} == {
        "HanlinMiniAppsUITests", "HanlinMiniAppsTests", "HanlinMiniAppsBootstrapTests"}
    for node in refs:
        assert targets[node.attrib["BlueprintName"]][0] == node.attrib["BlueprintIdentifier"]
    entitlements = plistlib.loads((ROOT / "HanlinMiniAppsApp/HanlinMiniApps.entitlements").read_bytes())
    assert set(entitlements["com.apple.security.application-groups"]) == {
        "group.com.itorah.chavrusachat", "group.com.itorah.shared"}
    assert "com.apple.developer.icloud-container-identifiers" not in entitlements
    info = plistlib.loads((ROOT / "HanlinMiniAppsApp/Info.plist").read_bytes())
    assert info["UTImportedTypeDeclarations"]
    assert info["CFBundleURLTypes"][0]["CFBundleURLSchemes"] == ["hanlinminiapps"]
    assert "chavrusachat" in info["LSApplicationQueriesSchemes"]
    ai_info = plistlib.loads((ROOT / "AI-HLY-Info.plist").read_bytes())
    assert {"maktabah", "hanlinminiapps"} <= set(ai_info["LSApplicationQueriesSchemes"])
    assert any("chavrusachat" in item["CFBundleURLSchemes"] for item in ai_info["CFBundleURLTypes"])
    assert info["CFBundleDocumentTypes"][0]["LSItemContentTypes"] == [
        "com.hanlin.scripting-package", "public.zip-archive"]
    manifest = (ROOT / "Packages/HanlinProductSplit/Package.swift").read_text()
    for name in ["SplitFixtureStore.swift", "SplitReceiverFixturePersistence.swift", "SplitMigrationFixturePersistence.swift"]:
        assert name in manifest, name
    assert 'name: "RegisteredIntegrationTests"' in manifest
    print(json.dumps({"status": "SOURCE_VALIDATED", "shared_source_count": len(sources),
                      "graph": graph_result, "sdk": sdk_result,
                      "ios_build": "NOT_RUN", "ios_ui": "NOT_RUN", "signed_group": "NOT_RUN"}))


if __name__ == "__main__":
    main()
