#!/usr/bin/env python3
"""Wire the original Hanlin executable to its single shared SDK implementation."""
from pathlib import Path
import argparse,json,re,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"Scripts/CI/IntegrationValidation"))
from project_graph import parse_project
FILE=ROOT/"AI_HLY.xcodeproj/project.pbxproj"
ROOT_PACKAGE="AC1900000000000000000001"
PRODUCTS={"HanlinApplication":"AC1900000000000000000002","HanlinA2UI":"AC1900000000000000000003"}

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
    for index,name in enumerate(("AI_Hanlin","AI_HLYTests","HanlinMiniApps")):
        key,target=targets[name]
        required=["HanlinApplication","HanlinA2UI"] if name!="HanlinMiniApps" else ["HanlinA2UI"]
        products=list(target.get("packageProductDependencies",[]))
        for product in required:
            if PRODUCTS[product] not in products:products.append(PRODUCTS[product])
        text=edit_object(text,key,lambda b:replace_list(b,"packageProductDependencies",products))
        phase=next(k for k in target["buildPhases"] if objects[k]["isa"]=="PBXFrameworksBuildPhase")
        linked=list(objects[phase]["files"])
        if name=="AI_Hanlin":
            linked=[k for k in linked if objects[k].get("fileRef") not in {"A10000000000000000000020","A10000000000000000000021"}]
        for offset,product in enumerate(required):
            build_id="AC19"+f"{10+index*4+offset:020X}"
            if build_id not in linked:linked.append(build_id)
            text=insert_object(text,"PBXBuildFile",build_id,
                "\t\t\tisa = PBXBuildFile;\n\t\t\tproductRef = "+PRODUCTS[product]+";\n")
        text=edit_object(text,phase,lambda b:replace_list(b,"files",linked))
        if name=="AI_Hanlin":
            for config in objects[target["buildConfigurationList"]]["buildConfigurations"]:
                def settings(b):
                    if "PRODUCT_MODULE_NAME" not in b:
                        b=re.sub(r'"?PRODUCT_NAME"? = "\$\(TARGET_NAME\)";', 'PRODUCT_NAME = "$(TARGET_NAME)";\n\t\t\t\tPRODUCT_MODULE_NAME = HanlinApp;', b)
                    return b
                text=edit_object(text,config,settings)
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
    parse_project(text)
    return text

if __name__=="__main__":
    parser=argparse.ArgumentParser();parser.add_argument("--check",action="store_true");args=parser.parse_args()
    text=update()
    if args.check:
        if text!=FILE.read_text():raise SystemExit("SDK project wiring is stale; run Scripts/SDK/update_project.py")
    else:FILE.write_text(text)
    print("Original application source ownership: SDK; executable entry point: AI_HLY/AI_HLY.swift")
