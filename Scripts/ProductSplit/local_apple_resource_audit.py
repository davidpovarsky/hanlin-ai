#!/usr/bin/env python3
"""Inspect installed-team Apple resources; never print keys, tokens or raw profiles."""
from __future__ import annotations
import argparse, base64, hashlib, json, os, platform, plistlib, subprocess, tempfile, time
from datetime import datetime, timezone
from pathlib import Path
import urllib.error, urllib.parse, urllib.request
import jwt

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args=parser.parse_args()
    key_id="BMFQPP6252"
    key=Path.home()/".appstoreconnect/private_keys"/("AuthKey_"+key_id+".p8")
    now=int(time.time())
    token=jwt.encode({"iss":"b5ac6a24-597d-4c46-924e-712ad41bf667","iat":now,"exp":now+900,"aud":"appstoreconnect-v1"},
                     key.read_bytes(),algorithm="ES256",headers={"kid":key_id,"typ":"JWT"})
    def get(path, params=None):
        url="https://api.appstoreconnect.apple.com"+path
        if params: url+="?"+urllib.parse.urlencode(params)
        req=urllib.request.Request(url,headers={"Authorization":"Bearer "+token})
        try:
            with urllib.request.urlopen(req,timeout=30) as response: return json.load(response)
        except urllib.error.HTTPError as error:
            data=json.loads(error.read())
            return {"errors":[{k:e.get(k) for k in ("status","code","title","detail")} for e in data.get("errors",[])]}
    wanted=("com.itorah.hanlinminiapps","com.davidpovarsky.chavrusatext","io.anytype.app.NA6HPWARQ2")
    all_bundles=get("/v1/bundleIds",{"limit":200})
    bundle_rows=all_bundles.get("data",[])
    if all_bundles.get("links",{}).get("next"):
        raise RuntimeError("Bundle audit requires pagination before completion")
    result={"schema":"hanlin.local-apple-resource-audit/1","observed_at":datetime.now(timezone.utc).isoformat(),
            "host":platform.node(),"execution":"installed ASC key in m1 SSH user session","team":"NA6HPWARQ2",
            "bundle_list_errors":all_bundles.get("errors",[]),"bundles":[],"apps":[]}
    for bundle in bundle_rows:
        identifier=bundle["attributes"]["identifier"]
        if not any(identifier==x or identifier.startswith(x+".") for x in wanted): continue
        bid=bundle["id"]
        caps=get("/v1/bundleIds/"+bid+"/bundleIdCapabilities")
        profiles=get("/v1/bundleIds/"+bid+"/profiles",{"limit":200})
        row={"identifier":identifier,"id":bid,"name":bundle["attributes"].get("name"),
             "capabilities":[{"id":c["id"],**c["attributes"]} for c in caps.get("data",[])],
             "capability_errors":caps.get("errors",[]),"profiles":[],"profile_errors":profiles.get("errors",[])}
        for item in profiles.get("data",[]):
            a=item["attributes"]
            profile={"id":item["id"],"name":a.get("name"),"uuid":a.get("uuid"),
                     "state":a.get("profileState"),"type":a.get("profileType"),"expiration":a.get("expirationDate")}
            if a.get("profileContent"):
                raw=base64.b64decode(a["profileContent"],validate=True)
                profile["cms_sha256"]=hashlib.sha256(raw).hexdigest()
                with tempfile.TemporaryDirectory(prefix="miniapps-profile-audit-") as tmp:
                    p=Path(tmp)/"input.mobileprovision"
                    p.write_bytes(raw); p.chmod(0o600)
                    decoded=subprocess.run(["security","cms","-D","-i",str(p)],capture_output=True,timeout=20)
                    if decoded.returncode:
                        profile["decode_error"]="security_cms_exit_"+str(decoded.returncode)
                    else:
                        data=plistlib.loads(decoded.stdout); e=data.get("Entitlements",{})
                        profile["entitlements"]=e
                        profile["certificate_sha256"]=[hashlib.sha256(x).hexdigest() for x in data.get("DeveloperCertificates",[])]
                        profile["team_identifiers"]=data.get("TeamIdentifier",[])
                        profile["device_count"]=len(data.get("ProvisionedDevices",[]))
            row["profiles"].append(profile)
        result["bundles"].append(row)
    for identifier in wanted:
        apps=get("/v1/apps",{"filter[bundleId]":identifier,"limit":10})
        for app in apps.get("data",[]):
            aid=app["id"]
            builds=get("/v1/builds",{"filter[app]":aid,"sort":"-uploadedDate","limit":3})
            result["apps"].append({"bundle_id":identifier,"id":aid,"name":app["attributes"].get("name"),
                 "latest_builds":[{"id":v["id"],**{k:v["attributes"].get(k) for k in
                     ("version","uploadedDate","processingState","expired","minOsVersion")}} for v in builds.get("data",[])],
                 "build_errors":builds.get("errors",[])})
        if apps.get("errors"): result["apps"].append({"bundle_id":identifier,"errors":apps["errors"]})
    out=Path(args.output); out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,ensure_ascii=False,indent=2,default=str)+"\n")
    print(json.dumps({"output":str(out),"sha256":hashlib.sha256(out.read_bytes()).hexdigest(),
        "bundle_count":len(result["bundles"]),"apps":result["apps"],
        "grants":[{"bundle":b["identifier"],"profile_count":len(b["profiles"]),
            "capability_errors":b["capability_errors"],
            "active_shared_profiles":sum(p["state"]=="ACTIVE" and
                "group.com.itorah.shared" in p.get("entitlements",{}).get("com.apple.security.application-groups",[])
                for p in b["profiles"]),
            "active_multicast_profiles":sum(p["state"]=="ACTIVE" and
                p.get("entitlements",{}).get("com.apple.developer.networking.multicast") is True
                for p in b["profiles"])} for b in result["bundles"]],
        "errors":result["bundle_list_errors"]},ensure_ascii=False,indent=2))
if __name__=="__main__": main()
