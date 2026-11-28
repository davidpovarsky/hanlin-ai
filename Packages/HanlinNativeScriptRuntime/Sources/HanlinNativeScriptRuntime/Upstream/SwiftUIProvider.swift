// Derived from @nativescript/swift-ui 4.0.2, platforms/ios/src/SwiftUIProvider.swift.
// Copyright OpenJS Foundation and NativeScript contributors. Apache-2.0.
// Hanlin intentionally embeds only the public provider contract required by the
// plugin's JavaScript runtime; package-authored Swift remains a build-time concern.

import SwiftUI
import UIKit

@MainActor
@objc public protocol SwiftUIProvider where Self: UIViewController {
    func updateData(data: NSDictionary)
    var onEvent: ((NSDictionary) -> Void)? { get set }
}

public extension SwiftUIProvider {
    func setupSwiftUIView<Content: View>(content: Content) {
        let hostingController = UIHostingController(rootView: content)
        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }
}
