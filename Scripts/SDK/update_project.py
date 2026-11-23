#!/usr/bin/env python3
"""Wire the original Hanlin executable to its single shared SDK implementation."""
from pathlib import Path
import argparse,json,re,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"Scripts/CI/IntegrationValidation"))
from project_graph import parse_project
FILE=ROOT/"AI_HLY.xcodeproj/project.pbxproj"
ROOT_PACKAGE="AC1900000000000000000001"
PRODUCTS={"HanlinApplication":"AC1900000000000000000002","HanlinA2UI":"AC1900000000000000000003",
          "HanlinLocalization":"AC1900000000000000000004",
          "HanlinAgentActivityCore":"AC1900000000000000000005",
          "HanlinExtensionContracts":"AC1900000000000000000040",
          "HanlinShareExtensionUI":"AC1900000000000000000041",
          "HanlinNotificationExtension":"AC1900000000000000000042",
          "HanlinTranslationUI":"AC1900000000000000000043",
          "HanlinWidgetUI":"AC1900000000000000000044",
           "HanlinMiniAppsUI":"AC1900000000000000000045",
           "HanlinPresentationKit":"AC1800000000000000000002",
           "TorahLibraryKit":"F70000000000000000000051"}

# Preserve existing target/build IDs. Four slots per target remain disjoint
# from product IDs, shared source IDs and the original localization test IDs.
# Additional products use explicit free IDs without shifting existing allocations.
EXTRA_PRODUCT_BUILDS = {
    ("HanlinMiniApps", "HanlinMiniAppsUI"): "AC1900000000000000000046",
    ("HanlinMiniApps", "HanlinPresentationKit"): "AC1900000000000000000047",
    ("HanlinMiniApps", "TorahLibraryKit"): "AC1900000000000000000048",
    ("AI_Hanlin", "HanlinTranslationUI"): "AC1900000000000000000049",
    ("HanlinMiniApps", "HanlinTranslationUI"): "AC190000000000000000004A",
    ("AI_HLYTests", "HanlinTranslationUI"): "AC190000000000000000004B"
}
TARGET_PRODUCTS={
    "AI_Hanlin": ["HanlinApplication", "HanlinA2UI", "HanlinLocalization", "HanlinExtensionContracts", "HanlinTranslationUI"],
    "AI_HLYTests": ["HanlinApplication", "HanlinA2UI", "HanlinLocalization", "HanlinExtensionContracts", "HanlinTranslationUI"],
    "HanlinMiniApps": ["HanlinA2UI", "HanlinLocalization", "HanlinAgentActivityCore", "HanlinExtensionContracts", "HanlinMiniAppsUI", "HanlinPresentationKit", "TorahLibraryKit", "HanlinTranslationUI"],
    "ChavrusaChatShare": ["HanlinShareExtensionUI", "HanlinExtensionContracts"],
    "ChavrusaChatNotificationService": ["HanlinNotificationExtension", "HanlinExtensionContracts"],
    "ChavrusaChatTranslationProvider": ["HanlinTranslationUI", "HanlinExtensionContracts"],
    "HanlinScriptingWidgets": ["HanlinWidgetUI", "HanlinExtensionContracts"],
}

class Span:
    def __init__(self,text,start,end):self.text,self.left,self.right=text,start,end
    def start(self):return self.left
    def end(self):return self.right
    def group(self):return self.text[self.left:self.right]

def object_span(text,key):
    pattern=r'(?m)^\t\t"?'+re.escape(key)+r'"?(?: /\*.*?\*/)? = \{'
    match=re.search(pattern,text)
    if not match:raise ValueError("Missing project object "+key)
    index=match.end();depth=1;quoted=False
    while index<len(text):
        char=text[index]
        if quoted:
            if char=="\\":index+=2;continue
            if char=='"':quoted=False
        elif char=='"':quoted=True
        elif text[index:index+2]=="/*":
            index=text.index("*/",index+2)+2;continue
        elif text[index:index+2]=="//":
            index=text.index("\n",index+2)+1;continue
        elif char=="{":depth+=1
        elif char=="}":
            depth-=1
            if depth==0:
                end=index+1
                while end<len(text) and text[end] in ";\n":end+=1
                return Span(text,match.start(),end)
        index+=1
    raise ValueError("Unclosed project object "+key)

def edit_object(text,key,fn):
    m=object_span(text,key)
    return text[:m.start()]+fn(m.group())+text[m.end():]

def replace_list(block,name,values):
    replacement=name+" = (\n"+"".join("\t\t\t\t"+json.dumps(v)+" ,\n" for v in values)+"\t\t\t);"
    pattern=r'"?'+re.escape(name)+r'"? = \([\s\S]*?\);'
    result,count=re.subn(pattern,lambda _:replacement,block,count=1)
    if count!=1:raise ValueError("Missing project list "+name)
    return result

def insert_object(text,section,key,body):
    if re.search(r"(?m)^\t\t"+key+r"\b",text):return text
    marker="/* End "+section+" section */"
    assert marker in text,section
    rendered="\t\t"+key+" = {\n"+body+"\t\t};\n"
    return text.replace(marker,rendered+marker,1)

def update():
    text=FILE.read_text();project=parse_project(text);objects=project["objects"]
    root=objects[project["rootObject"]]
    old=[key for key in root["packageReferences"] if objects[key]["isa"]=="XCLocalSwiftPackageReference" and key!=ROOT_PACKAGE]
    for key in old:
        text=re.sub(r'("?package"? = )"?'+key+r'"?(?: /\*.*?\*/)?;',r"\g<1>"+ROOT_PACKAGE+" /* HanlinSDK */;",text)
    refs=[key for key in root["packageReferences"] if key not in old]
    if ROOT_PACKAGE not in refs:refs.append(ROOT_PACKAGE)
    text=edit_object(text,project["rootObject"],lambda b:replace_list(b,"packageReferences",refs))
    text=insert_object(text,"XCLocalSwiftPackageReference",ROOT_PACKAGE,
        "\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = \".\";\n")
    for key in old:
        m=object_span(text,key);text=text[:m.start()]+text[m.end():]
    for name,key in PRODUCTS.items():
        text=insert_object(text,"XCSwiftPackageProductDependency",key,
            "\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = "+ROOT_PACKAGE+";\n\t\t\tproductName = "+name+";\n")
    targets={v["name"]:(k,v) for k,v in objects.items() if v.get("isa")=="PBXNativeTarget"}
    for index,(name,required) in enumerate(TARGET_PRODUCTS.items()):
        key,target=targets[name]
        products=list(target.get("packageProductDependencies",[]))
        for product in required:
            if PRODUCTS[product] not in products:products.append(PRODUCTS[product])
        def set_products(block):
            if "packageProductDependencies" not in block:
                marker = "\t\t\tproductType = "
                assert marker in block, name
                block = block.replace(marker, "\t\t\tpackageProductDependencies = ();\n" + marker, 1)
            return replace_list(block,"packageProductDependencies",products)
        text=edit_object(text,key,set_products)
        phase=next(k for k in target["buildPhases"] if objects[k]["isa"]=="PBXFrameworksBuildPhase")
        linked=list(objects[phase]["files"])
        if name=="AI_Hanlin":
            linked=[k for k in linked if objects[k].get("fileRef") not in {"A10000000000000000000020","A10000000000000000000021"}]
        for offset,product in enumerate(required):
            build_id=EXTRA_PRODUCT_BUILDS.get((name,product))
            if build_id is None:
                assert offset < 4, "Allocate an explicit free ID for an additional target product"
                build_id="AC19"+f"{10+index*4+offset:020X}"
            if build_id not in linked:linked.append(build_id)
            text=insert_object(text,"PBXBuildFile",build_id,
                "\t\t\tisa = PBXBuildFile;\n\t\t\tproductRef = "+PRODUCTS[product]+";\n")
        text=edit_object(text,phase,lambda b:replace_list(b,"files",linked))
        host_modules={"AI_Hanlin":"HanlinApp", "HanlinScriptingWidgets":"HanlinScriptingWidgetsHost"}
        if name in host_modules:
            # The SDK owns the original implementation module names, preserving
            # SwiftData and persisted AppIntent/AppEntity/ActivityAttributes identity.
            for config in objects[target["buildConfigurationList"]]["buildConfigurations"]:
                def settings(b):
                    module=host_modules[name]
                    if "PRODUCT_MODULE_NAME" in b:
                        return re.sub(r'"?PRODUCT_MODULE_NAME"? = [^;]+;',
                                      "PRODUCT_MODULE_NAME = "+module+";",b)
                    return re.sub(r'"?PRODUCT_NAME"? = "\$\(TARGET_NAME\)";',
                                  'PRODUCT_NAME = "$(TARGET_NAME)";\n\t\t\t\tPRODUCT_MODULE_NAME = '+module+';',b)
                text=edit_object(text,config,settings)
    # The standalone MiniApps executable compiles the same small original
    # runtime/provider closure. Runtime configuration must not pull the chat
    # model or AgentCore into this product.
    mini=targets["HanlinMiniApps"][1]
    source_phase=next(k for k in mini["buildPhases"] if objects[k]["isa"]=="PBXSourcesBuildPhase")
    source_files=list(objects[source_phase]["files"])
    shared=["AI_HLY/Downstream/SDK/HanlinApplicationResources.swift",
            "AI_HLY/Downstream/RuntimeCore/Core/HanlinApplicationRuntimeConfiguration.swift",
            "AI_HLY/Downstream/ProductSplitIntegration/HanlinMiniAppsForegroundBridge.swift",
            "AI_HLY/Downstream/ProductSplitIntegration/HanlinMiniAppsCatalogView.swift",
            "AI_HLY/Downstream/TorahStudy/TorahOCRService.swift",
            "AI_HLY/Downstream/TorahStudy/TorahPhotoStudyCaptureView.swift",
            "AI_HLY/Downstream/TorahStudy/TorahSourceReaderView.swift",
            "AI_HLY/Downstream/TorahStudy/TorahStudyNavigationRouter.swift",
            "AI_HLY/NativeAppPlatform/AppsHub/MiniAppCardView.swift",
            "AI_HLY/NativeAppPlatform/AppsHub/NativeAppsAddSheet.swift",
            "AI_HLY/NativeAppPlatform/AppsHub/NativeAppsCatalogView.swift",
            "AI_HLY/NativeAppPlatform/Support/NativeAppColor.swift",
            "AI_HLY/Downstream/ProductSplitIntegration/MiniAppAuthoringDelivery.swift",
            "AI_HLY/Downstream/ScriptingPlatform/MiniAppImportDiagnosticsView.swift",
            "AI_HLY/Downstream/RuntimeCore/Core/MiniAppAuthoringService.swift"]
    shared_group="F9F4C452EBF2FA6B1274B4D7"
    shared_children=list(objects[shared_group]["children"])
    for index,path in enumerate(shared):
        file_id="AC19"+f"{256+index*2:020X}"
        build_id="AC19"+f"{257+index*2:020X}"
        text=insert_object(text,"PBXFileReference",file_id,
            "\t\t\tisa = PBXFileReference;\n\t\t\tlastKnownFileType = sourcecode.swift;\n\t\t\tpath = "+json.dumps(path)+";\n\t\t\tsourceTree = SOURCE_ROOT;\n")
        text=insert_object(text,"PBXBuildFile",build_id,
            "\t\t\tisa = PBXBuildFile;\n\t\t\tfileRef = "+file_id+";\n")
        if build_id not in source_files:source_files.append(build_id)
        if file_id not in shared_children:shared_children.append(file_id)
    text=edit_object(text,source_phase,lambda b:replace_list(b,"files",source_files))
    text=edit_object(text,shared_group,lambda b:replace_list(b,"children",shared_children))
    resource_phase=next(k for k in mini["buildPhases"] if objects[k]["isa"]=="PBXResourcesBuildPhase")
    # Original shared translations now belong to HanlinLocalization. The
    # executable keeps its original AppIcon, AccentColor and launch logo only.
    resource_files=[k for k in objects[resource_phase]["files"]
                    if objects[objects[k]["fileRef"]]["path"] != "AI_HLY/Downstream/RuntimeCore/Resources/RuntimeLocalizable.xcstrings"]
    text=edit_object(text,resource_phase,lambda b:replace_list(b,"files",resource_files))
    # Run the canonical public-bundle tests in the actual application scheme as
    # well as the package scheme, without maintaining another test source.
    unit=targets["AI_HLYTests"][1]
    unit_phase=next(k for k in unit["buildPhases"] if objects[k]["isa"]=="PBXSourcesBuildPhase")
    unit_files=list(objects[unit_phase]["files"])
    test_file="AC1900000000000000000120"
    test_build="AC1900000000000000000121"
    text=insert_object(text,"PBXFileReference",test_file,
        "\t\t\tisa = PBXFileReference;\n\t\t\tlastKnownFileType = sourcecode.swift;\n\t\t\tpath = \"Packages/HanlinPresentationSDK/Tests/HanlinLocalizationTests/HanlinLocalizationTests.swift\";\n\t\t\tsourceTree = SOURCE_ROOT;\n")
    text=insert_object(text,"PBXBuildFile",test_build,
        "\t\t\tisa = PBXBuildFile;\n\t\t\tfileRef = "+test_file+";\n")
    if test_build not in unit_files:unit_files.append(test_build)
    text=edit_object(text,unit_phase,lambda b:replace_list(b,"files",unit_files))
    # Native binary targets are linked/embedded by the SDK graph. Retain the
    # standalone MiniApps target's original independent framework phases.
    text=edit_object(text,"D79AD5752DB545F9000646D4",lambda b:replace_list(b,"files",[]))
    exception="A10000000000000000000030"
    excluded=set(objects[exception]["membershipExceptions"])
    for file in (ROOT/"AI_HLY").rglob("*"):
        if file.is_file() and file.suffix in {".swift",".mm",".m",".h",".hpp"} and file.name!="AI_HLY.swift":
            excluded.add(file.relative_to(ROOT/"AI_HLY").as_posix())
    # These originals are packaged once by the SDK. App icons, launch screen and
    # host InfoPlist localizations remain executable-owned.
    excluded.update(["Downstream","Resource","RuntimeHostResources.zip"])
    text=edit_object(text,exception,lambda b:replace_list(b,"membershipExceptions",sorted(excluded)))
    # AppIntents' compiler accepts .main for statically linked package metadata.
    # Project the single SDK catalog into a namespaced table in each executable;
    # never copy translations into host source or change general SDK localization.
    from generate_app_intents_resources import OUTPUT, render
    if not OUTPUT.exists() or OUTPUT.read_text() != render():
        raise ValueError("Run Scripts/SDK/generate_app_intents_resources.py first")
    intents_file = "AC1900000000000000000130"
    text=insert_object(text,"PBXFileReference",intents_file,
        "\t\t\tisa = PBXFileReference;\n\t\t\tlastKnownFileType = text.json.xcstrings;\n"
        "\t\t\tpath = \"Packages/HanlinWidgetSDK/HostResources/HanlinAppIntents.xcstrings\";\n"
        "\t\t\tsourceTree = SOURCE_ROOT;\n")
    for name, build in [("AI_Hanlin", "AC1900000000000000000131"),
                        ("HanlinScriptingWidgets", "AC1900000000000000000132")]:
        target=targets[name][1]
        phase=next(k for k in target["buildPhases"] if objects[k]["isa"]=="PBXResourcesBuildPhase")
        files=list(objects[phase]["files"])
        text=insert_object(text,"PBXBuildFile",build,
            "\t\t\tisa = PBXBuildFile;\n\t\t\tfileRef = "+intents_file+";\n")
        if build not in files: files.append(build)
        text=edit_object(text,phase,lambda b:replace_list(b,"files",files))
    group=root["mainGroup"]
    children=list(objects[group]["children"])
    if intents_file not in children: children.append(intents_file)
    text=edit_object(text,group,lambda b:replace_list(b,"children",children))
    sys.path.insert(0, str(ROOT / "Scripts/ProductSplit"))
    from miniapps_extensions import wire_miniapps_extensions
    text = wire_miniapps_extensions(text, edit_object, replace_list, insert_object)
    parse_project(text)
    return text

if __name__=="__main__":
    parser=argparse.ArgumentParser();parser.add_argument("--check",action="store_true");args=parser.parse_args()
    text=update()
    if args.check:
        if text!=FILE.read_text():raise SystemExit("SDK project wiring is stale; run Scripts/SDK/update_project.py")
    else:FILE.write_text(text)
    print("Original application source ownership: SDK; executable entry point: AI_HLY/AI_HLY.swift")
