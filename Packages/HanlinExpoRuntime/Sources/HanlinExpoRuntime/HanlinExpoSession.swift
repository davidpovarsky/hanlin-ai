import Foundation
import ExpoBrownfield
import ExpoModulesCore
import ExpoUI
import ObjectiveC
import React
import React_RCTAppDelegate
import UIKit

@_silgen_name("jsrt_create_hermes_factory")
private func hanlin_create_hermes_factory() -> JSRuntimeFactoryRef

private final class HanlinExpoReactNativeFactoryDelegate: RCTDefaultReactNativeFactoryDelegate, @unchecked Sendable {
    private let targetBundleURL: URL
    private let appContext: AppContext

    init(bundleURL: URL, appContext: AppContext) {
        self.targetBundleURL = bundleURL
        self.appContext = appContext
        super.init()
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

    @objc(host:didInitializeRuntime:)
    nonisolated func host(_ host: AnyObject, didInitializeRuntime runtime: UnsafeMutableRawPointer) {
        NSLog("%@", "HANLIN_EXPO_HOST_DID_INITIALIZE_RUNTIME runtime=\(runtime)")
        appContext.setRuntime(runtime, scheduler: nil, dispatch: nil)
        NSLog("%@", "HANLIN_EXPO_SET_RUNTIME_DONE")
        let moduleNames = appContext.getModuleNames()
        NSLog("%@", "HANLIN_EXPO_REGISTERED_MODULES=\(moduleNames.joined(separator: ", "))")
    }
}

@objc(ExpoModulesProvider)
public final class HanlinExpoModulesProvider: ModulesProvider {
    public override func getModuleClasses() -> [ExpoModuleTupleType] {
        return [
            (module: ExpoUIModule.self, name: "ExpoUI"),
            (module: HanlinExpoUIModule.self, name: "HanlinExpoUI"),
            (module: HanlinGeneratedExpoUIModule.self, name: "HanlinGeneratedExpoUI"),
            (module: HanlinExpoHostServicesModule.self, name: "HanlinHostServices"),
            (module: ExpoBrownfieldModule.self, name: "ExpoBrownfieldModule"),
            (module: ExpoBrownfieldStateModule.self, name: "ExpoBrownfieldStateModule")
        ]
    }
}

@MainActor
public final class HanlinExpoSession {
    private static weak var activeSession: HanlinExpoSession?

    public let applicationRoot: URL
    public let containerController: UIViewController
    public let bundleURL: URL

    private var reactNativeFactory: RCTReactNativeFactory?
    private var factoryDelegate: HanlinExpoReactNativeFactoryDelegate?
    private var appContext: AppContext?
    private var hostedView: UIView?
    private let hostServicesBinding: HanlinExpoHostServicesBinding?
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
        hostServicesBinding: HanlinExpoHostServicesBinding? = nil
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
        guard FileManager.default.fileExists(atPath: packageJSONURL.path(percentEncoded: false)) else {
            throw HanlinExpoError.missingPreparedFile("package.json")
        }

        let packageData = try Data(contentsOf: packageJSONURL)
        guard let packageJSON = try JSONSerialization.jsonObject(with: packageData) as? [String: Any] else {
            throw HanlinExpoError.invalidApplicationRoot("package.json is not a valid JSON object")
        }

        guard packageJSON["hanlinRuntime"] as? String == "hanlin-expo" else {
            throw HanlinExpoError.unsupportedRuntimeVersion("package.json does not declare hanlinRuntime: hanlin-expo")
        }

        if let contract = packageJSON["hanlinExpo"] as? [String: Any],
           let requiredBridgeVersion = contract["bridgeVersion"] as? String,
           !HanlinExpoBridgeMetadata.supports(requiredBridgeVersion: requiredBridgeVersion) {
            throw HanlinExpoError.unsupportedRuntimeVersion(
                "This package requires Hanlin Expo UI bridge \(requiredBridgeVersion), but the host provides \(HanlinExpoBridgeMetadata.bridgeVersion)."
            )
        }

        let entryFileName = (packageJSON["main"] as? String) ?? "bundle.js"
        let resolvedBundleURL = root.appending(path: entryFileName, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: resolvedBundleURL.path(percentEncoded: false)) else {
            throw HanlinExpoError.missingPreparedFile(entryFileName)
        }

        self.applicationRoot = root
        self.bundleURL = resolvedBundleURL
        self.hostServicesBinding = hostServicesBinding
        self.containerController = UIViewController()
        self.containerController.view.backgroundColor = .systemBackground
    }

    public func start(moduleName: String = "main") throws {
        guard !isActive else { return }
        guard Self.activeSession == nil else {
            throw HanlinExpoError.sessionAlreadyActive
        }

        do {
            Self.ensureAppDefinesLoaded()
            HanlinExpoModifierRegistry.registerCustomModifiers()
            if let hostServicesBinding {
                HanlinExpoHostServicesRuntime.install(hostServicesBinding)
            }

            let modulesProvider = HanlinExpoModulesProvider()
            let appContext = AppContext()
            appContext.registerNativeModules(provider: modulesProvider)
            self.appContext = appContext

            let bundle = bundleURL
            let delegate = HanlinExpoReactNativeFactoryDelegate(bundleURL: bundle, appContext: appContext)
            self.factoryDelegate = delegate

            let factory = RCTReactNativeFactory(delegate: delegate)
            self.reactNativeFactory = factory

            let rootView = factory.rootViewFactory.view(
                withModuleName: moduleName,
                initialProperties: nil,
                launchOptions: nil
            )

            rootView.translatesAutoresizingMaskIntoConstraints = false
            containerController.view.addSubview(rootView)
            NSLayoutConstraint.activate([
                rootView.topAnchor.constraint(equalTo: containerController.view.topAnchor),
                rootView.leadingAnchor.constraint(equalTo: containerController.view.leadingAnchor),
                rootView.trailingAnchor.constraint(equalTo: containerController.view.trailingAnchor),
                rootView.bottomAnchor.constraint(equalTo: containerController.view.bottomAnchor)
            ])

            self.hostedView = rootView
            Self.activeSession = self
            isActive = true

            NSLog("%@", "HANLIN_EXPO_INITIALIZED_EXTERNAL_ROOT path=\(applicationRoot.path(percentEncoded: false)) bundle=\(bundleURL.lastPathComponent)")
        } catch {
            shutdown()
            throw HanlinExpoError.bootstrapFailed(error.localizedDescription)
        }
    }

    public func shutdown() {
        guard isActive || reactNativeFactory != nil else {
            HanlinExpoModifierRegistry.unregisterCustomModifiers()
            HanlinExpoHostServicesRuntime.uninstall()
            return
        }

        hostedView?.removeFromSuperview()
        hostedView = nil

        if let factory = reactNativeFactory {
            factory.rootViewFactory.reactHost = nil
            factory.rootViewFactory.setValue(nil, forKey: "_reactHost")
        }
        reactNativeFactory = nil
        factoryDelegate = nil
        appContext?.destroy()
        appContext = nil
        isActive = false

        HanlinExpoModifierRegistry.unregisterCustomModifiers()
        HanlinExpoHostServicesRuntime.uninstall()

        if Self.activeSession === self {
            Self.activeSession = nil
        }
    }

    deinit {
        MainActor.assumeIsolated {
            shutdown()
        }
    }
}
