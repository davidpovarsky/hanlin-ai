"""Own native MiniApps surfaces, linked to the original shared SDK products.

Only new extension objects are rendered; existing native build phases remain intact.
"""
import copy
import hashlib
import json

EXTENSIONS = (
    ("HanlinMiniAppsWidgets", "HanlinScriptingWidgets", "Widgets", "widgets"),
    ("HanlinMiniAppsShare", "ChavrusaChatShare", "Share", "share"),
    ("HanlinMiniAppsTranslationProvider", "ChavrusaChatTranslationProvider", "Translation", "translation-provider"),
    ("HanlinMiniAppsNotificationService", "ChavrusaChatNotificationService", "Notification", "notification-service"),
)

def extension_id(role):
    return "AC1A" + hashlib.sha256(("miniapps-extension:" + role).encode()).hexdigest()[:20].upper()

def render(value, level=3):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (level + 1) + json.dumps(k) + " = " + render(v, level + 1) + ";\n"
                               for k, v in value.items()) + "\t" * level + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (level + 1) + render(v, level + 1) + ",\n" for v in value) + "\t" * level + ")"
    return json.dumps(value)

def wire_miniapps_extensions(text, edit_object, replace_list, insert_object):
    from project_graph import parse_project
    project = parse_project(text)
    objects = project["objects"]
    root = objects[project["rootObject"]]
    targets = {v["name"]: (k, v) for k, v in objects.items() if v.get("isa") == "PBXNativeTarget"}
    mini_id, mini = targets["HanlinMiniApps"]
    mini_configs = {objects[k]["name"]: objects[k]["buildSettings"] for k in
                    objects[mini["buildConfigurationList"]]["buildConfigurations"]}

    def upsert(key, value):
        nonlocal text
        body = "".join("\t\t\t" + json.dumps(k) + " = " + render(v) + ";\n" for k, v in value.items())
        if key in objects:
            assert objects[key]["isa"] == value["isa"], "MiniApps extension ID collision"
            text = edit_object(text, key, lambda _: "\t\t" + key + " = {\n" + body + "\t\t};\n")
        else:
            text = insert_object(text, value["isa"], key, body)

    new_targets, new_groups, new_products, dependencies = [], [], [], []
    embeds = {"app": [], "extensionkit": []}
    for name, original_name, folder, suffix in EXTENSIONS:
        original = targets[original_name][1]
        target_id = extension_id(name + ":target")
        product_id = extension_id(name + ":product")
        group_id = extension_id(name + ":group")
        exception_id = extension_id(name + ":exception")
        config_list_id = extension_id(name + ":configs")
        directory = "HanlinMiniAppsExtensions/" + folder
        new_targets.append(target_id); new_products.append(product_id); new_groups.append(group_id)
        product = copy.deepcopy(objects[original["productReference"]])
        product["path"] = name + ".appex"
        upsert(product_id, product)
        upsert(group_id, {"isa": "PBXFileSystemSynchronizedRootGroup", "exceptions": [exception_id],
                          "path": directory, "sourceTree": "<group>"})
        upsert(exception_id, {"isa": "PBXFileSystemSynchronizedBuildFileExceptionSet",
                             "membershipExceptions": ["Info.plist", name + ".entitlements"], "target": target_id})
        phases = []
        for original_phase_id in original["buildPhases"]:
            original_phase = objects[original_phase_id]
            assert original_phase["isa"] in {"PBXSourcesBuildPhase", "PBXFrameworksBuildPhase", "PBXResourcesBuildPhase"}
            phase_id = extension_id(name + ":phase:" + original_phase["isa"])
            phase = copy.deepcopy(original_phase)
            phase["files"] = []
            for source_file_id in original_phase["files"]:
                file_id = extension_id(name + ":build:" + source_file_id)
                upsert(file_id, copy.deepcopy(objects[source_file_id]))
                phase["files"].append(file_id)
            upsert(phase_id, phase); phases.append(phase_id)
        configs = []
        for original_config_id in objects[original["buildConfigurationList"]]["buildConfigurations"]:
            config = copy.deepcopy(objects[original_config_id])
            settings = config["buildSettings"]
            app_settings = mini_configs[config["name"]]
            settings.update({
                "CODE_SIGN_ENTITLEMENTS": directory + "/" + name + ".entitlements",
                "INFOPLIST_FILE": directory + "/Info.plist",
                "PRODUCT_BUNDLE_IDENTIFIER": app_settings["PRODUCT_BUNDLE_IDENTIFIER"] + "." + suffix,
                "PRODUCT_MODULE_NAME": name + "Host",
                "CODE_SIGN_STYLE": "Automatic",
                "DEVELOPMENT_TEAM": app_settings["DEVELOPMENT_TEAM"],
                "CURRENT_PROJECT_VERSION": app_settings["CURRENT_PROJECT_VERSION"],
                "MARKETING_VERSION": app_settings["MARKETING_VERSION"],
            })
            for key in ("PROVISIONING_PROFILE_SPECIFIER", "PROVISIONING_PROFILE", "CODE_SIGN_IDENTITY"):
                settings.pop(key, None)
            config_id = extension_id(name + ":config:" + config["name"])
            upsert(config_id, config); configs.append(config_id)
        config_list = copy.deepcopy(objects[original["buildConfigurationList"]])
        config_list["buildConfigurations"] = configs
        upsert(config_list_id, config_list)
        target = copy.deepcopy(original)
        target.update({"buildConfigurationList": config_list_id, "buildPhases": phases,
                       "dependencies": [], "fileSystemSynchronizedGroups": [group_id],
                       "name": name, "productName": name, "productReference": product_id})
        upsert(target_id, target)
        proxy_id = extension_id(name + ":proxy")
        upsert(proxy_id, {"isa": "PBXContainerItemProxy", "containerPortal": project["rootObject"],
                          "proxyType": "1", "remoteGlobalIDString": target_id, "remoteInfo": name})
        dependency_id = extension_id(name + ":dependency")
        upsert(dependency_id, {"isa": "PBXTargetDependency", "target": target_id, "targetProxy": proxy_id})
        dependencies.append(dependency_id)
        embed_id = extension_id(name + ":embed")
        upsert(embed_id, {"isa": "PBXBuildFile", "fileRef": product_id,
                          "settings": {"ATTRIBUTES": ["RemoveHeadersOnCopy"]}})
        kind = "extensionkit" if original["productType"].endswith("extensionkit-extension") else "app"
        embeds[kind].append(embed_id)

    embed_phases = []
    for kind, files in embeds.items():
        phase_id = extension_id("embed:" + kind)
        upsert(phase_id, {"isa": "PBXCopyFilesBuildPhase", "buildActionMask": "2147483647",
                         "dstPath": "$(EXTENSIONS_FOLDER_PATH)" if kind == "extensionkit" else "",
                         "dstSubfolderSpec": "16" if kind == "extensionkit" else "13",
                         "files": files,
                         "name": "Embed MiniApps " + ("ExtensionKit Extensions" if kind == "extensionkit" else "App Extensions"),
                         "runOnlyForDeploymentPostprocessing": "0"})
        embed_phases.append(phase_id)
    text = edit_object(text, mini_id, lambda b: replace_list(replace_list(b, "dependencies", dependencies),
                      "buildPhases", [k for k in mini["buildPhases"] if k not in embed_phases] + embed_phases))
    for object_id, field, additions in ((project["rootObject"], "targets", new_targets),
                                       (root["mainGroup"], "children", new_groups),
                                       (root["productRefGroup"], "children", new_products)):
        values = list(objects[object_id][field])
        text = edit_object(text, object_id, lambda b: replace_list(b, field, values + [v for v in additions if v not in values]))
    return text
