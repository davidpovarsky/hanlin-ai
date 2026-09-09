#!/usr/bin/env python3
"""Build the truthful, canonical runtime command coverage manifest.

Total operations: 58
- 23 Shell commands
- 14 ScriptUI commands
- 11 Inferred capabilities
- 8 App lifecycle operations
- 2 Canonical tool authority operations
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = Path(__file__).parent / "runtime-command-coverage-manifest.json"

SHELL_COMMANDS = [
    "awk", "cat", "cp", "curl", "grep", "head", "ln", "ls", "mkdir", "mv",
    "readlink", "rm", "rmdir", "sed", "sort", "stat", "tail", "tar", "touch",
    "tr", "uniq", "unlink", "wc"
]

SCRIPT_UI_COMMANDS = [
    ("render", "Render UI Root", "HanlinScriptUINode", "Void", True, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptUITests/HanlinScriptUIReconcilerTests.swift#renderedPresentation",
     "AI_HLYUITests/HanlinScriptUIProductionE2ETests.swift#testProductionScriptUIUserJourneyAndLifecycle"),
    ("patches", "Apply UI Patches", "[HanlinScriptUIPatch]", "Void", True, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptUITests/HanlinScriptUIReconcilerTests.swift#keyedDiff",
     None),
    ("event", "Dispatch UI Event", "handlerID: String, payload: HanlinValue", "Void", True, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptUITests/HanlinScriptUIReconcilerTests.swift#model",
     "AI_HLYUITests/HanlinScriptUIProductionE2ETests.swift#testProductionScriptUIUserJourneyAndLifecycle"),
    ("state", "Update Hook State", "hookID: String, value: HanlinValue", "Void", True, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptingApplicationRuntimeTests/HanlinScriptingApplicationRuntimeTests.swift#rendersIndependently",
     "AI_HLYUITests/HanlinScriptUIProductionE2ETests.swift#testProductionScriptUIUserJourneyAndLifecycle"),
    ("registerEffect", "Register Side Effect", "HanlinScriptUIEffect", "Void", True, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptUITests/HanlinScriptUIReconcilerTests.swift#model",
     None),
    ("releaseEffect", "Release Side Effect", "id: String", "Void", True, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptUITests/HanlinScriptUIReconcilerTests.swift#model",
     None),
    ("registerRoute", "Register Navigation Route", "route: HanlinScriptUIRoute, destination: HanlinScriptUINode", "Void", True, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptUITests/HanlinScriptUIReconcilerTests.swift#navigationAndResume",
     None),
    ("navigate", "Navigate Route", "HanlinScriptUIRoute", "Void", True, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptUITests/HanlinScriptUIReconcilerTests.swift#navigationAndResume",
     None),
    ("pop", "Pop Navigation Stack", "count: Int", "Void", True, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptUITests/HanlinScriptUIReconcilerTests.swift#navigationAndResume",
     None),
    ("selectTab", "Select Active Tab", "id: String", "Void", True, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptUITests/HanlinScriptUIReconcilerTests.swift#navigationAndResume",
     None),
    ("present", "Present Modal/Sheet/Dialog", "HanlinScriptUIPresentation", "Void", True, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptUITests/HanlinScriptUIReconcilerTests.swift#navigationAndResume",
     None),
    ("dismissPresentation", "Dismiss Active Presentation", "id: String", "Void", True, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptUITests/HanlinScriptUIReconcilerTests.swift#navigationAndResume",
     None),
    ("scenePhase", "Update Scene Phase", "HanlinScriptUIScenePhase", "Void", True, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptUITests/HanlinScriptUIReconcilerTests.swift#navigationAndResume",
     None),
    ("resume", "Resume External Launch Payload", "HanlinScriptResumePayload", "Void", True, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptUITests/HanlinScriptUIReconcilerTests.swift#navigationAndResume",
     None),
]

CAPABILITIES = [
    ("network", "HTTP and WebSockets networking", "HanlinScriptDeviceServices", "fetch, Request, Response",
     "Packages/HanlinPlatform/Tests/HanlinScriptServicesTests/HanlinScriptServiceBrokerTests.swift#network",
     "AI_HLYUITests/HanlinScriptUIProductionE2ETests.swift#testProductionScriptUIUserJourneyAndLifecycle"),
    ("storage", "Local key-value and cache storage", "HanlinScriptStore", "Storage.*",
     "Packages/HanlinPlatform/Tests/HanlinScriptServicesTests/HanlinScriptServiceBrokerTests.swift#storageAndFiles",
     None),
    ("files", "Document sandbox file system access", "HanlinScriptDeviceServices", "FileManager.*, DocumentPicker.*",
     "Packages/HanlinPlatform/Tests/HanlinScriptingApplicationRuntimeTests/HanlinScriptingApplicationRuntimeTests.swift#documentPickerAndQuickLookRuntime",
     None),
    ("assistant", "Native LLM assistant tools and invocation", "HanlinScriptCanonicalAdapter", "Assistant.*, AssistantTool.*",
     "Packages/HanlinPlatform/Tests/HanlinScriptServicesTests/HanlinScriptServiceBrokerTests.swift#brokeredServices",
     None),
    ("location", "CoreLocation positioning services", "HanlinScriptDeviceServices", "Location.*",
     "Packages/HanlinPlatform/Tests/HanlinScriptDeviceServicesTests/HanlinAppleServiceContractsTests.swift#requirements",
     None),
    ("notifications", "User notification scheduling and delivery", "HanlinScriptDeviceServices", "Notification.*",
     "Packages/HanlinPlatform/Tests/HanlinScriptDeviceServicesTests/HanlinAppleServiceContractsTests.swift#requirements",
     None),
    ("reminders", "EventKit calendar and reminder management", "HanlinScriptDeviceServices", "Reminder.*",
     "Packages/HanlinPlatform/Tests/HanlinScriptDeviceServicesTests/HanlinAppleServiceContractsTests.swift#requirements",
     None),
    ("health", "HealthKit query and record observation", "HanlinScriptDeviceServices", "Health.*",
     "Packages/HanlinPlatform/Tests/HanlinScriptDeviceServicesTests/HanlinAppleServiceContractsTests.swift#requirements",
     None),
    ("photos", "PhotoKit image library access", "HanlinScriptDeviceServices", "Photos.*",
     "Packages/HanlinPlatform/Tests/HanlinScriptingApplicationRuntimeTests/HanlinScriptingApplicationRuntimeTests.swift#photosRuntime",
     None),
    ("pasteboard", "System clipboard read and write", "HanlinScriptDeviceServices", "Pasteboard.*",
     "Packages/HanlinPlatform/Tests/HanlinScriptServicesTests/HanlinScriptServiceBrokerTests.swift#brokeredServices",
     None),
    ("open-url", "System external application routing and Safari", "HanlinScriptDeviceServices", "OpenURL.*, Safari.*",
     "Packages/HanlinPlatform/Tests/HanlinScriptServicesTests/HanlinScriptServiceBrokerTests.swift#brokeredServices",
     None),
]

APP_LIFECYCLE_OPS = [
    ("app.import_package", "Import Package", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift",
     "sourceURL: URL", "HanlinImportPreview", True, None, True, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptCompilerTests/HanlinPackageCenterTests.swift",
     "AI_HLYUITests/HanlinScriptUIProductionE2ETests.swift#testProductionScriptUIUserJourneyAndLifecycle", None),
    ("app.install_preview", "Install Preview", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift",
     "Void", "HanlinStoredPackageSnapshot", True, None, True, False,
     "AI_HLYTests/HanlinScriptingRuntimeTests.swift#testProductionPackageInstallAndExecutionLifecycle",
     "AI_HLYUITests/HanlinScriptUIProductionE2ETests.swift#testProductionScriptUIUserJourneyAndLifecycle", None),
    ("app.discard_preview", "Discard Preview", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift",
     "Void", "Void", False, None, False, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptCompilerTests/HanlinPackageCenterTests.swift",
     "AI_HLYUITests/HanlinScriptUIProductionE2ETests.swift#testScriptUIDiscardPreviewLifecycle", None),
    ("app.launch", "Launch Installed Application", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift",
     "id: HanlinInstalledPackageID", "Void", True, None, True, False,
     "AI_HLYTests/HanlinScriptingRuntimeTests.swift#testProductionPackageInstallAndExecutionLifecycle",
     "AI_HLYUITests/HanlinScriptUIProductionE2ETests.swift#testScriptUILaunchReEntrancyAndIsolation", None),
    ("app.dismiss_active", "Dismiss Active Application", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift",
     "Void", "Void", True, None, False, False,
     "AI_HLYTests/HanlinScriptingRuntimeTests.swift#testProductionPackageInstallAndExecutionLifecycle",
     "AI_HLYUITests/HanlinScriptUIProductionE2ETests.swift#testProductionScriptUIUserJourneyAndLifecycle", None),
    ("app.set_enabled", "Enable / Disable Package", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift",
     "enabled: Bool, id: HanlinInstalledPackageID", "Void", True, None, True, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptStoreTests/HanlinAtomicScriptStoreTests.swift",
     "AI_HLYUITests/HanlinScriptUIProductionE2ETests.swift#testProductionScriptUIUserJourneyAndLifecycle", None),
    ("app.set_capability_granted", "Grant / Revoke Capability", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift",
     "granted: Bool, capability: HanlinCapabilityID, id: HanlinInstalledPackageID", "Void", True, None, True, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptStoreTests/HanlinAtomicScriptStoreTests.swift",
     "AI_HLYUITests/HanlinScriptUIProductionE2ETests.swift#testProductionScriptUIUserJourneyAndLifecycle", None),
    ("app.uninstall", "Uninstall Package", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift",
     "id: HanlinInstalledPackageID", "Void", True, None, True, False,
     "Packages/HanlinPlatform/Tests/HanlinScriptStoreTests/HanlinAtomicScriptStoreTests.swift",
     "AI_HLYUITests/HanlinScriptUIProductionE2ETests.swift#testProductionScriptUIUserJourneyAndLifecycle", None),
]

TOOL_ROUTING_OPS = [
    ("tool_authority.resolve", "Resolve Tool Alias",
     "AI_HLY/Downstream/CanonicalTools/HanlinCanonicalToolAuthority.swift",
     "alias: String", "HanlinCanonicalToolAuthority.Resolution?", False, None, False, False,
     "AI_HLYTests/CanonicalToolAuthorityTests.swift#testCanonicalCatalogAliasResolution",
     None, None),
    ("tool_authority.invoke", "Invoke Canonical Tool",
     "AI_HLY/Downstream/MCP/ToolIntegration/AssistantToolBridge.swift",
     "alias: String, argumentsJSON: String, context: NativeToolExecutionContext",
     "NativeToolResult?", True, None, True, True,
     "AI_HLYTests/CanonicalToolAuthorityTests.swift#executionRoutesByBackend",
     None, None),
]

operations = []

# Shell commands (23)
for cmd in sorted(SHELL_COMMANDS):
    operations.append({
        "canonical_id": f"shell.{cmd}",
        "public_name": f"Shell command '{cmd}'",
        "authoritative_source": "Packages/IOSSystemLite/Sources/IOSSystemLite/IOSSystemRunner.swift",
        "runtime_bridge_owner": "IOSSystemLite (ios_system miniRoot)",
        "app_exposed": True,
        "inputs": f"argv: [String] (arguments for {cmd})",
        "outputs": "IOSSystemExecution (stdout, stderr, exitCode)",
        "state_mutation": cmd in ("cp", "ln", "mkdir", "mv", "rm", "rmdir", "touch", "unlink", "tar"),
        "capability_requirement": "network" if cmd == "curl" else None,
        "async_behavior": False,
        "cancellation_support": False,
        "existing_acceptance_test": "Scripts/Runtime/validate_shell_acceptance.py",
        "new_acceptance_test": "AI_HLYUITests/HanlinRuntimeCommandAcceptanceUITests.swift#testRuntimeCenterCommandSmokeAndCoherence",
        "justified_exclusion": None
    })

# ScriptUI commands (14)
for cmd, name, in_type, out_type, state_mut, is_async, is_cancel, exist_t, new_t in SCRIPT_UI_COMMANDS:
    operations.append({
        "canonical_id": f"script_ui.command.{cmd}",
        "public_name": f"ScriptUI command '{cmd}' ({name})",
        "authoritative_source": "Packages/HanlinPlatform/Sources/HanlinScriptUI/HanlinScriptUIContracts.swift",
        "runtime_bridge_owner": "HanlinScriptSessionCoordinator / HanlinScriptUIModel",
        "app_exposed": True,
        "inputs": in_type,
        "outputs": out_type,
        "state_mutation": state_mut,
        "capability_requirement": None,
        "async_behavior": is_async,
        "cancellation_support": is_cancel,
        "existing_acceptance_test": exist_t,
        "new_acceptance_test": new_t,
        "justified_exclusion": None
    })

# Inferred Capabilities (11)
for cap, desc, owner, symbols, exist_t, new_t in CAPABILITIES:
    operations.append({
        "canonical_id": f"capability.{cap}",
        "public_name": f"Capability '{cap}' ({desc})",
        "authoritative_source": "Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinScriptAnalyzer.swift",
        "runtime_bridge_owner": f"HanlinPlatform ({owner})",
        "app_exposed": True,
        "inputs": f"Requested by symbols: {symbols}",
        "outputs": "HanlinPermissionDecision (granted / denied)",
        "state_mutation": True,
        "capability_requirement": cap,
        "async_behavior": False,
        "cancellation_support": False,
        "existing_acceptance_test": exist_t,
        "new_acceptance_test": new_t,
        "justified_exclusion": None
    })

# App Lifecycle (8)
for cid, name, src, in_t, out_t, mut, cap, is_async, is_cancel, exist_t, new_t, excl in APP_LIFECYCLE_OPS:
    operations.append({
        "canonical_id": cid,
        "public_name": name,
        "authoritative_source": src,
        "runtime_bridge_owner": "HanlinScriptingPlatform",
        "app_exposed": True,
        "inputs": in_t,
        "outputs": out_t,
        "state_mutation": mut,
        "capability_requirement": cap,
        "async_behavior": is_async,
        "cancellation_support": is_cancel,
        "existing_acceptance_test": exist_t,
        "new_acceptance_test": new_t,
        "justified_exclusion": excl
    })

# Tool Routing / Authority (2)
for cid, name, src, in_t, out_t, mut, cap, is_async, is_cancel, exist_t, new_t, excl in TOOL_ROUTING_OPS:
    operations.append({
        "canonical_id": cid,
        "public_name": name,
        "authoritative_source": src,
        "runtime_bridge_owner": "HanlinCanonicalToolAuthority",
        "app_exposed": True,
        "inputs": in_t,
        "outputs": out_t,
        "state_mutation": mut,
        "capability_requirement": cap,
        "async_behavior": is_async,
        "cancellation_support": is_cancel,
        "existing_acceptance_test": exist_t,
        "new_acceptance_test": new_t,
        "justified_exclusion": excl
    })

manifest = {
    "schema_version": 1,
    "last_audited": "2026-09-09",
    "authoritative_sources": [
        "Packages/IOSSystemLite/Sources/IOSSystemLite/IOSSystemRunner.swift",
        "Packages/HanlinPlatform/Sources/HanlinScriptUI/HanlinScriptUIContracts.swift",
        "Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinScriptAnalyzer.swift",
        "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift",
        "AI_HLY/Downstream/CanonicalTools/HanlinCanonicalToolAuthority.swift",
        "AI_HLY/Downstream/MCP/ToolIntegration/AssistantToolBridge.swift"
    ],
    "operation_count": len(operations),
    "operations": operations
}

MANIFEST_PATH.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
print(f"Generated manifest with {len(operations)} operations at {MANIFEST_PATH}")
