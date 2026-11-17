"""Validate actual production target boundaries; source validation is not iOS proof."""
from pathlib import Path
import json
import plistlib
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts/CI/IntegrationValidation"))
from project_graph import parse_project, validate_graph, validate_agent_sdk_linkage


def main():
    # The parser rejects duplicate IDs/keys and reads quoted and ordinary OpenStep alike.
    project = parse_project((ROOT / "AI_HLY.xcodeproj/project.pbxproj").read_text(encoding="utf-8"))
    objects = project["objects"]
    root = objects[project["rootObject"]]
    targets = {objects[key]["name"]: (key, objects[key]) for key in root["targets"]}
    assert len(targets) == len(root["targets"]), "Duplicate target names"
    provider = json.loads((ROOT / "Scripts/CI/IntegrationValidation/miniapps_provider_sources.json").read_text())
    membership = json.loads((ROOT / "docs/product-split/target-membership.json").read_text())
    assert provider["product_stage"] == "standalone-production-bundle-unsigned"
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
        if resource != "AI_HLY/RuntimeHostResources.zip":
            assert (ROOT / resource).is_file(), resource
    mini_id, mini = targets["HanlinMiniApps"]
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
