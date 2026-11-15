"""Create a disposable UI target using the real whole Swift Parity package."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "IntegrationValidation"))
from extract_target import render


def prepare(repo: Path, output: Path):
    output.mkdir(parents=True, exist_ok=False)
    objects = {}

    def add(object_key, **values):
        key = hashlib.sha256(object_key.encode()).hexdigest()[:24].upper()
        objects[key] = values
        return key

    source_files = []
    hashes = {}
    for name in ["ParityApp.swift", "ParityUITests.swift"]:
        path = repo / "Scripts/CI/SimulatorAcceptance" / name
        data = path.read_bytes()
        (output / name).write_bytes(data)
        hashes[path.relative_to(repo).as_posix()] = hashlib.sha256(data).hexdigest()
        ref = add(name, isa="PBXFileReference", lastKnownFileType="sourcecode.swift", path=name, sourceTree="<group>")
        source_files.append(add(name + "-build", isa="PBXBuildFile", fileRef=ref))
    app_product = add("app-product", isa="PBXFileReference", explicitFileType="wrapper.application", path="HanlinParityUI.app", sourceTree="BUILT_PRODUCTS_DIR")
    test_product = add("test-product", isa="PBXFileReference", explicitFileType="wrapper.cfbundle", path="HanlinParityUITests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
    products = add("products", isa="PBXGroup", name="Products", sourceTree="<group>", children=[app_product, test_product])
    group = add("main-group", isa="PBXGroup", sourceTree="<group>", children=[*list(objects)[:1], products])
    objects[group]["children"] = [key for key, value in objects.items() if value.get("lastKnownFileType") == "sourcecode.swift"] + [products]
    packages = []
    package_products = []
    package_builds = []
    for package, names in [("HanlinParityMiniApp", ["HanlinParityMiniApp"]), ("HanlinPlatform", ["HanlinMiniAppCore", "HanlinPlatformContracts"])]:
        ref = add(package, isa="XCLocalSwiftPackageReference", relativePath=str((repo / "Packages" / package).resolve()).replace("\\", "/"))
        packages.append(ref)
        for name in names:
            product = add(name + "-product", isa="XCSwiftPackageProductDependency", package=ref, productName=name)
            package_products.append(product)
            package_builds.append(add(name + "-link", isa="PBXBuildFile", productRef=product))

    def configurations(name, settings):
        refs = []
        for mode in ["Debug", "Release"]:
            refs.append(add(name + mode, isa="XCBuildConfiguration", name=mode, buildSettings=settings))
        return add(name + "-configs", isa="XCConfigurationList", buildConfigurations=refs, defaultConfigurationIsVisible="0", defaultConfigurationName="Release")

    base = {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "27.0", "SUPPORTED_PLATFORMS": "iphonesimulator", "SWIFT_VERSION": "6.0", "CODE_SIGNING_ALLOWED": "NO", "GENERATE_INFOPLIST_FILE": "YES", "TARGETED_DEVICE_FAMILY": "1,2", "ENABLE_TESTABILITY": "YES"}
    app_settings = dict(base, PRODUCT_NAME="HanlinParityUI", PRODUCT_BUNDLE_IDENTIFIER="com.itorah.hanlin.simulatoracceptance.parity", INFOPLIST_KEY_UILaunchScreen_Generation="YES", CURRENT_PROJECT_VERSION="1", MARKETING_VERSION="1.0")
    app_sources = add("app-sources", isa="PBXSourcesBuildPhase", files=[source_files[0]], buildActionMask="2147483647", runOnlyForDeploymentPostprocessing="0")
    app_frameworks = add("app-frameworks", isa="PBXFrameworksBuildPhase", files=package_builds, buildActionMask="2147483647", runOnlyForDeploymentPostprocessing="0")
    app = add("app", isa="PBXNativeTarget", name="HanlinParityUI", productName="HanlinParityUI", productType="com.apple.product-type.application", productReference=app_product, buildConfigurationList=configurations("app", app_settings), buildPhases=[app_sources, app_frameworks], buildRules=[], dependencies=[], packageProductDependencies=package_products)
    dependency = add("test-dependency", isa="PBXTargetDependency", target=app)
    test_sources = add("test-sources", isa="PBXSourcesBuildPhase", files=[source_files[1]], buildActionMask="2147483647", runOnlyForDeploymentPostprocessing="0")
    test_settings = dict(base, PRODUCT_NAME="HanlinParityUITests", PRODUCT_BUNDLE_IDENTIFIER="com.itorah.hanlin.simulatoracceptance.parity.uitests", TEST_TARGET_NAME="HanlinParityUI")
    tests = add("tests", isa="PBXNativeTarget", name="HanlinParityUITests", productName="HanlinParityUITests", productType="com.apple.product-type.bundle.ui-testing", productReference=test_product, buildConfigurationList=configurations("tests", test_settings), buildPhases=[test_sources], buildRules=[], dependencies=[dependency], packageProductDependencies=[])
    project = add("project", isa="PBXProject", attributes={"LastUpgradeCheck": "2700"}, buildConfigurationList=configurations("project", {}), compatibilityVersion="Xcode 14.0", developmentRegion="en", knownRegions=["en", "he"], mainGroup=group, productRefGroup=products, projectDirPath="", projectRoot="", targets=[app, tests], packageReferences=packages)
    project_dir = output / "Parity.xcodeproj"
    project_dir.mkdir()
    (project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + render({"archiveVersion": "1", "classes": {}, "objectVersion": "60", "objects": objects, "rootObject": project}) + "\n", encoding="utf-8", newline="\n")
    scheme = ET.Element("Scheme", version="1.7", LastUpgradeVersion="2700")
    build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="NO", buildImplicitDependencies="YES")
    entries = ET.SubElement(build, "BuildActionEntries")

    def reference(parent, target, name, product):
        return ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target, BuildableName=product, BlueprintName=name, ReferencedContainer="container:Parity.xcodeproj")

    for target, name, product in [(app, "HanlinParityUI", "HanlinParityUI.app"), (tests, "HanlinParityUITests", "HanlinParityUITests.xctest")]:
        reference(ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES", buildForProfiling="NO", buildForArchiving="NO", buildForAnalyzing="YES"), target, name, product)
    action = ET.SubElement(scheme, "TestAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="NO")
    reference(ET.SubElement(ET.SubElement(action, "Testables"), "TestableReference", skipped="NO", parallelizable="NO"), tests, "HanlinParityUITests", "HanlinParityUITests.xctest")
    schemes = project_dir / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True)
    ET.indent(scheme)
    ET.ElementTree(scheme).write(schemes / "HanlinParityUI.xcscheme", encoding="utf-8", xml_declaration=True)
    (output / "source-inputs.json").write_text(json.dumps({"scope": "compiled-swift-parity-miniapp-ui-only", "full_app_acceptance": False, "wrapper_sha256": hashes}, indent=2) + "\n", encoding="utf-8", newline="\n")
    return {"objects": len(objects), "scope": "compiled-swift-parity-miniapp-ui-only", "full_app_acceptance": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.repo.resolve(), args.output.resolve())))
