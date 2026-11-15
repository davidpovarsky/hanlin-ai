"""Read the checked-in OpenStep project without Xcode or third-party packages."""
import re


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


def validate_graph(project):
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
    assert {objects[key]["isa"] for key in mini["buildPhases"]} == {
        "PBXSourcesBuildPhase", "PBXFrameworksBuildPhase", "PBXResourcesBuildPhase"
    }, "No runtime generator/build shell phases belong to this independent target"
    products = {objects[key]["productName"] for key in mini["packageProductDependencies"]}
    assert products == {"HanlinPlatformContracts", "HanlinMiniAppCore", "HanlinProductSplit"}
    frameworks = next(objects[key] for key in mini["buildPhases"]
                      if objects[key]["isa"] == "PBXFrameworksBuildPhase")
    linked = {objects[objects[key]["productRef"]]["productName"] for key in frameworks["files"]}
    assert linked == products, "Every declared MiniApps product must actually be linked"
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
