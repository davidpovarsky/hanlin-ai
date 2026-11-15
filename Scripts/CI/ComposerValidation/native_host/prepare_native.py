"""Generate a zero-package, real app-hosted native unit-test project.

Pure packet generation is available for source review in memory. Only an explicit
Mac staging call materializes the unchanged canonical files for a future run.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parents[1] / "IntegrationValidation"))
from prepare_capability_proof import SOURCES, TEST_SOURCE, EDITOR_TEST_SOURCE, APP_INPUTS
from extract_target import render
from project_graph import parse_project

SOURCE = "e8ccd81452843609285a0cd7e017a759bda6a6ef"
OWNER = "20980c9448f0a5d78eefcaec38da6e92364de37d"
PROJECT = "ComposerNativeHost.xcodeproj"
SCHEME = "ComposerNativeHost"
HOST_PATH = "Infrastructure/ComposerNativeUnitHost.swift"


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def frozen_inputs(repo):
    paths = [*SOURCES, TEST_SOURCE, EDITOR_TEST_SOURCE, *APP_INPUTS]
    return {path: subprocess.check_output(["git", "-C", str(repo), "show", SOURCE + ":" + path],
                                         timeout=30) for path in paths}


def provenance(repo):
    """Read the frozen project pattern and shared infrastructure without editing it."""
    paths = ['AI_HLY.xcodeproj/project.pbxproj',
             'Scripts/CI/SimulatorAcceptance/prepare_parity_project.py',
             'Scripts/CI/IntegrationValidation/extract_target.py',
             'Scripts/CI/IntegrationValidation/project_graph.py']
    blobs = {p: subprocess.check_output(['git', '-C', str(repo), 'show', SOURCE + ':' + p], timeout=30)
             for p in paths}
    objects = parse_project(blobs[paths[0]].decode('utf-8-sig'))['objects']
    target = next(obj for obj in objects.values()
                  if obj.get('isa') == 'PBXNativeTarget' and obj.get('name') == 'AI_HLYTests')
    assert target['productType'] == 'com.apple.product-type.bundle.unit-test'
    mapping = {}
    for key in objects[target['buildConfigurationList']]['buildConfigurations']:
        config = objects[key]
        settings = config['buildSettings']
        assert settings['TEST_HOST'] == '$(BUILT_PRODUCTS_DIR)/AI_Hanlin.app/AI_Hanlin'
        assert settings['BUNDLE_LOADER'] == '$(TEST_HOST)'
        mapping[config['name']] = {name: settings[name] for name in ['TEST_HOST', 'BUNDLE_LOADER']}
    # The imported renderer/reader must be the reviewed shared bytes as well.
    for path in paths[2:]:
        assert (repo / path).read_bytes() == blobs[path], 'shared reader/renderer differs from frozen reference'
    return {'reference_commit': SOURCE, 'read_only_reference_sha256': {p: digest(raw) for p, raw in blobs.items()},
            'checked_in_native_unit_target': 'AI_HLYTests', 'host_loading_pattern': mapping,
            'prior_validation_package_sha256_reference_only': 'f529f2843080de42fccc5f0c5879b2674caaa976de0fadeaa4db606dde71cc8d'}


def make_packet(contents, host):
    assert set(contents) == set([*SOURCES, TEST_SOURCE, EDITOR_TEST_SOURCE, *APP_INPUTS])
    tests = [TEST_SOURCE, EDITOR_TEST_SOURCE]
    ids = []
    for path, suite in [(TEST_SOURCE, "HanlinMorphComposerTests"),
                        (EDITOR_TEST_SOURCE, "NativeComposerLineSizingTests")]:
        names = re.findall(r"@Test(?:\([^\n]*\))?\s+func\s+(\w+)\s*\(", contents[path].decode("utf-8-sig"))
        assert len(names) == (7 if path == TEST_SOURCE else 5) and len(set(names)) == len(names)
        ids += [f"{suite}/{name}()" for name in names]
    compiled = [*SOURCES, *tests]
    directives = {
        path: [{"line": i, "text": line.strip()} for i, line in enumerate(
            contents[path].decode("utf-8-sig").splitlines(), 1)
            if line.lstrip().startswith(("#if", "#elseif", "#else", "#endif"))]
        for path in compiled
    }
    assert not any("SWIFT_PACKAGE" in contents[p].decode("utf-8-sig") for p in compiled)
    objects = {}

    def oid(name):
        return digest(("native-composer-host:" + name).encode())[:24].upper()

    def add(identity, **values):
        key = oid(identity)
        assert key not in objects
        objects[key] = values
        return key

    files = {}
    staged = {}
    for path in compiled:
        native = "Canonical/" + path
        ref = add("file:" + path, isa="PBXFileReference", lastKnownFileType="sourcecode.swift",
                  path=native, sourceTree="SOURCE_ROOT")
        files[path] = add("build:" + path, isa="PBXBuildFile", fileRef=ref)
        staged[native] = contents[path]
    host_ref = add("host-file", isa="PBXFileReference", lastKnownFileType="sourcecode.swift",
                   path=HOST_PATH, sourceTree="SOURCE_ROOT")
    host_build = add("host-build", isa="PBXBuildFile", fileRef=host_ref)
    staged[HOST_PATH] = host
    app_product = add("app-product", isa="PBXFileReference", explicitFileType="wrapper.application",
                      path="AI_Hanlin.app", sourceTree="BUILT_PRODUCTS_DIR")
    test_product = add("test-product", isa="PBXFileReference", explicitFileType="wrapper.cfbundle",
                       path="AI_HanlinTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
    products = add("products", isa="PBXGroup", name="Products", sourceTree="<group>",
                   children=[app_product, test_product])
    main_group = add("main-group", isa="PBXGroup", sourceTree="<group>",
                     children=[key for key, obj in objects.items()
                               if obj.get("lastKnownFileType") == "sourcecode.swift"] + [products])
    base = {
        "SDKROOT": "iphonesimulator", "SUPPORTED_PLATFORMS": "iphonesimulator",
        "IPHONEOS_DEPLOYMENT_TARGET": "27.0", "TARGETED_DEVICE_FAMILY": "1,2",
        "SWIFT_VERSION": "6.0", "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG Xcode $(inherited)",
        "ENABLE_TESTABILITY": "YES", "CLANG_ENABLE_MODULES": "YES",
        "CODE_SIGNING_ALLOWED": "NO", "CODE_SIGNING_REQUIRED": "NO",
        "GENERATE_INFOPLIST_FILE": "YES",
        "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    }

    def configs(name, settings):
        config = add(name + "-debug", isa="XCBuildConfiguration", name="Debug", buildSettings=settings)
        return add(name + "-configs", isa="XCConfigurationList", buildConfigurations=[config],
                   defaultConfigurationIsVisible="0", defaultConfigurationName="Debug")

    def phase(name, kind, members):
        return add(name, isa=kind, files=members, buildActionMask="2147483647",
                   runOnlyForDeploymentPostprocessing="0")

    app_id = oid("app")
    project_id = oid("project")
    app = add("app", isa="PBXNativeTarget", name="AI_Hanlin", productName="AI_Hanlin",
              productType="com.apple.product-type.application", productReference=app_product,
              buildConfigurationList=configs("app", dict(
                  base, PRODUCT_NAME="AI_Hanlin", PRODUCT_MODULE_NAME="AI_Hanlin",
                  PRODUCT_BUNDLE_IDENTIFIER="com.itorah.hanlin.composer-native-unit-host",
                  DEFINES_MODULE="YES", CURRENT_PROJECT_VERSION="1", MARKETING_VERSION="1.0",
                  INFOPLIST_KEY_UILaunchScreen_Generation="YES",
                  INFOPLIST_KEY_UIApplicationSceneManifest_Generation="YES")),
              buildPhases=[phase("app-sources", "PBXSourcesBuildPhase",
                                 [files[p] for p in SOURCES] + [host_build]),
                           phase("app-frameworks", "PBXFrameworksBuildPhase", []),
                           phase("app-resources", "PBXResourcesBuildPhase", [])],
              buildRules=[], dependencies=[], packageProductDependencies=[])
    proxy = add("test-host-proxy", isa="PBXContainerItemProxy", containerPortal=project_id,
                proxyType="1", remoteGlobalIDString=app_id, remoteInfo="AI_Hanlin")
    dependency = add("test-host-dependency", isa="PBXTargetDependency", target=app, targetProxy=proxy)
    unit = add("unit-tests", isa="PBXNativeTarget", name="AI_HanlinTests", productName="AI_HanlinTests",
               productType="com.apple.product-type.bundle.unit-test", productReference=test_product,
               buildConfigurationList=configs("tests", dict(
                   base, PRODUCT_NAME="AI_HanlinTests", PRODUCT_MODULE_NAME="AI_HanlinTests",
                   PRODUCT_BUNDLE_IDENTIFIER="com.itorah.hanlin.composer-native-unit-host.tests",
                   TEST_HOST="$(BUILT_PRODUCTS_DIR)/AI_Hanlin.app/AI_Hanlin",
                   BUNDLE_LOADER="$(TEST_HOST)",
                   LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks",
                                           "@loader_path/Frameworks"])),
               buildPhases=[phase("test-sources", "PBXSourcesBuildPhase", [files[p] for p in tests]),
                            phase("test-frameworks", "PBXFrameworksBuildPhase", []),
                            phase("test-resources", "PBXResourcesBuildPhase", [])],
               buildRules=[], dependencies=[dependency], packageProductDependencies=[])
    project = add("project", isa="PBXProject",
                  attributes={"LastUpgradeCheck": "2700", "TargetAttributes": {
                      app: {"CreatedOnToolsVersion": "27.2"},
                      unit: {"CreatedOnToolsVersion": "27.2", "TestTargetID": app}}},
                  buildConfigurationList=configs("project", {}),
                  compatibilityVersion="Xcode 14.0", developmentRegion="en",
                  knownRegions=["en", "he"], mainGroup=main_group, productRefGroup=products,
                  projectDirPath="", projectRoot="", targets=[app, unit], packageReferences=[])
    graph = {"archiveVersion": "1", "classes": {}, "objectVersion": "60",
             "objects": objects, "rootObject": project}
    pbx = ("// !$*UTF8*$!\n" + render(graph) + "\n").encode()
    assert parse_project(pbx.decode()) == graph
    scheme = ET.Element("Scheme", version="1.7", LastUpgradeVersion="2700")

    def reference(parent, target, name, product):
        return ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary",
                             BlueprintIdentifier=target, BuildableName=product,
                             BlueprintName=name, ReferencedContainer="container:" + PROJECT)

    build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="NO", buildImplicitDependencies="YES")
    entries = ET.SubElement(build, "BuildActionEntries")
    for target, name, product in [(app, "AI_Hanlin", "AI_Hanlin.app"),
                                  (unit, "AI_HanlinTests", "AI_HanlinTests.xctest")]:
        reference(ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES",
                               buildForRunning="YES" if target == app else "NO",
                               buildForProfiling="NO", buildForArchiving="NO", buildForAnalyzing="YES"),
                  target, name, product)
    action = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug",
                           shouldUseLaunchSchemeArgsEnv="YES",
                           selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                           selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB")
    reference(ET.SubElement(ET.SubElement(action, "Testables"), "TestableReference",
                           skipped="NO", parallelizable="NO"), unit,
              "AI_HanlinTests", "AI_HanlinTests.xctest")
    reference(ET.SubElement(action, "MacroExpansion"), app, "AI_Hanlin", "AI_Hanlin.app")
    ET.indent(scheme)
    xml = ET.tostring(scheme, encoding="utf-8", xml_declaration=True) + b"\n"
    generated = {PROJECT + "/project.pbxproj": pbx,
                 PROJECT + "/xcshareddata/xcschemes/" + SCHEME + ".xcscheme": xml}
    manifest = {
        "scope": "native-hosted-component-unit-test-infrastructure", "full_app_acceptance": False,
        "source": SOURCE, "owner": OWNER, "status": "SOURCE_ONLY_NOT_COMPILED",
        "original_reference_input_sha256": {p: digest(raw) for p, raw in sorted(contents.items())},
        "native_canonical_sources": [
            {"original": p, "native": "Canonical/" + p, "sha256": digest(contents[p]),
             "target": "AI_Hanlin" if p in SOURCES else "AI_HanlinTests"} for p in compiled],
        "reference_only_not_compiled": list(APP_INPUTS),
        "native_infrastructure_sources": {HOST_PATH: digest(host)},
        "generated_infrastructure_sha256": {p: digest(raw) for p, raw in generated.items()},
        "expected_case_ids": ids, "reference_compiled_file_count": 10,
        "native_compiled_file_count": 11, "package_references": 0,
        "conditional_directive_audit": directives,
        "compilation_condition_mapping": {
            "prior_actual_run": "43691033216", "prior_source": "51d3fa350f6908526c6a78e4858b40122cc4f2f0",
            "prior_github_cli_log_sha256": "9ae53b7446817a4d76f93fe465a01c8b21bf20e7e65b3e29c6dfc52ed651b687",
            "prior_observed_swift_conditions": ["SWIFT_PACKAGE", "DEBUG", "SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE", "Xcode"],
            "native_explicit_swift_conditions": ["DEBUG", "Xcode"],
            "SWIFT_PACKAGE_dependency_in_compiled_frozen_files": False,
            "omitted_unused_package_conditions": ["SWIFT_PACKAGE", "SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE"],
            "canImport_UIKit": "required true for both iOS environments; actual compiler verification still NOT_RUN",
            "language": "Swift6", "optimization": "-Onone", "testability": True,
            "concurrency_overrides": "none; no app-specific default-actor/approachable-concurrency override copied",
        },
        "declared_environment_differences": [
            "native real UIApplication host and hosted unit-test bundle, rather than synthesized SwiftPM runner",
            "explicit iOS27 minimum instead of prior validation Package iOS26 minimum",
            "zero Swift packages and no package resources; old Package.swift is reference only, not native input",
            "new minimal clear host scene; canonical component code/tests/math/probes are unchanged",
            "actual effective native build settings, loading and runtime metrics remain NOT_RUN"],
        "target_ids": {"app": app, "unit": unit, "project": project},
    }
    return generated, staged, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if sys.platform != "darwin":
        raise SystemExit("Mac staging only; use make_packet in memory for source review")
    generated, staged, manifest = make_packet(frozen_inputs(REPO), (HERE / "ComposerNativeUnitHost.swift").read_bytes())
    manifest['read_only_pattern_provenance'] = provenance(REPO)
    from validate_packet import validate, controls
    originals = frozen_inputs(REPO)
    validate(generated, staged, manifest, originals)
    controls(generated, staged, manifest, originals)
    args.output.mkdir(parents=True, exist_ok=False)
    for path, raw in {**generated, **staged}.items():
        dest = args.output / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(raw)
    (args.output / "native-inputs.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": manifest["status"], "expected_cases": len(manifest["expected_case_ids"]),
                      "packages": 0, "full_app_acceptance": False}))


if __name__ == "__main__":
    main()
