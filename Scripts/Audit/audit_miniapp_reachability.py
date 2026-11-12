#!/usr/bin/env python3
"""Curated source-backed extension matrix. Never infers an executed E2E pass."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/miniapp-sdk"
RUNTIMES = ["node", "typeScript", "localPython", "javaScriptCore", "shell"]
ENGINES = ["hanlinNativeScript", "hanlinExpo"]


def build() -> dict:
    sdk = json.loads((OUT / "source-inventory.json").read_text(encoding="utf-8"))
    for entry in sdk["sources"]:
        if hashlib.sha256((ROOT / entry["path"]).read_bytes()).hexdigest() != entry["sha256"]:
            raise ValueError(f"SDK authority is stale: {entry['path']}; run its source audit first.")
    refs = {}

    def ref(name: str, file: str, anchor: str) -> str:
        data = (ROOT / file).read_bytes()
        text = data.decode("utf-8")
        if anchor not in text:
            raise ValueError(f"Audit anchor changed: {file}: {anchor}")
        refs[name] = {"file": file, "line": text[:text.index(anchor)].count("\n") + 1,
                      "anchor": anchor, "sha256": hashlib.sha256(data).hexdigest()}
        return name

    ref("shareWrite", "ChavrusaChatShare/ShareViewController.swift", "private func save(")
    ref("shareReadOnlyDeclaration", "AI_HLY/Downstream/SystemIntegrations/ChavrusaShareInbox.swift", "func pendingItems()")
    ref("translationSnapshot", "ChavrusaChatTranslationProvider/TranslationProviderMiniAppView.swift", "HanlinExtensionNodeView(")
    ref("extensionIntent", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptAppIntentBridge.swift", "public func perform()")
    ref("extensionQueue", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinInvocationQueue.swift", "public func enqueue(")
    ref("extensionReceipts", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinInvocationDelivery.swift", "public struct HanlinInvocationReceipt")
    ref("extensionExecutor", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinInvocationExecutor.swift", "public actor HanlinInvocationExecutor")
    ref("resume", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", "private func processPendingResumeCommands()")
    ref("headless", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", "func executeHeadlessAction(")
    ref("expoIntentRejection", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", "guard entrypoint.runtimeProfile != .hanlinExpo else")
    ref("expoExposureRejection", "Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinScriptAnalyzer.swift", "Expo exposure '")
    ref("widgetBundle", "HanlinScriptingWidgets/HanlinScriptingWidgets.swift", "struct HanlinScriptingWidgetBundle")
    ref("widgetCallback", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinWidgetActionExecutor.swift", "public static func perform(")
    ref("widgetIntent", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinGenericWidgetActionIntent.swift", "public func perform()")
    ref("shortcutIntent", "HanlinScriptingWidgets/HanlinScriptingAppIntents.swift", "struct HanlinRunScriptActionIntent")
    ref("hostShortcuts", "AI_HLY/Downstream/SystemIntegrations/ChavrusaSystemIntegrations.swift", "struct ChavrusaChatShortcuts")
    ref("notification", "ChavrusaChatNotificationService/NotificationService.swift", "override func didReceive(")
    ref("requestBroker", "Packages/HanlinPlatform/Sources/HanlinMiniAppCore/HanlinMiniAppRequestBroker.swift", "public func request(")
    ref("nativeBridge", "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/include/HanlinNativeServicesBridge.h", "@protocol HanlinNativeServicesProvider")
    ref("nativeAdapter", "AI_HLY/Downstream/HostServices/Adapters/NativeScriptHostServicesAdapter.swift", "public func executeJavaScript(")
    ref("nativeSession", "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/HanlinNativeScriptSession.swift", "guard Self.activeSession == nil")
    ref("expoFacade", "Packages/HanlinExpoUI/src/host-services.ts", "executeRuntime(")
    ref("expoModule", "Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinHostServicesModule.swift", 'AsyncFunction("invoke")')
    ref("expoAdapter", "AI_HLY/Downstream/HostServices/Adapters/ExpoHostServicesAdapter.swift", 'case "runtime.execute":')
    ref("runtimeBroker", "AI_HLY/Downstream/HostServices/Runtime/HanlinRuntimeBroker.swift", "func execute(")
    ref("callerContext", "AI_HLY/Downstream/HostServices/Core/HanlinHostCallContext.swift", "public struct HanlinHostCallContext")
    ref("systemBroker", "AI_HLY/Downstream/HostServices/System/HanlinSystemServicesBroker.swift", "public actor HanlinSystemServicesBroker")
    ref("appBootstrap", "AI_HLY/AI_HLY.swift", "@main")
    ref("projectTargets", "AI_HLY.xcodeproj/project.pbxproj", "/* Begin PBXNativeTarget section */")
    ref("audit", "Scripts/Audit/audit_miniapp_reachability.py", "Curated source-backed extension matrix")
    for target in ["ChavrusaChatShare", "ChavrusaChatTranslationProvider", "HanlinScriptingWidgets", "ChavrusaChatNotificationService"]:
        ref(target + "Info", target + "/Info.plist", "<plist")

    tracked = subprocess.check_output(["git", "ls-files", "*.swift"], cwd=ROOT, text=True, encoding="utf-8").splitlines()
    share_references = [p for p in tracked if "ChavrusaShareInbox" in (ROOT / p).read_text(encoding="utf-8-sig")]
    if share_references != ["AI_HLY/Downstream/SystemIntegrations/ChavrusaShareInbox.swift"]:
        raise ValueError(f"Share inbox callers changed; re-audit reachability: {share_references}")
    optional_surfaces = {symbol: [p for p in tracked if re.search(rf"\b{symbol}\b", (ROOT / p).read_text(encoding="utf-8-sig"))]
                         for symbol in ["ControlWidget", "CSSearchableIndex", "CoreSpotlight"]}
    project = (ROOT / "AI_HLY.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    targets = project.split("/* Begin PBXNativeTarget section */")[1].split("/* End PBXNativeTarget section */")[0]
    target_names = sorted(re.findall(r"\bname = ([^;]+);", targets))
    entitlement_files = ["AI_HLY/AI_HLY.entitlements"] + [
        f"{target}/{target}.entitlements" for target in ["ChavrusaChatShare", "ChavrusaChatTranslationProvider", "HanlinScriptingWidgets", "ChavrusaChatNotificationService"]]
    entitlements = {}
    for file in entitlement_files:
        data = (ROOT / file).read_bytes()
        entitlements[file] = {"declared": plistlib.loads(data), "sha256": hashlib.sha256(data).hexdigest(),
                              "exportedSignatureVerified": False}
    paths = {
        "share": {"target": "ChavrusaChatShare", "refs": ["shareWrite", "shareReadOnlyDeclaration"],
                  "stop": "share-inbox.json has no Host consumer; only borrowed provider URLs are persisted, not an owned attachment transaction.", "owner": "INT-04"},
        "translation": {"target": "ChavrusaChatTranslationProvider", "refs": ["translationSnapshot", "extensionIntent", "extensionQueue", "resume", "expoExposureRejection"],
                        "stop": "Declarative snapshot/action continuation is not an NS/Expo runtime route. Resume requires an appIntent entrypoint; Expo non-widget exposure is rejected.", "owner": "INT-02/INT-03"},
        "widget": {"target": "HanlinScriptingWidgets", "refs": ["widgetBundle", "widgetIntent", "widgetCallback"],
                   "stop": "Existing Expo/ScriptWidget callbacks commit revision/nonces in the widget-specific runtime. They do not expose the five canonical Host runtimes or an NS foreground VM.", "owner": "INT-02/INT-03"},
        "notification": {"target": "ChavrusaChatNotificationService", "refs": ["notification"],
                         "stop": "Media attachment/category delivery only; no authenticated package event envelope, Host consumer or MiniApp receipt.", "owner": "INT-05"},
        "liveActivity": {"target": "HanlinScriptingWidgets", "refs": ["widgetBundle", "extensionIntent", "extensionQueue"],
                         "stop": "Static ActivityKit presentation is not a canonical Node/TS/Python/JSC/Shell execution path.", "owner": "INT-02/INT-03"},
        "hostAppIntent": {"target": "AI_Hanlin / HanlinScriptExtensions", "refs": ["extensionIntent", "extensionQueue", "extensionReceipts", "extensionExecutor", "resume", "requestBroker", "headless", "nativeSession", "expoIntentRejection"],
                          "stop": "NS declared action can dispatch through the existing broker and persist its action value/status in a protected durable receipt. Busy NS session yields needsForeground; Expo yields an explicit unsupported receipt. Generic runtime callbacks, readback to system ingress and presentation-context propagation remain incomplete; native delivery tests pending.", "owner": "INT-02/INT-03"},
        "shortcuts": {"target": "HanlinScriptingWidgets / AI_Hanlin", "refs": ["shortcutIntent", "hostShortcuts", "extensionQueue", "extensionReceipts", "extensionExecutor", "resume", "headless", "expoIntentRejection"],
                      "stop": "Generic MiniApp action enqueues foreground continuation. Registered Siri phrases are alarm/notification operations; not an all-runtime MiniApp API.", "owner": "INT-02/INT-03"},
        "foreground": {"target": "AI_Hanlin", "refs": ["nativeBridge", "nativeAdapter", "nativeSession", "expoFacade", "expoModule", "expoAdapter", "runtimeBroker", "callerContext"],
                       "stop": "Source-wired Host calls still require real JS->native->executor->receipt tests; legacy NS strings lose stderr/status/artifacts and generic TS/Shell are absent.", "owner": "INT-03/INT-06/SDK-03/SDK-04"},
    }
    rows = []
    for surface, route in paths.items():
        for engine in ENGINES:
            for runtime in RUNTIMES:
                has_tail = engine == "hanlinExpo" or runtime in ["node", "localPython", "javaScriptCore"]
                connected_source = surface == "foreground" or (surface in ["hostAppIntent", "shortcuts"] and engine == "hanlinNativeScript")
                wired = has_tail and connected_source
                structured_receipt = wired and surface == "foreground" and engine == "hanlinExpo"
                rows.append({"surface": surface, "engine": engine, "runtime": runtime,
                    "status": "not-tested" if structured_receipt else "partially-wired" if wired else "disconnected", "path": surface,
                    "runtimeTail": (["expoFacade", "expoModule", "expoAdapter", "runtimeBroker"] if engine == "hanlinExpo"
                                    else ["nativeBridge", "nativeAdapter", "runtimeBroker"]) if has_tail else [],
                    "sourcePathReachesCanonicalExecutor": wired,
                    "structuredReceiptReturnedToIngressInSource": structured_receipt,
                    "durableActionReceiptInSource": surface in ["hostAppIntent", "shortcuts"] and engine == "hanlinNativeScript",
                    "realSurfaceE2E": False, "onDeviceProof": None,
                    "resultBoundary": "Legacy string/error callback" if wired and engine == "hanlinNativeScript" else
                                      "Typed RuntimeExecutionResult in foreground facade; per-surface E2E missing" if wired else "No connected canonical-runtime receipt",
                    "callerContext": {"hostAdapterReachable": wired, "canPresentUI": True if wired else None,
                        "userGesturePresent": False if wired else None,
                        "note": "NS headless path currently inherits the adapter's hardcoded canPresentUI=true; actual invocation context must be propagated" if wired and surface != "foreground" else
                                "Host-bound package/session identity" if wired else "No canonical Host call context is connected from this ingress"},
                    "engineVersionSource": "source-inventory.json#/" + ("expo" if engine == "hanlinExpo" else "nativeScript"),
                    "permissions": ["Declared App Group is not exported-signature proof", "Actual service OS permission/availability still required"],
                    "followUp": route["owner"]})
    if len(rows) != 80 or len({(r['surface'], r['engine'], r['runtime']) for r in rows}) != 80:
        raise ValueError("Incomplete or duplicate matrix")
    changed = subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=all"], cwd=ROOT, text=True, encoding="utf-8").splitlines()
    changed_paths = {line[3:].replace("\\", "/") for line in changed if line}
    return {"schemaVersion": 1, "sourceCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "snapshotIdentity": "Base commit plus exact current hashes; uncommitted audit sources are listed separately",
        "uncommittedSourcePaths": sorted({r["file"] for r in refs.values()} & changed_paths),
        "status": "IN_PROGRESS_SOURCE_AUDIT", "sdkAuthority": "source-inventory.json",
        "sdkSources": sdk["sources"], "history": {"ownerTestFlightBuild": "93401", "source": "7fa8fe26",
            "boundary": "Historical owner delivery only; not current branch/signature/matrix acceptance"},
        "targetsDeclaredInProject": target_names, "entitlements": entitlements, "optionalSurfaceSymbolScan": optional_surfaces,
        "sourceRefs": refs, "paths": paths, "matrix": rows,
        "systemServices": {"authority": "source-inventory.json#/systemServices",
            "publicBindingStatus": {e: "No generic SystemServicesBroker binding in the inspected Host bridge; direct native metadata APIs are a separate, unverified path" for e in ENGINES},
            "availabilityIsNotGrantMetadata": True, "devicePermissionChecksExecuted": False},
        "acceptance": {"fourExtensionsByTwoEnginesByFiveRuntimes": 40, "additionalSurfaceCells": 40,
            "executedSurfaceE2EPasses": 0, "signedPhysicalAcceptance": "NOT_RUN"}}


def markdown(value: dict) -> str:
    lines = ["# NativeScript / Expo extension reachability", "", "Status: **IN_PROGRESS — source audit only**.", "",
        f"Base commit: `{value['sourceCommit']}`. Exact current file hashes and line anchors are in [the JSON matrix](extension-reachability.json).",
        "Runtime/API/version authority is [source-inventory.json](source-inventory.json); this matrix consumes it rather than maintaining a second SDK contract.", "",
        "The four actual extension targets × two engines × five canonical runtimes form40 cells. Live Activity, Host AppIntent, Shortcuts and foreground add40 more.",
        "A declared bridge, rendered snapshot, queued command or widget-local callback is not a complete ingress → executor → returned receipt proof. No signed physical or per-surface E2E pass is inferred.", "",
        "| Surface | Engine | Node | TS | Python | JSC | Shell |", "|---|---|---|---|---|---|---|"]
    for surface in value["paths"]:
        for engine in ENGINES:
            states = [next(r["status"] for r in value["matrix"] if r["surface"] == surface and r["engine"] == engine and r["runtime"] == runtime) for runtime in RUNTIMES]
            lines.append("| " + " | ".join([surface, engine] + states) + " |")
    lines += ["", "## Existing path boundaries", ""]
    for surface, route in value["paths"].items():
        links = []
        for key in route["refs"]:
            ref = value["sourceRefs"][key]
            links.append(f"[{key}](../../{ref['file']}#L{ref['line']})")
        lines += [f"- **{surface}** ({route['target']}): {route['stop']} Follow-up: {route['owner']}. Sources: " + ", ".join(links) + "."]
    lines += ["", "## Identity, permissions and proof", "",
        "- App Group/other entitlements in JSON are source declarations. Exported signed entitlement/profile identity is NOT_VERIFIED here.",
        "- TestFlight93401 is the historical owner delivery at7fa8fe26. It does not prove this branch, current framework identity, or this matrix. No IPA is generated by this audit.",
        "- NS Node/Python/JSC legacy callbacks are string/error callbacks. Generic TS/Shell and full structured results are missing. One global active NS session requires real arbitration, not a second unowned VM.",
        "- Expo's existing TypeScript facade validates all5 canonical kinds through invoke(runtime.execute). Its native legacy executeRuntime now rejects unknown kinds and propagates failure/cancellation; actual five-backend regressions and complete JS receipt coverage remain pending under INT-06.",
        "- The17 SystemServicesBroker declarations are inventoried separately. They do not prove a public NS/Expo binding, actual OS permission, UI presentation context or device availability. Direct native metadata calls are a separate path.",
        "- ControlWidget/CoreSpotlight names occur in exposure contracts; the source scan does not find an implemented corresponding target/index. They are not added as executable surfaces.",
        "- The existing ResumeQueue now carries delivery metadata, leases, duplicate/TTL/cancel handling and protected durable Receipts. Its host dispatcher retains actual action values; this is not yet a complete generic runtime/attachment/system-ingress result contract. Native queue/executor tests are pending. No new engine or automatic Host Node/Python/Shell launch inside an extension.", "",
        "## Verification", "", "Run the SDK source audit first, then `py -3 Scripts/Audit/audit_miniapp_reachability.py --check`. Both fail on source drift; runtime execution is not part of this audit.",
        "INT-02/03/04/05/06/07 and SDK-02…08 remain open. This is the prerequisite map, not their implementation or final acceptance.", ""]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    value = build()
    output = OUT / "extension-reachability.json"
    if args.check:
        prior = json.loads(output.read_text(encoding="utf-8"))
        recorded_commit = prior["sourceCommit"]
        prior.pop("sourceCommit", None)
        prior.pop("uncommittedSourcePaths", None)
        value.pop("sourceCommit", None)
        value.pop("uncommittedSourcePaths", None)
        if prior != value:
            raise SystemExit("Extension source inventory drift; re-audit before regenerating.")
        value["sourceCommit"] = recorded_commit
        if (OUT / "extension-reachability.md").read_text(encoding="utf-8") != markdown(value):
            raise SystemExit("Reachability Markdown differs from the versioned matrix.")
        print("PASS: 80 unique source-backed reachability cells; no E2E pass inferred.")
    else:
        output.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        (OUT / "extension-reachability.md").write_text(markdown(value), encoding="utf-8", newline="\n")
        print("Wrote 80 reachability cells; four-extension matrix = 40. All physical/E2E gates remain open.")


if __name__ == "__main__":
    main()
