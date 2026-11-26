"""Generate the AI-owned keyboard, notification-content and capture targets.

The existing target objects and shell phases are retained. MiniApps receives
its own targets through miniapps_extensions, after these SDK links are wired.
"""
import copy
import hashlib
import json

from extension_inventory import EXTENSIONS, NEW_EXTENSION_KEYS
from miniapps_extensions import render


def extension_id(role):
    return "AC1B" + hashlib.sha256(("ai-system-extension:" + role).encode()).hexdigest()[:20].upper()


def wire_ai_system_extensions(text, *, parse_project, edit_object, replace_list, insert_object):
    project = parse_project(text)
    objects = project["objects"]
    root = objects[project["rootObject"]]
    targets = {v["name"]: (k, v) for k, v in objects.items() if v.get("isa") == "PBXNativeTarget"}
    app_id, app = targets["HanlinApp"]
    app_configs = {objects[k]["name"]: objects[k]["buildSettings"] for k in
                   objects[app["buildConfigurationList"]]["buildConfigurations"]}
    template = targets["ChavrusaChatNotificationService"][1]
    additions = {"targets": [], "groups": [], "products": [], "dependencies": []}
    embeds = {"app": [], "extensionkit": []}

    def upsert(key, value):
        nonlocal text
        body = "".join("\t\t\t" + json.dumps(k) + " = " + render(v) + ";\n" for k, v in value.items())
        if key in objects:
            assert objects[key]["isa"] == value["isa"], "AI extension ID collision"
            text = edit_object(text, key, lambda _: "\t\t" + key + " = {\n" + body + "\t\t};\n")
        else:
            text = insert_object(text, value["isa"], key, body)

    for spec in EXTENSIONS:
        if spec.key not in NEW_EXTENSION_KEYS:
            continue
        name = spec.ai_target
        target_id = extension_id(name + ":target")
        product_id = extension_id(name + ":product")
        group_id = extension_id(name + ":group")
        exception_id = extension_id(name + ":exception")
        config_list_id = extension_id(name + ":configs")
        # The installed Xcode capture template inherits ExtensionKit and declares
        # com.apple.securecapture. Its product is embedded like Translation.
        kind = "extensionkit" if spec.key == "camera-capture" else "app"
        product_type = ("com.apple.product-type.extensionkit-extension" if kind == "extensionkit"
                        else "com.apple.product-type.app-extension")
        upsert(product_id, {"isa": "PBXFileReference", "explicitFileType": "wrapper.app-extension",
                            "includeInIndex": "0", "path": name + ".appex", "sourceTree": "BUILT_PRODUCTS_DIR"})
        upsert(group_id, {"isa": "PBXFileSystemSynchronizedRootGroup", "exceptions": [exception_id],
                         "path": name, "sourceTree": "<group>"})
        upsert(exception_id, {"isa": "PBXFileSystemSynchronizedBuildFileExceptionSet",
                             "membershipExceptions": ["Info.plist", name + ".entitlements"], "target": target_id})
        phases = []
        for isa in ("PBXSourcesBuildPhase", "PBXFrameworksBuildPhase", "PBXResourcesBuildPhase"):
            phase_id = extension_id(name + ":phase:" + isa)
            upsert(phase_id, {"isa": isa, "buildActionMask": "2147483647", "files": [],
                             "runOnlyForDeploymentPostprocessing": "0"})
            phases.append(phase_id)
        configs = []
        for old_id in objects[template["buildConfigurationList"]]["buildConfigurations"]:
            config = copy.deepcopy(objects[old_id])
            settings = config["buildSettings"]
            app_settings = app_configs[config["name"]]
            settings.update({
                "CODE_SIGN_ENTITLEMENTS": name + "/" + name + ".entitlements",
                "INFOPLIST_FILE": name + "/Info.plist",
                "GENERATE_INFOPLIST_FILE": "YES",
                "PRODUCT_BUNDLE_IDENTIFIER": app_settings["PRODUCT_BUNDLE_IDENTIFIER"] + "." + spec.suffix,
                "PRODUCT_MODULE_NAME": name + "Host",
                "CODE_SIGN_STYLE": "Automatic",
                "DEVELOPMENT_TEAM": app_settings["DEVELOPMENT_TEAM"],
                "CURRENT_PROJECT_VERSION": app_settings["CURRENT_PROJECT_VERSION"],
                "MARKETING_VERSION": app_settings["MARKETING_VERSION"],
            })
            for key in ("PROVISIONING_PROFILE_SPECIFIER", "PROVISIONING_PROFILE", "CODE_SIGN_IDENTITY"):
                settings.pop(key, None)
            config_id = extension_id(name + ":config:" + config["name"])
            upsert(config_id, config)
            configs.append(config_id)
        configuration_list = copy.deepcopy(objects[template["buildConfigurationList"]])
        configuration_list["buildConfigurations"] = configs
        upsert(config_list_id, configuration_list)
        upsert(target_id, {
            "isa": "PBXNativeTarget", "buildConfigurationList": config_list_id,
            "buildPhases": phases, "buildRules": [], "dependencies": [],
            "fileSystemSynchronizedGroups": [group_id], "name": name,
            "packageProductDependencies": [], "productName": name,
            "productReference": product_id, "productType": product_type,
        })
        proxy_id = extension_id(name + ":proxy")
        upsert(proxy_id, {"isa": "PBXContainerItemProxy", "containerPortal": project["rootObject"],
                         "proxyType": "1", "remoteGlobalIDString": target_id, "remoteInfo": name})
        dependency_id = extension_id(name + ":dependency")
        upsert(dependency_id, {"isa": "PBXTargetDependency", "target": target_id, "targetProxy": proxy_id})
        embed_id = extension_id(name + ":embed")
        upsert(embed_id, {"isa": "PBXBuildFile", "fileRef": product_id,
                         "settings": {"ATTRIBUTES": ["RemoveHeadersOnCopy"]}})
        additions["targets"].append(target_id)
        additions["groups"].append(group_id)
        additions["products"].append(product_id)
        additions["dependencies"].append(dependency_id)
        embeds[kind].append(embed_id)

    for kind, new_files in embeds.items():
        phase_name = "Embed ExtensionKit Extensions" if kind == "extensionkit" else "Embed App Extensions"
        matching = [key for key in app["buildPhases"] if
                    objects[key].get("isa") == "PBXCopyFilesBuildPhase" and objects[key].get("name") == phase_name]
        assert len(matching) == 1, "Missing or ambiguous original extension embedding phase"
        key = matching[0]
        phase = objects[key]
        assert phase["dstPath"] == ("$(EXTENSIONS_FOLDER_PATH)" if kind == "extensionkit" else "")
        assert phase["dstSubfolderSpec"] == ("16" if kind == "extensionkit" else "13")
        files = list(phase["files"])
        text = edit_object(text, key, lambda block: replace_list(
            block, "files", files + [value for value in new_files if value not in files]))
    for object_id, field, new_values in (
            (app_id, "dependencies", additions["dependencies"]),
            (project["rootObject"], "targets", additions["targets"]),
            (root["mainGroup"], "children", additions["groups"]),
            (root["productRefGroup"], "children", additions["products"])):
        values = list(objects[object_id][field])
        text = edit_object(text, object_id, lambda block: replace_list(
            block, field, values + [value for value in new_values if value not in values]))
    return text
