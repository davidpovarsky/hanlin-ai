import Foundation
import ExpoBrownfield
import ExpoModulesCore
import ExpoUI
import HanlinExpoNativeAPI
import HanlinExpoNativeAPICore
import HanlinPlatformContracts
import ObjectiveC
import React
@_implementationOnly import React_RCTAppDelegate
import UIKit

@_silgen_name("jsrt_create_hermes_factory")
private func hanlin_create_hermes_factory() -> JSRuntimeFactoryRef

private func hostDidInitRuntimeCallback(selfObj: AnyObject, _cmd: Selector, host: AnyObject, runtime: UnsafeMutableRawPointer) {
    NSLog("%@", "HANLIN_EXPO_HOST_DID_INITIALIZE_RUNTIME runtime=\(runtime)")
    if let delegate = selfObj as? HanlinExpoReactNativeFactoryDelegate {
        delegate.handleHostDidInitializeRuntime(runtime)
    }
}

private final class HanlinExpoReactNativeFactoryDelegate: RCTDefaultReactNativeFactoryDelegate, @unchecked Sendable {
    private let targetBundleURL: URL
    nonisolated(unsafe) private let appContext: AppContext
    private let sessionID: String
    private static var didRegisterRuntimeCallback = false

    private static func registerRuntimeCallbackIfNeeded() {
        guard !didRegisterRuntimeCallback else { return }
        didRegisterRuntimeCallback = true
        let sel = NSSelectorFromString("host:didInitializeRuntime:")
        let fn: @convention(c) (AnyObject, Selector, AnyObject, UnsafeMutableRawPointer) -> Void = hostDidInitRuntimeCallback
        let imp = unsafeBitCast(fn, to: IMP.self)
        let types = "v@:@^v"
        if !class_addMethod(HanlinExpoReactNativeFactoryDelegate.self, sel, imp, types) {
            if let method = class_getInstanceMethod(HanlinExpoReactNativeFactoryDelegate.self, sel) {
                method_setImplementation(method, imp)
            }
        }
    }

    init(bundleURL: URL, appContext: AppContext, sessionID: String) {
        self.targetBundleURL = bundleURL
        self.appContext = appContext
        self.sessionID = sessionID
        super.init()
        if let provider = HanlinExpoNativeAPIManager.dependencyProvider() as? (any RCTDependencyProvider) {
            self.dependencyProvider = provider
        }
        Self.registerRuntimeCallbackIfNeeded()
    }

    nonisolated override func bundleURL() -> URL? {
        return targetBundleURL
    }

    nonisolated override func sourceURL(for bridge: RCTBridge) -> URL? {
        return targetBundleURL
    }

    nonisolated override func createJSRuntimeFactory() -> JSRuntimeFactoryRef {
        return hanlin_create_hermes_factory()
    }

    nonisolated fileprivate func handleHostDidInitializeRuntime(_ runtime: UnsafeMutableRawPointer) {
        NSLog("%@", "HANLIN_EXPO_HOST_DID_INITIALIZE_RUNTIME runtime=\(runtime)")
        guard HanlinExpoInstallScheduledRuntime(runtime, appContext) else {
            NSLog("%@", "HANLIN_EXPO_BOOTSTRAP_FAILED: React runtime scheduler is missing")
            return
        }
        NSLog("%@", "HANLIN_EXPO_SET_RUNTIME_DONE")
        let moduleNames = appContext.getModuleNames()
        NSLog("%@", "HANLIN_EXPO_REGISTERED_MODULES=\(moduleNames.joined(separator: ", "))")
        HanlinExpoNativeAPIManager.bindRuntime(runtime, forSessionID: self.sessionID)
    }
}

@objc(ExpoModulesProvider)
public final class HanlinExpoModulesProvider: ModulesProvider {
    public override func getModuleClasses() -> [ExpoModuleTupleType] {
        return [
            (module: ExpoUIModule.self, name: "ExpoUI"),
            (module: HanlinExpoUIModule.self, name: "HanlinExpoUI"),
            (module: HanlinGeneratedExpoUIModule.self, name: "HanlinGeneratedExpoUI"),
            (module: ExpoBrownfieldModule.self, name: "ExpoBrownfieldModule"),
            (module: ExpoBrownfieldStateModule.self, name: "ExpoBrownfieldStateModule"),
            (module: HanlinHostServicesModule.self, name: "HanlinHostServices")
        ]
    }
}

@MainActor
public final class HanlinExpoSession {
    private static let supportedSDKVersion = "58.0.3"
    private static let supportedUIVersion = "58.0.3"
    private static var activeSessions: [String: HanlinExpoSession] = [:]

    public let sessionID: String
    public let applicationRoot: URL
    public let containerController: UIViewController
    public let bundleURL: URL
    public let packageID: String
    public let isNativeAPIGranted: Bool

    private var reactNativeFactory: RCTReactNativeFactory?
    private var factoryDelegate: HanlinExpoReactNativeFactoryDelegate?
    private var appContext: AppContext?
    private var hostedView: UIView?
    private(set) public var isActive = false

    private static var didLoadAppDefines = false

    @MainActor
    public static func ensureAppDefinesLoaded() {
        guard !didLoadAppDefines else { return }
        let defines: NSDictionary = [
            "APP_DEBUG": false,
            "APP_RCT_DEBUG": false,
            "APP_RCT_DEV": false,
            "APP_NEW_ARCH_ENABLED": true
        ]
        let sel = NSSelectorFromString("load:")
        if let cls = NSClassFromString("EXAppDefines") {
            if let metaCls = object_getClass(cls), class_respondsToSelector(metaCls, sel) {
                typealias LoadFn = @convention(c) (AnyClass, Selector, NSDictionary) -> Void
                let imp = class_getMethodImplementation(metaCls, sel)
                let fn = unsafeBitCast(imp, to: LoadFn.self)
                fn(cls, sel, defines)
            } else {
                _ = (cls as AnyObject).perform(sel, with: defines)
            }
        }
        didLoadAppDefines = true
        NSLog("%@", "HANLIN_EXPO_APP_DEFINES_LOADED")
    }

    public init(
        applicationRoot: URL,
        sessionID: String = UUID().uuidString.lowercased(),
        packageID: String = "unknown",
        isNativeAPIGranted: Bool = false
    ) throws {
        Self.ensureAppDefinesLoaded()
        let root = applicationRoot.standardizedFileURL
        guard root.isFileURL else {
            throw HanlinExpoError.invalidApplicationRoot("the URL is not a file URL")
        }
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw HanlinExpoError.invalidApplicationRoot("the root is not a real directory")
        }

        let packageJSONURL = root.appending(path: "package.json", directoryHint: .notDirectory)
        guard let metadata = try? packageJSONURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              metadata.isRegularFile == true, metadata.isSymbolicLink != true else {
            throw HanlinExpoError.missingPreparedFile("package.json")
        }

        let packageData = try Data(contentsOf: packageJSONURL)
        guard let packageJSON = try JSONSerialization.jsonObject(with: packageData) as? [String: Any] else {
            throw HanlinExpoError.invalidApplicationRoot("package.json is not a valid JSON object")
        }

        guard packageJSON["hanlinRuntime"] as? String == "hanlin-expo" else {
            throw HanlinExpoError.unsupportedRuntimeVersion("package.json does not declare hanlinRuntime: hanlin-expo")
        }

        if let supplied = packageJSON["hanlinExpo"] {
            guard let contract = supplied as? [String: Any],
                  let runtimeVersion = contract["runtimeVersion"] as? String,
                  contract["plugins"] is [String: Any],
                  HanlinPreparedRuntimeVersion.supportsMinimum(runtimeVersion, installed: HanlinExpoBridgeMetadata.runtimeVersion) else {
                throw HanlinExpoError.unsupportedRuntimeVersion("hanlinExpo must declare a supported runtimeVersion and plugins object.")
            }
            if let bridge = contract["bridgeVersion"] {
                guard let version = bridge as? String, HanlinExpoBridgeMetadata.supports(requiredBridgeVersion: version) else {
                    throw HanlinExpoError.unsupportedRuntimeVersion("hanlinExpo bridgeVersion is malformed or newer than the installed bridge.")
                }
            }
        }

        let entryFileName: String
        if let main = packageJSON["main"] {
            guard let name = main as? String else {
                throw HanlinExpoError.invalidApplicationRoot("package.json main must be a relative file path string")
            }
            entryFileName = name
        } else { entryFileName = "bundle.js" }
        let components = entryFileName.split(separator: "/", omittingEmptySubsequences: false)
        guard !entryFileName.isEmpty, !entryFileName.contains("\\"), !entryFileName.contains(":"), !entryFileName.contains("\0"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw HanlinExpoError.invalidApplicationRoot("package.json main must stay within the prepared package")
        }
        var resolvedBundleURL = root
        for (index, component) in components.enumerated() {
            resolvedBundleURL.append(path: String(component))
            guard let values = try? resolvedBundleURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true,
                  index == components.count - 1 ? values.isRegularFile == true : values.isDirectory == true else {
                throw HanlinExpoError.missingPreparedFile(entryFileName)
            }
        }

        self.sessionID = sessionID
        self.applicationRoot = root
        self.bundleURL = resolvedBundleURL
        self.packageID = packageID
        self.isNativeAPIGranted = isNativeAPIGranted
        self.containerController = UIViewController()
        self.containerController.view.backgroundColor = .systemBackground
    }

    public func start(moduleName: String = "main") throws {
        guard !isActive else { return }

        do {
            Self.ensureAppDefinesLoaded()
            HanlinExpoModifierRegistry.registerCustomModifiers()

            // Bind native authorization context before React / Hermes evaluation
            HanlinExpoNativeAPIManager.registerSession(
                sessionID: sessionID,
                packageID: packageID,
                isGranted: isNativeAPIGranted
            )

            let modulesProvider = HanlinExpoModulesProvider()
            let appContext = AppContext()
            NSLog("%@", "HANLIN_EXPO_APPCONTEXT_CREATED")
            guard HanlinExpoHostServicesBridge.bind(sessionID: sessionID, toAppContext: appContext) else {
                throw HanlinExpoError.bootstrapFailed("No Host Services provider is registered for this Expo session.")
            }
            NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_BOUND")
            appContext.registerNativeModules(provider: modulesProvider)
            NSLog("%@", "HANLIN_EXPO_MODULES_REGISTERED")
            self.appContext = appContext

            let bundle = bundleURL
            let delegate = HanlinExpoReactNativeFactoryDelegate(
                bundleURL: bundle,
                appContext: appContext,
                sessionID: sessionID
            )
            self.factoryDelegate = delegate

            let factory = RCTReactNativeFactory(delegate: delegate)
            NSLog("%@", "HANLIN_EXPO_REACT_FACTORY_CREATED")
            self.reactNativeFactory = factory

            let rootView = factory.rootViewFactory.view(
                withModuleName: moduleName,
                initialProperties: nil,
                launchOptions: nil
            )
            NSLog("%@", "HANLIN_EXPO_ROOTVIEW_CREATED")

            rootView.translatesAutoresizingMaskIntoConstraints = false
            containerController.view.addSubview(rootView)
            NSLayoutConstraint.activate([
                rootView.topAnchor.constraint(equalTo: containerController.view.topAnchor),
                rootView.leadingAnchor.constraint(equalTo: containerController.view.leadingAnchor),
                rootView.trailingAnchor.constraint(equalTo: containerController.view.trailingAnchor),
                rootView.bottomAnchor.constraint(equalTo: containerController.view.bottomAnchor)
            ])

            self.hostedView = rootView
            Self.activeSessions[sessionID] = self
            isActive = true

            NSLog("%@", "HANLIN_EXPO_INITIALIZED_EXTERNAL_ROOT path=\(applicationRoot.path(percentEncoded: false)) bundle=\(bundleURL.lastPathComponent)")
        } catch {
            shutdown()
            throw HanlinExpoError.bootstrapFailed(error.localizedDescription)
        }
    }

    public func shutdown() {
        NSLog("%@", "HANLIN_EXPO_SHUTDOWN_BEGIN")
        HanlinExpoNativeAPIManager.revokeSession(sessionID: sessionID)

        guard isActive || reactNativeFactory != nil || appContext != nil else {
            HanlinExpoModifierRegistry.unregisterCustomModifiers()
            return
        }

        hostedView?.removeFromSuperview()
        hostedView = nil

        if let factory = reactNativeFactory {
            factory.rootViewFactory.reactHost = nil
        }
        reactNativeFactory = nil
        factoryDelegate = nil
        if let appContext {
            HanlinExpoHostServicesBridge.unbind(appContext: appContext)
            NSLog("%@", "HANLIN_EXPO_UNBOUND")
            // Expo's native state owns destroy() and executes it on the JS
            // thread when React tears down the runtime. Calling it here on
            // MainActor races queued JSI callbacks and releases live JS values.
        }
        appContext = nil
        isActive = false

        HanlinExpoModifierRegistry.unregisterCustomModifiers()

        Self.activeSessions.removeValue(forKey: sessionID)
    }

    deinit {
        MainActor.assumeIsolated {
            shutdown()
        }
    }
}
