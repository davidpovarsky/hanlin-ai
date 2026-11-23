#!/usr/bin/env python3
"""Derive one public package graph from canonical Hanlin module manifests.

No implementation is copied: targets retain their original source directories.
Nested local-package product edges become target edges in the published graph.
Run after changing any module manifest; --check detects stale generation.
"""
from pathlib import Path
import argparse, collections, concurrent.futures, hashlib, json, os, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts/CI/IntegrationValidation"))
from project_graph import parse_project

def quoted(value):
    # Absolute package-directory arguments are evaluated at consumer location.
    encoded = json.dumps(value, ensure_ascii=False)
    return encoded.replace(str(ROOT), r"\(Context.packageDirectory)")

def array(values):
    return "[" + ", ".join(values) + "]"

PLATFORMS = {"ios":"iOS","macos":"macOS","tvos":"tvOS","watchos":"watchOS",
             "visionos":"visionOS","linux":"linux","windows":"windows"}

def condition(value):
    if not value: return ""
    args=[]
    if value.get("platformNames"):
        args.append("platforms: "+array("."+PLATFORMS[x] for x in value["platformNames"]))
    if value.get("config"): args.append("configuration: ."+value["config"])
    if value.get("traits"): args.append("traits: "+array(quoted(x) for x in value["traits"]))
    return ".when("+", ".join(args)+")"

def get_manifests():
    paths=sorted((ROOT/"Packages").glob("*/Package.swift"))
    paths=[p for p in paths if p.parent.name!="HanlinSwiftUIBridgeGenerator"]
    def read(path):
        run=subprocess.run(["swift","package","--package-path",str(path.parent),"dump-package"],
                           capture_output=True,text=True,check=True)
        return path.parent.relative_to(ROOT).as_posix(),json.loads(run.stdout)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        return list(pool.map(read,paths))

def source_dependency(dep):
    obj=dep["sourceControl"][0]
    url=obj["location"]["remote"][0]["urlString"]
    req=obj["requirement"]
    if "revision" in req: rule="revision: "+quoted(req["revision"][0])
    elif "exact" in req: rule="exact: "+quoted(req["exact"][0])
    elif "branch" in req: rule="branch: "+quoted(req["branch"][0])
    elif "range" in req:
        v=req["range"][0];rule=quoted(v["lowerBound"])+"..<"+quoted(v["upperBound"])
    else: raise ValueError("Unsupported dependency "+repr(dep))
    return obj["identity"].lower(),url,rule

def setting(value):
    kind,args=next(iter(value["kind"].items()))
    raw=args.get("_0")
    suffix=condition(value.get("condition"))
    if kind=="unsafeFlags": first=array(quoted(x) for x in raw)
    elif kind=="interoperabilityMode": first="."+raw
    elif kind=="swiftLanguageMode": first=".v"+raw
    else: first=quoted(raw)
    if args.get("_1") is not None: first+=", to: "+quoted(args["_1"])
    return "."+kind+"("+first+(", "+suffix if suffix else "")+")"

def dependency(value, local_products):
    if "product" in value:
        name,package,aliases,cond=value["product"]
        if package.lower() in local_products:
            targets=local_products[package.lower()][name]
            return [".target(name: "+quoted(n)+(", condition: "+condition(cond) if cond else "")+")" for n in targets]
        out=".product(name: "+quoted(name)+", package: "+quoted(package)
        if aliases: out+=", moduleAliases: "+repr(aliases)
        if cond: out+=", condition: "+condition(cond)
        return [out+")"]
    key,parts=next(iter(value.items()))
    name,cond=parts
    return [".target(name: "+quoted(name)+(", condition: "+condition(cond) if cond else "")+")"]

def target(value, folder, local_products):
    kind=value["type"]
    path=folder+"/"+value.get("path",("Tests/" if kind=="test" else "Sources/")+value["name"])
    if kind=="binary":
        if value.get("url"):
            return ".binaryTarget(name: "+quoted(value["name"])+", url: "+quoted(value["url"])+", checksum: "+quoted(value["checksum"])+")"
        return ".binaryTarget(name: "+quoted(value["name"])+", path: "+quoted(path)+")"
    functions={"regular":"target","test":"testTarget","executable":"executableTarget","system":"systemLibrary"}
    args=["name: "+quoted(value["name"])]
    deps=[d for item in value["dependencies"] for d in dependency(item,local_products)]
    if deps: args.append("dependencies: "+array(deps))
    args.append("path: "+quoted(path))
    if value["exclude"]: args.append("exclude: "+array(quoted(x) for x in value["exclude"]))
    if value.get("sources") is not None: args.append("sources: "+array(quoted(x) for x in value["sources"]))
    if value["resources"]:
        resources=[]
        for res in value["resources"]:
            name,options=next(iter(res["rule"].items()))
            extra=", localization: ."+options["localization"] if options.get("localization") else ""
            resources.append("."+name+"("+quoted(res["path"])+extra+")")
        args.append("resources: "+array(resources))
    if value.get("publicHeadersPath") is not None: args.append("publicHeadersPath: "+quoted(value["publicHeadersPath"]))
    tools={"c":"cSettings","cxx":"cxxSettings","swift":"swiftSettings","linker":"linkerSettings"}
    for tool,key in tools.items():
        values=[setting(x) for x in value["settings"] if x["tool"]==tool]
        if values: args.append(key+": "+array(values))
    return "."+functions[kind]+"(\n            "+",\n            ".join(args)+"\n        )"

def generate(selected_products=None):
    manifests=get_manifests()
    products={};local_products={};targets=[];deps={};product_targets={};target_edges={};target_remote={}
    for folder,manifest in manifests:
        local_products[manifest["name"].lower()]={p["name"]:p["targets"] for p in manifest["products"]}
        for p in manifest["products"]:
            product_targets[p["name"]]=p["targets"]
            if p["name"] in products: raise ValueError("Duplicate product "+p["name"])
            if "library" in p["type"]:
                mode=p["type"]["library"][0]
                extra="" if mode=="automatic" else ", type: ."+mode
                products[p["name"]]=".library(name: "+quoted(p["name"])+extra+", targets: "+array(quoted(x) for x in p["targets"])+")"
        for dep in manifest["dependencies"]:
            if "sourceControl" in dep:
                identity,url,rule=source_dependency(dep)
                existing=deps.get(identity)
                if existing and existing[1]!=rule: raise ValueError("Conflicting dependency requirements: "+identity)
                deps[identity]=(url,rule)
    project=parse_project((ROOT/"AI_HLY.xcodeproj/project.pbxproj").read_text())
    objects=project["objects"]
    # Keep the actual pinned app dependencies, including frameworks used only
    # by its original full application implementation.
    locks=json.loads((ROOT/"AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())
    pins={p["identity"].lower():p for p in locks["pins"]}
    for obj in objects.values():
        if obj.get("isa")!="XCRemoteSwiftPackageReference": continue
        url=obj["repositoryURL"]
        identity=url.rstrip("/").removesuffix(".git").split("/")[-1].lower()
        pin=pins.get(identity)
        if identity not in deps:
            if not pin: raise ValueError("No original lock pin for "+identity)
            deps[identity]=(url,"revision: "+quoted(pin["state"]["revision"]))
    all_target_names=set()
    for folder,manifest in manifests:
        for t in manifest["targets"]:
            if t["name"] in all_target_names: raise ValueError("Duplicate target "+t["name"])
            all_target_names.add(t["name"])
            edges=[];remote=set()
            for item in t["dependencies"]:
                if "product" in item:
                    name,owner,_,_=item["product"]
                    if owner.lower() in local_products:edges.extend(local_products[owner.lower()][name])
                    else:remote.add(owner.lower())
                else:edges.append(next(iter(item.values()))[0])
            target_edges[t["name"]]=edges
            target_remote[t["name"]]=remote
            targets.append(target(t,folder,local_products))
    app=next(o for o in objects.values() if o.get("isa")=="PBXNativeTarget" and o.get("name")=="AI_Hanlin")
    app_deps=[]
    for ref in app["packageProductDependencies"]:
        product=objects[ref]
        name=product["productName"]
        if name=="HanlinApplication": continue
        package=objects[product["package"]]
        if package.get("isa")=="XCLocalSwiftPackageReference":
            owner=Path(package["relativePath"]).name.lower()
            # Root reference is already unified after Xcode migration.
            if owner in {"",".","hanlin-sdk-unification-20261123"} or package["relativePath"]==".":
                target_names=next((ps[name] for ps in local_products.values() if name in ps),None)
            else: target_names=local_products[owner][name]
            if target_names is None: raise ValueError("Missing original product "+name)
            app_deps.extend(quoted(n) for n in target_names)
        else:
            identity=package["repositoryURL"].rstrip("/").removesuffix(".git").split("/")[-1]
            app_deps.append(".product(name: "+quoted(name)+", package: "+quoted(identity)+")")
    app_deps.extend([quoted("HanlinNodeBridge"),quoted("HanlinPythonBridge"),quoted("HanlinA2UI")])
    # Every original application Swift file remains a single authoritative
    # implementation. The executable only owns its tiny @main declaration.
    app_sources=sorted(p.relative_to(ROOT/"AI_HLY").as_posix()
                       for p in (ROOT/"AI_HLY").rglob("*.swift") if p.name!="AI_HLY.swift")
    # Shared resources use the same original files; no runtime or UI replicas.
    app_resources=[
        '.process("Assets.xcassets")', '.process("Resource/Localizable.xcstrings")',
        '.process("Downstream/MCP/Resources/MCPLocalizable.xcstrings")',
        '.process("Downstream/RuntimeCore/Resources/RuntimeLocalizable.xcstrings")',
        '.copy("RuntimeHostResources.zip")'
    ]
    resource_files=list((ROOT/"AI_HLY/Resource").glob("*.json"))
    resource_files+=list((ROOT/"AI_HLY/Downstream/AgentSkills/Analysis/Resources").glob("*"))
    resource_files+=list((ROOT/"AI_HLY/Downstream/RuntimeCore/Python/Resources").rglob("*"))
    resource_files+=[ROOT/"AI_HLY/Downstream/RuntimeCore/Resources/RuntimeManifest.json",
                     ROOT/"AI_HLY/Downstream/RuntimeCore/Resources/RuntimeLinkDependencyNotices.txt",
                     ROOT/"AI_HLY/Downstream/AgentDiagnostics/HanlinDiagnosticsBuildProvenance.json"]
    for file in sorted(resource_files):
        if file.is_file():
            app_resources.append('.copy('+quoted(file.relative_to(ROOT/"AI_HLY").as_posix())+')')
    targets.extend([
        '.binaryTarget(name: "NodeMobile", path: "Vendor/NodeMobile/NodeMobile.xcframework")',
        '.binaryTarget(name: "Python", path: "Vendor/Python/Python.xcframework")',
        '.target(name: "HanlinNodeBridge", dependencies: ["NodeMobile"], path: "AI_HLY/Downstream/RuntimeCore/Node/Native", exclude: ["NodeRuntimeBridge.swift"], publicHeadersPath: ".", linkerSettings: [.linkedFramework("Foundation")])',
        '.target(name: "HanlinPythonBridge", dependencies: ["Python"], path: "AI_HLY/Downstream/RuntimeCore/Python/Native", publicHeadersPath: ".", linkerSettings: [.linkedFramework("Foundation")])',
        '.target(name: "AI_Hanlin", dependencies: '+array(list(dict.fromkeys(app_deps)))+',\n'
        '            path: "AI_HLY", exclude: ["AI_HLY.swift", "AI_HLY.entitlements", "Base.lproj", "mul.lproj"],\n'
        '            sources: '+array(quoted(x) for x in app_sources)+',\n'
        '            resources: '+array(app_resources)+',\n'
        '            swiftSettings: [.define("HANLIN_A2UI_POC"), .define("HANLIN_SKILL_ANALYSIS_POC"), .interoperabilityMode(.Cxx), .enableUpcomingFeature("NonisolatedNonsendingByDefault")],\n'
        '            linkerSettings: [.linkedLibrary("icucore"), .linkedLibrary("z"), .linkedLibrary("c++")])'
    ])
    products["HanlinApplication"]='.library(name: "HanlinApplication", targets: ["AI_Hanlin"])'
    product_targets["HanlinApplication"]=["AI_Hanlin"]
    target_edges["HanlinNodeBridge"]=["NodeMobile"]
    target_edges["HanlinPythonBridge"]=["Python"]
    target_edges["NodeMobile"]=[];target_edges["Python"]=[]
    target_edges["AI_Hanlin"]=[json.loads(x) for x in app_deps if x.startswith('"')]
    import re
    target_remote["AI_Hanlin"]={re.search(r'package: "([^"]+)"',x)[1].lower()
                                for x in app_deps if x.startswith(".product(")}
    chosen_targets=set(target_edges)
    if selected_products:
        unknown=set(selected_products)-set(products)
        if unknown:raise ValueError("Unknown public SDK products: "+", ".join(sorted(unknown)))
        chosen_targets=set()
        def include(name):
            if name in chosen_targets:return
            if name not in target_edges:raise ValueError("Missing canonical target: "+name)
            chosen_targets.add(name)
            for child in target_edges[name]:include(child)
        for name in selected_products:
            for child in product_targets[name]:include(child)
        products={name:value for name,value in products.items() if name in selected_products}
        targets=[value for value in targets
                 if re.search(r'name: "([^"]+)"',value)[1] in chosen_targets]
        remote=set().union(*(target_remote.get(name,set()) for name in chosen_targets))
        deps={name:value for name,value in deps.items() if name.lower() in remote}
    dependency_text=[".package(url: "+quoted(url)+", "+rule+")" for _,(url,rule) in sorted(deps.items())]
    text="// swift-tools-version: 6.2\n// Generated by Scripts/SDK/generate_manifest.py. Source implementations are never copied.\nimport PackageDescription\n\n"
    text+='let package = Package(\n    name: "HanlinSDK",\n    defaultLocalization: "en",\n    platforms: [.iOS("27.0"), .macOS(.v26)],\n'
    text+="    products: [\n        "+",\n        ".join(products.values())+"\n    ],\n"
    text+="    dependencies: [\n        "+",\n        ".join(dependency_text)+"\n    ],\n"
    text+="    targets: [\n        "+",\n        ".join(targets)+"\n    ],\n"
    text+="    swiftLanguageModes: [.v6],\n    cLanguageStandard: .gnu11,\n    cxxLanguageStandard: .gnucxx20\n)\n"
    receipt={"schemaVersion":1,"sourceOwnership":"one original source path per target",
             "applicationModule":"AI_Hanlin" if "AI_Hanlin" in chosen_targets else None,
             "applicationSourceCount":len(app_sources) if "AI_Hanlin" in chosen_targets else 0,
             "selectedProducts":list(selected_products) if selected_products else None,
             "products":list(products),"targets":len(targets),
             "localPackageEdgesRemaining":0,
             "inputs":{folder+"/Package.swift":hashlib.sha256((ROOT/folder/"Package.swift").read_bytes()).hexdigest() for folder,_ in manifests}}
    return text,receipt

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--check",action="store_true")
    parser.add_argument("--products",nargs="+",help="Install only these public product closures, retaining canonical sources")
    args=parser.parse_args()
    selection=list(dict.fromkeys(part for item in args.products for part in item.split(","))) if args.products else None
    text,receipt=generate(selection)
    target=ROOT/"Package.swift"
    if args.check:
        if not target.exists() or target.read_text()!=text: raise SystemExit("Unified SDK manifest is stale; run Scripts/SDK/generate_manifest.py")
    else:
        target.write_text(text)
        output=ROOT/"docs/agent-sdk/unified-package-manifest.json"
        output.parent.mkdir(parents=True,exist_ok=True)
        output.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps(receipt,ensure_ascii=False))
