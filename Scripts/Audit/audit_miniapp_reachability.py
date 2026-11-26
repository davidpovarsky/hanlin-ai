#!/usr/bin/env python3
"""Curated source-backed extension matrix. Never infers an executed E2E pass."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from Scripts.CI.IntegrationValidation.project_graph import parse_project
OUT = ROOT / "docs/miniapp-sdk"
RUNTIMES = ["node", "typeScript", "localPython", "javaScriptCore", "shell"]
ENGINES = ["hanlinNativeScript", "hanlinExpo"]


class TrackedSources:
    """Read working bytes first; missing tracked files use their exact HEAD blob."""

    def __init__(self, root: Path):
        self.root = root
        self.tracked = set(subprocess.check_output(
            ["git", "ls-files", "-z"], cwd=root).decode("utf-8").split("\0")) - {""}
        self.cache = {}

    def prefetch(self, files) -> None:
        missing = []
        for file in dict.fromkeys(files):
            relative = PurePosixPath(file)
            if relative.is_absolute() or ".." in relative.parts or str(relative) != file or file not in self.tracked:
                raise ValueError(f"Audit source is not a normalized tracked file: {file}")
            if file in self.cache:
                continue
            local = self.root / file
            if local.exists() or local.is_symlink():
                self.cache[file] = local.read_bytes()
            else:
                if "\n" in file or "\r" in file:
                    raise ValueError(f"Audit source cannot be addressed by the git batch protocol: {file!r}")
                missing.append(file)
        if not missing:
            return
        # Equivalent to git show HEAD:path, batched for sparse Swift inventories.
        result = subprocess.run(["git", "cat-file", "--batch"], cwd=self.root,
            input="".join(f"HEAD:{file}\n" for file in missing).encode("utf-8"),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        output, position = result.stdout, 0
        for file in missing:
            end = output.find(b"\n", position)
            header = output[position:end].split()
            if end < position or len(header) != 3 or header[1] != b"blob" or not header[2].isdigit():
                raise ValueError(f"Missing tracked HEAD source: {file}: {output[position:end]!r}")
            size = int(header[2])
            position = end + 1
            if position + size >= len(output) or output[position + size:position + size + 1] != b"\n":
                raise ValueError(f"Incomplete tracked HEAD blob: {file}")
            self.cache[file] = output[position:position + size]
            position += size + 1
        if position != len(output):
            raise ValueError("Unexpected trailing data in tracked source batch")

    def read_bytes(self, file: str) -> bytes:
        self.prefetch([file])
        return self.cache[file]

    def read_text(self, file: str) -> str:
        return self.read_bytes(file).decode("utf-8-sig")


def build() -> dict:
    sources = TrackedSources(ROOT)
    sdk = json.loads(sources.read_text("docs/miniapp-sdk/source-inventory.json"))
    sources.prefetch(entry["path"] for entry in sdk["sources"])
    for entry in sdk["sources"]:
        if hashlib.sha256(sources.read_bytes(entry["path"])).hexdigest() != entry["sha256"]:
            raise ValueError(f"SDK authority is stale: {entry['path']}; run its source audit first.")
    refs = {}

    def ref(name: str, file: str, anchor: str) -> str:
        data = sources.read_bytes(file)
        text = data.decode("utf-8")
        if anchor not in text:
            raise ValueError(f"Audit anchor changed: {file}: {anchor}")
        refs[name] = {"file": file, "line": text[:text.index(anchor)].count("\n") + 1,
                      "anchor": anchor, "sha256": hashlib.sha256(data).hexdigest()}
        return name

    ref("shareWrite", "Packages/HanlinAppExtensionsSDK/Sources/HanlinShareExtensionUI/HanlinShareViewController.swift", "store.commit(batchID, items: items)")
    ref("shareOwnedStore", "Packages/HanlinPlatform/Sources/HanlinScriptStore/HanlinShareInboxStore.swift", "public struct HanlinShareInboxStore")
    ref("shareProviderCopy", "Packages/HanlinPlatform/Sources/HanlinScriptStore/HanlinShareItemLoader.swift", "return provider.loadFileRepresentation(")
    ref("shareRead", "AI_HLY/Downstream/SystemIntegrations/ChavrusaShareInbox.swift", "func pendingBatches()")
    ref("shareReview", "AI_HLY/Downstream/SystemIntegrations/ChavrusaShareInboxView.swift", "struct ChavrusaShareInboxView")
    ref("shareSelection", "AI_HLY/Downstream/SystemIntegrations/ChavrusaShareActionTarget.swift", "var shareActionTargets:")
    ref("translationSnapshot", "Packages/HanlinAppExtensionsSDK/Sources/HanlinTranslationUI/TranslationProviderMiniAppView.swift", "HanlinExtensionNodeView(")
    ref("extensionIntent", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptAppIntentBridge.swift", "public func perform()")
    ref("extensionQueue", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinInvocationQueue.swift", "public func enqueue(")
    ref("extensionReceipts", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinInvocationDelivery.swift", "public struct HanlinInvocationReceipt")
    ref("extensionExecutor", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinInvocationExecutor.swift", "public actor HanlinInvocationExecutor")
    ref("resume", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", "private func processPendingResumeCommands()")
    ref("assistantDeclaration", "Packages/HanlinPlatform/Sources/HanlinScriptContracts/HanlinPreparedAssistantToolDeclaration.swift", "public struct HanlinPreparedAssistantToolDeclaration")
    ref("assistantProjection", "Packages/HanlinPlatform/Sources/HanlinScriptStore/HanlinStoredPackageSnapshot+AssistantTools.swift", "public func preparedAssistantTools()")
    ref("assistantAdapter", "AI_HLY/Downstream/Scripting/HanlinScriptCanonicalAdapter.swift", "struct HanlinPreparedAssistantToolAdapter")
    ref("assistantCanonicalSources", "AI_HLY/Downstream/Scripting/HanlinScriptCanonicalAdapter.swift", "func canonicalSources()")
    ref("assistantCatalog", "AI_HLY/Downstream/MCP/ToolIntegration/AssistantToolBridge.swift", ") + preparedCatalog.sources")
    ref("assistantCatalogUnavailable", "AI_HLY/Downstream/Scripting/HanlinScriptCanonicalAdapter.swift", 'NativeToolTraceLogger.shared.log("prepared_miniapp_tool_catalog_unavailable"')
    ref("assistantProviderDispatch", "AI_HLY/Downstream/MCP/ToolIntegration/AssistantToolBridge.swift", "result = await preparedTools.execute(route: route, argumentsJSON: argumentsJSON)")
    ref("assistantActualResult", "AI_HLY/Downstream/Scripting/HanlinScriptCanonicalAdapter.swift", "let value = try await dispatch(expected, HanlinValue(json: json))")
    ref("assistantForegroundDispatch", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", "func executePreparedAssistantTool(")
    ref("assistantBrokerDispatch", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", "let response = try await HanlinMiniAppHost.shared.requestBroker.request(")
    ref("assistantAuthoring", "AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs", "function validatePreparedAssistantTools(input)")
    ref("assistantPublicTypes", "Scripts/MiniApps/native-presentations.d.ts", "export type PreparedAssistantToolAction")
    ref("headless", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", "func executeHeadlessAction(")
    ref("expoActionDispatch", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", "return try await adapter.actionChannel.invoke(")
    ref("nativeActionDispatch", "AI_HLY/Downstream/HostServices/Adapters/NativeScriptHostServicesAdapter.swift", "func invokeRegisteredAction(")
    ref("resumeDispatch", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", "func dispatchResumeCommand(")
    ref("translationContinuation", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", '"source": .string("translationUI")')
    ref("translationAction", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinExtensionNodeView.swift", "private var scriptActionIntent: HanlinInvokeScriptActionIntent?")
    ref("widgetBundle", "HanlinScriptingWidgets/HanlinScriptingWidgets.swift", "struct HanlinScriptingWidgetBundle")
    ref("widgetCallback", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinWidgetActionExecutor.swift", "public static func perform(")
    ref("widgetIntent", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinGenericWidgetActionIntent.swift", "public func perform()")
    ref("widgetHostDeclaration", "Packages/HanlinPlatform/Sources/HanlinScriptContracts/HanlinWidgetProgram.swift", "public struct HanlinWidgetHostAction")
    ref("widgetHostCompiler", "Packages/HanlinPlatform/Sources/HanlinWidgetCompiler/HanlinWidgetCompiler.swift", "public static func validateHostActionTargets(")
    ref("widgetHostExecutor", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinWidgetHostAction.swift", "public enum HanlinWidgetHostActionExecutor")
    ref("widgetHostIntent", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinWidgetHostActionIntent.swift", "public func perform()")
    ref("widgetHostWake", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinWidgetHostAction.swift", "public enum HanlinWidgetHostActionContinuation")
    ref("nativeNodeActivityIntent", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinLiveActivityHostActionIntent.swift", "public func perform()")
    ref("nativeNodeActivityAction", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinExtensionNodeView.swift", "if invocationSource == .liveActivity")
    ref("expoWidgetHostButton", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ExpoWidgets/HanlinExpoWidgetsViewRenderer.swift", "HanlinWidgetHostActionIntent")
    ref("scriptWidgetHostButton", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/Original/Component/Elements/ScriptWidgetElementTagButton.swift", "HanlinWidgetHostActionIntent")
    ref("shortcutIntent", "Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/HanlinScriptingAppIntents.swift", "struct HanlinRunScriptActionIntent")
    ref("hostShortcuts", "AI_HLY/Downstream/SystemIntegrations/ChavrusaSystemIntegrations.swift", "struct ChavrusaChatShortcuts")
    ref("notification", "Packages/HanlinAppExtensionsSDK/Sources/HanlinNotificationExtension/HanlinNotificationService.swift", "override func didReceive(")
    ref("miniAppsNotificationPrincipal", "HanlinMiniAppsExtensions/Notification/NotificationService.swift", "final class NotificationService")
    ref("notificationEvent", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinNotificationEvent.swift", "public struct HanlinNotificationEvent")
    ref("notificationQueue", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinNotificationInvocation.swift", "public static func enqueue(")
    ref("notificationTarget", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinNotificationInvocation.swift", "public static func validateTarget(")
    ref("notificationHostDelegate", "AI_HLY/Downstream/ScriptingPlatform/HanlinNotificationApplicationDelegate.swift", "public final class HanlinNotificationApplicationDelegate")
    ref("notificationForeground", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", "func resumePendingInvocations(")
    ref("requestBroker", "Packages/HanlinPlatform/Sources/HanlinMiniAppCore/HanlinMiniAppRequestBroker.swift", "public func request(")
    ref("nativeBridge", "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/include/HanlinNativeServicesBridge.h", "@protocol HanlinNativeServicesProvider")
    ref("nativeAdapter", "AI_HLY/Downstream/HostServices/Adapters/NativeScriptHostServicesAdapter.swift", "public func executeRuntime(")
    ref("nativeFacade", "Scripts/NativeScript/host-services.ts", "export function createHostServices()")
    ref("runtimeWire", "AI_HLY/Downstream/HostServices/Runtime/HanlinRuntimeWireProtocol.swift", "enum HanlinRuntimeWireProtocol")
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
    ref("miniAppsBootstrap", "HanlinMiniAppsApp/HanlinMiniAppsApp.swift", "@main")
    ref("miniAppsWidgetBundle", "HanlinMiniAppsExtensions/Widgets/HanlinMiniAppsWidgets.swift", "struct HanlinMiniAppsWidgetBundle")
    ref("sharePrincipal", "ChavrusaChatShare/ShareViewController.swift", "ShareViewController: HanlinShareViewController")
    ref("miniAppsSharePrincipal", "HanlinMiniAppsExtensions/Share/ShareViewController.swift", "ShareViewController: HanlinShareViewController")
    ref("nativeRuntimeDispatch", "AI_HLY/Downstream/HostServices/Adapters/NativeScriptHostServicesAdapter.swift", "HanlinRuntimeWireProtocol.execute(")
    ref("expoRuntimeDispatch", "AI_HLY/Downstream/HostServices/Adapters/ExpoHostServicesAdapter.swift", "HanlinRuntimeWireProtocol.execute(")
    ref("nativePresentationExecutor", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinNativePresentation.swift", "public enum HanlinNativePresentationExecutor")
    ref("nativePresentationView", "Packages/HanlinAppExtensionsSDK/Sources/HanlinTranslationUI/HanlinNativePresentationView.swift", "public struct HanlinNativePresentationContentView")
    ref("nativeSnippet", "Packages/HanlinAppExtensionsSDK/Sources/HanlinTranslationUI/HanlinNativePresentationView.swift", "public struct HanlinShowMiniAppSnippetIntent")
    ref("nativeTranslation", "Packages/HanlinAppExtensionsSDK/Sources/HanlinTranslationUI/TranslationProviderNativePresentationView.swift", "session.context.finish(translation:")
    ref("originalControlWidgets", "Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/ScriptWidgetControls/Original/ScriptWidgetControlWidget.swift", "public struct ScriptWidgetButtonControlWidget: ControlWidget")
    ref("originalToggleWidget", "Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/ScriptWidgetControls/Original/ScriptWidgetControlWidget.swift", "public struct ScriptWidgetControlWidget: ControlWidget")
    ref("originalControlProvider", "Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/ScriptWidgetControls/Original/ScriptWidgetSelectTimerIntent.swift", "public struct ScriptWidgetButtonControlProvider")
    ref("originalControlActions", "Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/ScriptWidgetControls/Original/ScriptWidgetSelectTimerIntent.swift", "HanlinScriptWidgetControlCatalog.perform(")
    ref("controlCatalog", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptWidgetControls.swift", "public enum HanlinScriptWidgetControlCatalog")
    ref("controlCompiler", "Packages/HanlinPlatform/Sources/HanlinWidgetCompiler/HanlinWidgetCompiler.swift", "HanlinOriginalScriptWidgetControls.read(data, entryPath: entryPath)")
    ref("controlUpstream", "docs/widget-engines/UPSTREAM_SOURCE_MANIFEST.json", "ScriptWidgetControls/Original/ScriptWidgetControlWidget.swift")
    ref("controlSourceRefresh", "Scripts/MiniApps/refresh-original-sources.mjs", "const controlTargetRoot=")
    ref("scriptWidgetLiveActivity", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptWidgetLiveActivity.swift", "public enum HanlinScriptWidgetLiveActivityController")
    ref("scriptWidgetActivityRenderer", "Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/HanlinScriptingWidgets.swift", "public struct HanlinOriginalScriptWidgetLiveActivityWidget")
    ref("originalExpoWidget", "Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/HanlinOriginalExpoWidget.swift", "public struct HanlinOriginalExpoWidget: Widget")
    ref("originalExpoModule", "Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Original/WidgetsModule.swift", "public final class WidgetsModule: Module")
    ref("originalExpoActivity", "Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Original/Widgets/WidgetLiveActivity.swift", "public struct WidgetLiveActivity")
    ref("originalExpoRegistry", "Packages/HanlinExpoRuntime/Sources/ExpoWidgets/HanlinExpoWidgetsIntegration.swift", "public enum HanlinExpoWidgetsIntegration")
    ref("shareSDKFacade", "AI_HLY/Downstream/SDK/HanlinApplicationComponents.swift", "func prepareSharedDraft(")
    ref("shareComposer", "AI_HLY/Views/Components/ChatViewBottom.swift", "ChavrusaShareInboxView(platform: .shared, useInChat:")
    ref("hostControlButtonRegistration", "HanlinScriptingWidgets/HanlinScriptingWidgets.swift", "ScriptWidgetButtonControlWidget()")
    ref("hostControlToggleRegistration", "HanlinScriptingWidgets/HanlinScriptingWidgets.swift", "ScriptWidgetControlWidget()")
    ref("miniAppsControlButtonRegistration", "HanlinMiniAppsExtensions/Widgets/HanlinMiniAppsWidgets.swift", "ScriptWidgetButtonControlWidget()")
    ref("miniAppsControlToggleRegistration", "HanlinMiniAppsExtensions/Widgets/HanlinMiniAppsWidgets.swift", "ScriptWidgetControlWidget()")
    ref("currentScope", "docs/miniapp-sdk/README.md", "## Entry points and native surfaces")
    ref("installedSystemCatalog", "AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppSystemCatalog.swift", "enum HanlinMiniAppSystemCatalog")
    ref("installedEntityQuery", "AI_HLY/Downstream/ScriptingPlatform/HanlinInstalledMiniAppEntity.swift", "public struct HanlinInstalledMiniAppQuery")
    ref("spotlightOpen", "AI_HLY/Downstream/ScriptingPlatform/HanlinInstalledMiniAppEntity.swift", "public struct HanlinOpenInstalledMiniAppIntent: OpenIntent")
    ref("spotlightIndex", "AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppSpotlightIndex.swift", "try await index.indexAppEntities(")
    ref("spotlightRemove", "AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppSpotlightIndex.swift", "try await index.deleteAppEntities(")
    ref("systemCatalogPublication", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", "await HanlinMiniAppSystemEntrypoints.shared.reconcile(")
    ref("nativePresentationPublication", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", "nativePresentations: nativePresentations,")
    ref("systemEntrypointOpen", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", "func openSystemEntrypoint(")
    ref("systemEntrypointAdmission", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift", "if entrypoint.kind == .assistantTool || entrypoint.kind == .spotlight || entrypoint.kind == .capture {")
    ref("cameraIntent", "Packages/HanlinAppExtensionsSDK/Sources/HanlinCameraCaptureUI/HanlinCameraCaptureIntent.swift", "public struct HanlinCameraCaptureIntent: CameraCaptureIntent")
    ref("cameraControl", "Packages/HanlinAppExtensionsSDK/Sources/HanlinCameraCaptureUI/HanlinCameraCaptureIntent.swift", "ControlWidgetButton(action: HanlinCameraCaptureIntent())")
    ref("cameraPhoto", "Packages/HanlinAppExtensionsSDK/Sources/HanlinCameraCaptureUI/HanlinCameraService.swift", "output.capturePhoto(with: settings, delegate: delegate)")
    ref("cameraHardwareEvent", "Packages/HanlinAppExtensionsSDK/Sources/HanlinCameraCaptureUI/HanlinCameraCaptureView.swift", "AVCaptureEventInteraction")
    ref("cameraHandoff", "Packages/HanlinAppExtensionsSDK/Sources/HanlinCameraCaptureUI/HanlinCameraCaptureView.swift", "try await session.openApplication(for: activity)")
    ref("cameraAppContext", "AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppCaptureCoordinator.swift", "try await HanlinCameraCaptureIntent.updateAppContext(target)")
    ref("cameraSystemReceive", "AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppCaptureCoordinator.swift", "LockedCameraCaptureManager.shared.sessionContentUpdates")
    ref("cameraDurableCopy", "AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppCaptureInbox.swift", "func receive(directory: URL) throws -> HanlinMiniAppCaptureRecord")
    ref("cameraPackageCopy", "AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppCaptureInbox.swift", "func copyPhotos(for id: UUID, documents: URL) throws -> [URL]")
    ref("cameraActionContinuation", "AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppCaptureCoordinator.swift", "invocationID: record.invocationID, createdAt: record.invocationCreatedAt")
    ref("capturePrincipal", "ChavrusaChatCameraCapture/HanlinCameraCapture.swift", "struct HanlinCameraCaptureExtension: LockedCameraCaptureExtension")
    ref("miniAppsCapturePrincipal", "HanlinMiniAppsExtensions/CameraCapture/HanlinMiniAppsCameraCapture.swift", "struct HanlinMiniAppsCameraCaptureExtension: LockedCameraCaptureExtension")
    ref("keyboardPrincipal", "ChavrusaChatKeyboard/HanlinKeyboard.swift", "final class HanlinKeyboard: HanlinKeyboardInputViewController")
    ref("miniAppsKeyboardPrincipal", "HanlinMiniAppsExtensions/Keyboard/HanlinMiniAppsKeyboard.swift", "final class HanlinMiniAppsKeyboard: HanlinKeyboardInputViewController")
    ref("keyboardController", "Packages/HanlinAppExtensionsSDK/Sources/HanlinKeyboardUI/HanlinKeyboardInputViewController.swift", "open class HanlinKeyboardInputViewController: UIInputViewController")
    ref("keyboardTextEdit", "Packages/HanlinAppExtensionsSDK/Sources/HanlinKeyboardUI/HanlinKeyboardInputViewController.swift", "case .insertText: textDocumentProxy.insertText(edit.text!)")
    ref("keyboardLocalStorage", "Packages/HanlinAppExtensionsSDK/Sources/HanlinKeyboardUI/HanlinKeyboardInputViewController.swift", "self.model.storage = .extensionLocal(")
    ref("notificationContentPrincipal", "ChavrusaChatNotificationContent/NotificationViewController.swift", "final class NotificationViewController: HanlinNotificationContentViewController")
    ref("miniAppsNotificationContentPrincipal", "HanlinMiniAppsExtensions/NotificationContent/HanlinMiniAppsNotificationContent.swift", "final class HanlinMiniAppsNotificationContent: HanlinNotificationContentViewController")
    ref("notificationContentController", "Packages/HanlinAppExtensionsSDK/Sources/HanlinNotificationContentUI/HanlinNotificationContentViewController.swift", "open class HanlinNotificationContentViewController: UIViewController, UNNotificationContentExtension")
    ref("notificationContentAction", "Packages/HanlinAppExtensionsSDK/Sources/HanlinNotificationContentUI/HanlinNotificationContentViewController.swift", "extensionContext?.performNotificationDefaultAction()")
    ref("notificationPresentationPayload", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinNotificationPresentation.swift", "public struct HanlinNotificationPresentationPayload")
    ref("notificationPresentationContinuation", "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinNotificationPresentation.swift", "return try HanlinNotificationInvocation.enqueue(event, in: store, now: now)")
    extension_directories = {
        "ChavrusaChatShare": "ChavrusaChatShare",
        "ChavrusaChatTranslationProvider": "ChavrusaChatTranslationProvider",
        "HanlinScriptingWidgets": "HanlinScriptingWidgets",
        "ChavrusaChatNotificationService": "ChavrusaChatNotificationService",
        "HanlinMiniAppsNotificationService": "HanlinMiniAppsExtensions/Notification",
        "HanlinMiniAppsShare": "HanlinMiniAppsExtensions/Share",
        "HanlinMiniAppsTranslationProvider": "HanlinMiniAppsExtensions/Translation",
        "HanlinMiniAppsWidgets": "HanlinMiniAppsExtensions/Widgets",
        "ChavrusaChatKeyboard": "ChavrusaChatKeyboard",
        "HanlinMiniAppsKeyboard": "HanlinMiniAppsExtensions/Keyboard",
        "ChavrusaChatNotificationContent": "ChavrusaChatNotificationContent",
        "HanlinMiniAppsNotificationContent": "HanlinMiniAppsExtensions/NotificationContent",
        "ChavrusaChatCameraCapture": "ChavrusaChatCameraCapture",
        "HanlinMiniAppsCameraCapture": "HanlinMiniAppsExtensions/CameraCapture",
    }
    for target, directory in extension_directories.items():
        ref(target + "Info", directory + "/Info.plist", "<plist")

    tracked = sorted(p for p in sources.tracked if p.endswith(".swift"))
    sources.prefetch(tracked)
    swift = {p: sources.read_text(p) for p in tracked}
    share_references = [p for p in tracked if p.startswith("AI_HLY/") and "ChavrusaShareInbox" in swift[p]]
    if share_references != [
        "AI_HLY/Downstream/SDK/HanlinApplicationComponents.swift",
        "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift",
        "AI_HLY/Downstream/ScriptingPlatform/ScriptingPackageCenterViews.swift",
        "AI_HLY/Downstream/SystemIntegrations/ChavrusaShareActionTarget.swift",
        "AI_HLY/Downstream/SystemIntegrations/ChavrusaShareInbox.swift",
        "AI_HLY/Downstream/SystemIntegrations/ChavrusaShareInboxView.swift",
        "AI_HLY/Views/Components/ChatViewBottom.swift",
    ]:
        raise ValueError(f"Share inbox callers changed; re-audit reachability: {share_references}")
    optional_surfaces = {symbol: [p for p in tracked if re.search(rf"\b{symbol}\b", swift[p])]
                         for symbol in ["ControlWidget", "CSSearchableIndex", "CoreSpotlight", "IndexedEntity",
                                        "UIInputViewController", "UNNotificationContentExtension",
                                        "CameraCaptureIntent", "LockedCameraCaptureExtension", "LockedCameraCaptureUIScene"]}
    project = parse_project(sources.read_text("AI_HLY.xcodeproj/project.pbxproj"))
    objects = project["objects"]
    target_names = sorted(objects[key]["name"] for key in objects[project["rootObject"]]["targets"]
                          if objects[key].get("isa") == "PBXNativeTarget")
    entitlement_files = ["AI_HLY/AI_HLY.entitlements", "HanlinMiniAppsApp/HanlinMiniApps.entitlements"] + [
        f"{directory}/{target}.entitlements" for target, directory in extension_directories.items()]
    entitlements = {}
    for file in entitlement_files:
        data = sources.read_bytes(file)
        entitlements[file] = {"declared": plistlib.loads(data), "sha256": hashlib.sha256(data).hexdigest(),
                              "exportedSignatureVerified": False}
    paths = {
        "share": {"target": "ChavrusaChatShare / HanlinMiniAppsShare", "refs": ["sharePrincipal", "miniAppsSharePrincipal", "shareWrite", "shareOwnedStore", "shareProviderCopy", "shareRead", "shareReview", "shareSelection", "shareSDKFacade", "shareComposer", "extensionQueue", "extensionReceipts", "resume", "resumeDispatch", "headless", "nativeActionDispatch", "expoActionDispatch"],
                  "stop": "Owned share batches feed a Host chooser of installed NativeScript or Expo declared share actions, bound to installation/generation/entry/action. Resume dispatch uses the request broker; NativeScript invokes its registered action and Expo uses its foreground session action channel. An authored handler can call the canonical Host facade. Durable action receipts exist, but the original share ingress does not return a generic RuntimeExecutionResult automatically.", "owner": "INT-04"},
        "translation": {"target": "ChavrusaChatTranslationProvider / HanlinMiniAppsTranslationProvider", "refs": ["translationSnapshot", "translationContinuation", "translationAction", "extensionIntent", "extensionQueue", "resume", "resumeDispatch", "headless", "nativeActionDispatch", "expoActionDispatch", "nativeTranslation"],
                        "stop": "A declared NativeScript/Expo foreground action can carry selected text through an App Intent and the same Host action dispatch. Separately, native presentation programs render/edit/finish translation in the extension through original widget engines; that local presentation is not a canonical Host runtime passthrough. Neither route implies per-surface executed receipt coverage.", "owner": "INT-02/INT-03"},
        "widget": {"target": "HanlinScriptingWidgets / HanlinMiniAppsWidgets", "refs": ["widgetBundle", "miniAppsWidgetBundle", "widgetIntent", "widgetCallback", "originalExpoWidget", "originalExpoModule", "widgetHostDeclaration", "widgetHostCompiler", "widgetHostExecutor", "widgetHostIntent", "widgetHostWake", "expoWidgetHostButton", "scriptWidgetHostButton", "extensionQueue", "extensionReceipts", "resumeDispatch", "nativeActionDispatch", "expoActionDispatch"],
                   "stop": "Original renderer callbacks retain their local execution path. An explicit hostAction validates the current widget program and one same-package Expo/NativeScript appIntent action, queues a foreground invocation and wakes the existing Host after enqueue. The real handler may call all five canonical runtimes and retains its actual action value/error. A placed-widget OS tap and runtime result readback require separate executed evidence.", "owner": "INT-02/INT-03"},
        "notification": {"target": "ChavrusaChatNotificationService / HanlinMiniAppsNotificationService / both foreground Hosts",
                         "refs": ["notification", "miniAppsNotificationPrincipal", "notificationContentController", "notificationPresentationPayload", "notificationPresentationContinuation", "notificationContentAction", "notificationEvent", "notificationQueue", "notificationTarget", "notificationHostDelegate", "notificationForeground", "extensionQueue", "extensionReceipts", "extensionExecutor", "resumeDispatch", "nativeActionDispatch", "expoActionDispatch"],
                         "stop": "A versioned tagged event is durably queued in its product App Group. Mutable remote alerts use the shared service; both early application delegates handle actual local/remote foreground delivery and responses, and foreground recovery reads actual OS-delivered notifications. The live Host rechecks installation/generation and a declared Expo/NativeScript appIntent action, then persists its real result/error. No React Native/NativeScript or canonical Host runtime executes in the notification extensions. Rich content separately renders its prepared original program locally and can enqueue the same validated event before forwarding the system action. OS delivery, locked storage, and surface-to-runtime cases still require actual attempt evidence.", "owner": "INT-05"},
        "liveActivity": {"target": "HanlinScriptingWidgets / HanlinMiniAppsWidgets", "refs": ["widgetBundle", "miniAppsWidgetBundle", "scriptWidgetLiveActivity", "scriptWidgetActivityRenderer", "originalExpoActivity", "originalExpoModule", "widgetHostDeclaration", "widgetHostExecutor", "widgetHostIntent", "widgetHostWake", "scriptWidgetHostButton", "nativeNodeActivityIntent", "nativeNodeActivityAction", "extensionQueue", "extensionReceipts", "resumeDispatch", "nativeActionDispatch", "expoActionDispatch"],
                         "stop": "A ScriptWidget-rendered activity uses its declared widget hostAction with validated widget origin. A native-node ActivityKit activity uses its published appIntent action and a dedicated foreground LiveActivityIntent without fabricating widget origin. Both record the actual liveActivity source and wake the Host after enqueue; handlers may use all five canonical runtimes. Original Expo createLiveActivity callbacks remain their separate upstream path and do not implicitly consume hanlinWidget.hostAction metadata. Real OS surface execution remains a separate gate.", "owner": "INT-02/INT-03"},
        "hostAppIntent": {"target": "HanlinApp / HanlinMiniApps / HanlinScriptExtensions", "refs": ["extensionIntent", "extensionQueue", "extensionReceipts", "extensionExecutor", "resume", "resumeDispatch", "requestBroker", "headless", "nativeSession", "nativeActionDispatch", "expoActionDispatch"],
                          "stop": "Declared NativeScript and Expo actions dispatch through the installed-package broker and persist action value/status in a durable receipt. NativeScript admission preserves its one-VM ownership; Expo uses the visible foreground action channel. A handler may use its canonical Host facade, but the returned action value is not automatically the complete generic runtime receipt.", "owner": "INT-02/INT-03"},
        "shortcuts": {"target": "HanlinApp / HanlinMiniApps / HanlinWidgetUI", "refs": ["shortcutIntent", "hostShortcuts", "extensionIntent", "widgetHostWake", "extensionQueue", "extensionReceipts", "extensionExecutor", "resume", "resumeDispatch", "headless", "nativeActionDispatch", "expoActionDispatch"],
                      "stop": "Hanlin's typed installed-package action intent enqueues foreground continuation for NativeScript or Expo and wakes the existing Host after enqueue. ChavrusaChatShortcuts advertises alarm/notification phrases; the upstream ScriptWidget AppShortcutsProvider is not registered. Native snippets and original control intents are separate native UI/action surfaces.", "owner": "INT-02/INT-03"},
        "spotlight": {"target": "HanlinApp / HanlinMiniApps / CoreSpotlight", "refs": ["installedSystemCatalog", "installedEntityQuery", "spotlightIndex", "spotlightRemove", "spotlightOpen", "systemCatalogPublication", "systemEntrypointOpen", "systemEntrypointAdmission", "extensionQueue", "extensionReceipts", "resumeDispatch", "requestBroker", "headless", "nativeActionDispatch", "expoActionDispatch"],
                      "stop": "Each product indexes declared enabled installed-package Spotlight entries, independently of widget instances, and reconciles metadata and removal on publication. OpenIntent resolves the current installation/generation. An entry without an exported action opens its real prepared app; only a validated declared action queues a foreground continuation whose handler may call the five canonical Host runtimes. Spotlight search/tap and runtime receipt return to Spotlight are not established by source indexing.", "owner": "INT-02/INT-03"},
        "capture": {"target": "ChavrusaChatCameraCapture / HanlinMiniAppsCameraCapture / both foreground Hosts", "refs": ["capturePrincipal", "miniAppsCapturePrincipal", "cameraIntent", "cameraControl", "cameraPhoto", "cameraHardwareEvent", "cameraHandoff", "cameraAppContext", "cameraSystemReceive", "cameraDurableCopy", "cameraPackageCopy", "cameraActionContinuation", "installedSystemCatalog", "systemEntrypointOpen", "systemEntrypointAdmission", "extensionQueue", "extensionReceipts", "resumeDispatch", "requestBroker", "headless", "nativeActionDispatch", "expoActionDispatch"],
                    "stop": "CameraCaptureIntent and its Control use the real locked-capture extension or foreground camera. AVFoundation writes JPEGs under sessionContentURL; openApplication hands off through the system. The app verifies and retains its own copy before system-session invalidation, copies photos into the selected package Documents area, then invokes the required declared action with installation/generation checks and a stable queue identity. The locked process has no App Group, network or package runtime. Canonical Host runtime calls happen only after foreground handoff; physical capture and complete receipt return to the ingress remain separate acceptance.", "owner": "INT-02/INT-03"},
        "assistantTool": {"target": "HanlinApp assistant tool catalog / installed Expo or NativeScript foreground runtime",
                          "refs": ["assistantDeclaration", "assistantProjection", "assistantAuthoring", "assistantPublicTypes", "assistantAdapter", "assistantCanonicalSources", "assistantCatalog", "assistantCatalogUnavailable", "assistantProviderDispatch", "assistantActualResult", "assistantForegroundDispatch", "assistantBrokerDispatch", "resumeDispatch", "requestBroker", "headless", "nativeActionDispatch", "expoActionDispatch"],
                          "stop": "A request-scoped canonical tool catalog includes explicit assistantTool entries from enabled installed prepared Expo/NativeScript apps. If prepared-package discovery or projection is unavailable, only that contribution is omitted with an explicit trace; the existing native, MCP and legacy catalogs remain intact. Each entry selects exactly one real foreground action and its canonical input/output schemas. The prepared route rechecks installation, generation and source/artifact identity before directly awaiting the existing native request broker and original registered handler. The assistant receives the real action value or error; this route does not enqueue a durable invocation and cannot substitute a legacy scripting handler. An authored handler may call the five canonical Host runtimes through its existing facade; provider selection, complete runtime receipt forwarding and native E2E are separate acceptance.", "owner": "SDK-03/SDK-04/INT-03"},
        "foreground": {"target": "HanlinApp / HanlinMiniApps", "refs": ["appBootstrap", "miniAppsBootstrap", "nativeBridge", "nativeAdapter", "nativeRuntimeDispatch", "nativeSession", "expoFacade", "expoModule", "expoAdapter", "expoRuntimeDispatch", "runtimeWire", "runtimeBroker", "callerContext"],
                       "stop": "NativeScript generic async and Expo facades reach the shared canonical JSON/full RuntimeExecutionResult route. NativeScript captures its bound bridge and session-owned cancellation; legacy strings retain their historical boundary. This generator records source wiring and imports no native or physical acceptance verdict.", "owner": "INT-03/INT-06/SDK-03/SDK-04"},
    }
    original_surfaces = {
        "scriptWidgetControls": {"engines": ["scriptwidget"],
            "refs": ["originalControlWidgets", "originalToggleWidget", "originalControlProvider", "originalControlActions", "controlCatalog", "controlCompiler", "widgetCallback", "hostControlButtonRegistration", "hostControlToggleRegistration", "miniAppsControlButtonRegistration", "miniAppsControlToggleRegistration", "controlUpstream", "controlSourceRefresh"],
            "sourceSupport": "Original button/toggle ControlWidget wrappers, configuration intents, entity/value providers and actions are registered in both widget bundles. Original widget.json actions/controls are projected into current installation/generation state and the widget action executor. Original source provenance and automatic refresh are retained."},
        "widgets": {"engines": ["expo-widgets", "scriptwidget"],
            "refs": ["widgetBundle", "miniAppsWidgetBundle", "widgetCallback", "originalExpoWidget", "originalExpoModule", "originalExpoRegistry"],
            "sourceSupport": "Original engine widget rendering and actions exist, including the original Expo Widgets module, registration picker, timeline and configuration integration. This is separate from a canonical Host-runtime bridge."},
        "nativePresentations": {"engines": ["expo-widgets", "scriptwidget"],
            "refs": ["nativePresentationExecutor", "nativePresentationView", "nativeSnippet", "nativeTranslation"],
            "sourceSupport": "Declared native snippet/translation programs execute through original widget engines with invocation-owned state and actual native controls. Translation expansion/text replacement uses the native provider context; it is not a React Native or NativeScript VM inside the extension."},
        "liveActivities": {"engines": ["expo-widgets", "scriptwidget"],
            "refs": ["scriptWidgetLiveActivity", "scriptWidgetActivityRenderer", "originalExpoActivity", "originalExpoModule", "widgetBundle", "miniAppsWidgetBundle"],
            "sourceSupport": "Original Expo ActivityKit and original ScriptWidget component/region rendering have native lifecycle integration. Local controls refresh declared activity state with current installation/generation checks."},
    }
    local_presentations = {
        "keyboard": {"engines": ["expo-widgets", "scriptwidget"],
            "target": "ChavrusaChatKeyboard / HanlinMiniAppsKeyboard",
            "refs": ["keyboardPrincipal", "miniAppsKeyboardPrincipal", "keyboardController", "keyboardTextEdit", "keyboardLocalStorage", "nativePresentationExecutor", "nativePresentationView", "nativePresentationPublication"],
            "sourceSupport": "A real UIInputViewController chooses a published installed-package keyboard presentation. The original prepared renderer receives document context; validated effects call textDocumentProxy insertion/deletion/cursor movement or the system next-keyboard API. Renderer/service mutable storage stays extension-local. This keyboard is not a React Native/NativeScript app VM or a canonical Host-runtime ingress.",
            "canonicalHostContinuationPath": None},
        "richNotification": {"engines": ["expo-widgets", "scriptwidget"],
            "target": "ChavrusaChatNotificationContent / HanlinMiniAppsNotificationContent",
            "refs": ["notificationContentPrincipal", "miniAppsNotificationContentPrincipal", "notificationContentController", "notificationPresentationPayload", "notificationPresentationContinuation", "notificationContentAction", "notificationQueue", "nativePresentationExecutor", "nativePresentationView"],
            "sourceSupport": "A real UNNotificationContentExtension validates the published presentation identity/category and renders its original prepared program with extension-local mutable state. Matching installation/package/generation ties optional continuation to the existing notification event; the exact event is persisted before the system default action/response forwards to the foreground Host. A queued receipt is not execution completion. Ordinary notifications retain system content without a fabricated MiniApp.",
            "canonicalHostContinuationPath": "notification"},
    }
    for route in [*original_surfaces.values(), *local_presentations.values()]:
        route.update({"status": "source-wired", "canonicalHostRuntimePassthroughEstablished": False,
                      "realSurfaceE2E": False, "onDeviceProof": None})
    rows = []
    for surface, route in paths.items():
        for engine in ENGINES:
            for runtime in RUNTIMES:
                wired = surface in ["foreground", "share", "translation", "widget", "notification", "liveActivity", "hostAppIntent", "shortcuts", "spotlight", "capture", "assistantTool"]
                structured_receipt = wired and surface == "foreground"
                rows.append({"surface": surface, "engine": engine, "runtime": runtime,
                    "status": "not-tested" if structured_receipt else "partially-wired" if wired else "disconnected", "path": surface,
                    "runtimeTail": (["expoFacade", "expoModule", "expoAdapter", "runtimeWire", "runtimeBroker"] if engine == "hanlinExpo"
                                    else ["nativeFacade", "nativeBridge", "nativeAdapter", "runtimeWire", "runtimeBroker"]) if wired else [],
                    "sourcePathReachesCanonicalExecutor": wired,
                    "structuredReceiptReturnedToIngressInSource": structured_receipt,
                    "durableActionReceiptInSource": wired and surface not in ["foreground", "assistantTool"],
                    "receiptCondition": "Only the optional declared action uses the queue; plain Spotlight app-open has no action receipt" if surface == "spotlight" else
                                         "Direct awaited native action response; no durable invocation is enqueued" if surface == "assistantTool" else None,
                    "routeCondition": "An explicit hostAction validates the current installed widget and registered target, then continues in the foreground Host" if surface == "widget" else
                                      "Declared ScriptWidget hostAction or published native-node action continues in the foreground Host; original Expo callbacks stay separate" if surface == "liveActivity" else
                                      "Typed notification event resumes only a current installed action in the foreground Host" if surface == "notification" else
                                      "Declared Spotlight action only; an entry without a symbol opens its prepared app without a runtime invocation" if surface == "spotlight" else
                                      "Verified captured files hand off to the selected current foreground package action; no Host runtime in the locked process" if surface == "capture" else
                                      "Explicit installed prepared action in the AI host catalog; its real foreground handler may call the canonical Host facade" if surface == "assistantTool" else
                                      "Foreground package action continuation; original native presentations remain separate" if surface == "translation" else
                                      "Declared registered package handler can call its canonical Host facade" if wired and surface != "foreground" else
                                      "Direct canonical Host facade call" if wired else "No canonical Host runtime route established",
                    "realSurfaceE2E": False, "onDeviceProof": None,
                    "resultBoundary": "Typed RuntimeExecutionResult in generic foreground facade; per-surface E2E missing" if structured_receipt else
                                      "Actual awaited action JSON value/error returned to the assistant; a full RuntimeExecutionResult is returned only if the authored handler forwards it; no executed E2E proof" if surface == "assistantTool" else
                                      "Durable action receipt; runtime receipt readback to ingress incomplete" if wired else "No connected canonical-runtime receipt",
                    "callerContext": {"hostAdapterReachable": wired, "canPresentUI": True if wired and (engine == "hanlinExpo" or surface in ["foreground", "spotlight", "capture", "assistantTool"]) else None,
                        "userGesturePresent": False if wired else None,
                        "note": "The validated system entrypoint opens its actual prepared foreground controller before action dispatch" if surface in ["spotlight", "capture"] else
                                "The active AI host validates the current prepared action and starts or reuses its actual foreground runtime before directly awaiting the handler" if surface == "assistantTool" else
                                 "NativeScript uses the existing foreground context when available; a new headless provider sets canPresentUI=false. Foreground continuation depends on the declared app handler." if wired and surface != "foreground" and engine == "hanlinNativeScript" else
                                "Host-bound package/session identity" if wired else "No canonical Host call context is connected from this ingress"},
                    "engineVersionSource": "source-inventory.json#/" + ("expo" if engine == "hanlinExpo" else "nativeScript"),
                    "permissions": (["Locked capture uses system session storage and no App Group/network access", "Camera authorization and supported physical hardware required", "Extension declaration is not signed/device acceptance"] if surface == "capture" else
                                    ["App-owned Spotlight index declaration is not system search/tap acceptance"] if surface == "spotlight" else
                                    ["Existing canonical tool and package action capability validation applies", "Actual service OS permission/availability still required"] if surface == "assistantTool" else
                                    ["Declared App Group is not exported-signature proof", "Actual service OS permission/availability still required"]),
                    "followUp": route["owner"]})
    if len(rows) != 110 or len({(r['surface'], r['engine'], r['runtime']) for r in rows}) != 110:
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
        "optionalSurfaceSymbolScanBoundary": "Symbol discovery only; the exact sourceRefs and explicit routes establish wiring, never runtime execution.",
        "sourceRefs": refs, "paths": paths, "matrix": rows, "originalLibrarySurfaces": original_surfaces,
        "localPresentationSurfaces": local_presentations,
        "matrixScope": "Eleven ingress categories by two native app engines by five canonical Host runtimes (110 conditional source routes); original library rendering and keyboard/rich-notification presentation records are separate. Plain Spotlight app-open does not itself execute a runtime. Assistant tools directly await their prepared action result, without a durable queue receipt.",
        "sourceReadPolicy": "Current local bytes take precedence; only missing tracked files use exact HEAD blobs, including the Swift symbol scan.",
        "systemServices": {"authority": "source-inventory.json#/systemServices",
            "publicBindingStatus": {e: "No generic HanlinSystemServicesBroker facade in the inspected Host adapter. Original native SDK APIs and ScriptWidget service providers are separate API paths; this does not classify them as absent." for e in ENGINES},
            "availabilityIsNotGrantMetadata": True, "devicePermissionChecksExecuted": False},
        "acceptance": {"fourExtensionCategoriesByTwoEnginesByFiveRuntimes": 40, "additionalSurfaceCells": 70, "canonicalHostRuntimeCells": 110,
            "executedSurfaceE2EPasses": 0, "signedPhysicalAcceptance": "NOT_RUN"}}


def markdown(value: dict) -> str:
    lines = ["# NativeScript / Expo extension reachability", "", "Status: **IN_PROGRESS — source audit only**.", "",
        f"Base commit: `{value['sourceCommit']}`. Exact current file hashes and line anchors are in [the JSON matrix](extension-reachability.json).",
        "Runtime/API/version authority is [source-inventory.json](source-inventory.json); this matrix consumes it rather than maintaining a second SDK contract.", "",
        "The share, translation, widget and notification ingress categories × two native app engines × five canonical Host runtimes form 40 cells. Live Activity, Host AppIntent, Shortcuts, Spotlight, camera capture, prepared assistant tools and foreground add 70 more. These 110 cells describe conditional Host-runtime passthrough, not all original widget, control or presentation capabilities. Spotlight without a declared action only opens its prepared app; camera capture reaches a Host handler after the system handoff. Prepared assistant tools expose actual installed actions through the AI host catalog and directly await the original native handler response.",
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
    lines += ["", "## Original library surfaces outside the 110 cells", ""]
    for surface, route in value["originalLibrarySurfaces"].items():
        links = []
        for key in route["refs"]:
            ref = value["sourceRefs"][key]
            links.append(f"[{key}](../../{ref['file']}#L{ref['line']})")
        lines += [f"- **{surface}** ({', '.join(route['engines'])}): {route['sourceSupport']} Source support only; no canonical Host-runtime passthrough or executed E2E pass is inferred. Sources: " + ", ".join(links) + "."]
    lines += ["", "## Local keyboard and rich-notification presentations", ""]
    for surface, route in value["localPresentationSurfaces"].items():
        links = []
        for key in route["refs"]:
            ref = value["sourceRefs"][key]
            links.append(f"[{key}](../../{ref['file']}#L{ref['line']})")
        continuation = (f" Foreground continuation uses the existing **{route['canonicalHostContinuationPath']}** matrix route."
                        if route["canonicalHostContinuationPath"] else " No canonical Host-runtime route is inferred for this local presentation.")
        lines += [f"- **{surface}** ({route['target']}): {route['sourceSupport']}{continuation} Source support only; system UI, signed entitlement/profile and physical acceptance remain separate. Sources: " + ", ".join(links) + "."]
    lines += ["", "## Identity, permissions and proof", "",
        "- App Group/other entitlements in JSON are source declarations. Exported signed entitlement/profile identity is NOT_VERIFIED here.",
        "- TestFlight93401 is the historical owner delivery at7fa8fe26. It does not prove this branch, current framework identity, or this matrix. No IPA is generated by this audit.",
        "- NS legacy callbacks keep string/error semantics. The generic facade exposes all five canonical kinds/full receipts and session-owned cancellation in source. One process-wide native VM keeps its existing admission/ownership rules. This audit does not load execution evidence.",
        "- Expo's facade routes all five canonical kinds through the shared runtime.execute wire. Declared Expo actions use their actual foreground action channel and can call that facade; they are no longer rejected as a group. Per-ingress returned runtime receipts still need separate acceptance evidence.",
        "- SystemServicesBroker declarations are inventoried separately from original NativeScript/Expo APIs and installed ScriptWidget native providers. This matrix does not equate a missing generic broker facade with missing original service APIs, or declarations with OS authorization/device execution.",
        "- Original ScriptWidget button/toggle Control Widgets are implemented in both existing Widget extensions and recorded above. They are not Node/Shell passthrough rows. The separate installed-package Spotlight catalog, IndexedEntity/OpenIntent and actual index/update/removal calls are source-anchored above; optional symbol occurrences alone do not prove a route.",
        "- ResumeQueue delivery metadata, leases, deduplication, cancellation and durable receipts are source-backed paths. Their historical and current executed evidence belongs to the corresponding acceptance run, not this generator. No automatic canonical Host engine launch inside an extension is inferred.",
        "- The two locked-camera ExtensionKit wrappers, real AVFoundation capture and app handoff are source-anchored. The locked process uses no App Group/network access; package actions execute in the foreground Host after verified file transfer. Camera permission, hardware, system launch and signed/device acceptance are not inferred from those declarations.",
        "- Prepared assistant tools use the existing canonical AI tool catalog, then the installed-package request broker and original Expo/NativeScript registered action. Input parameters follow the canonical object contract; output schemas can describe any JSON value. Their actual action response is awaited directly, not a queued receipt or an inferred provider-selected/runtime/device PASS.",
        "- Legacy Scripting/ScriptUI development remains frozen. No custom home entrypoint or upstream ScriptWidget AppShortcutsProvider registration is added. Keyboard/rich-notification UI uses separate prepared original presentations, not an extension-hosted React Native/NativeScript VM.", "",
        "## Verification", "", "Run the SDK source audit first, then `py -3 Scripts/Audit/audit_miniapp_reachability.py --check`. Both fail on source drift; runtime execution is not part of this audit.",
        "Task completion and native acceptance are tracked separately. This generated map reports current source routes and does not set task status or establish final acceptance.", ""]
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
        print("PASS: 110 unique source-backed reachability cells; no E2E pass inferred.")
    else:
        output.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        (OUT / "extension-reachability.md").write_text(markdown(value), encoding="utf-8", newline="\n")
        print("Wrote 110 canonical Host-runtime reachability cells plus separate original-library and local-presentation records; no physical/E2E pass inferred.")


if __name__ == "__main__":
    main()
