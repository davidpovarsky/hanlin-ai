import HanlinChatUI
import Hanlin145801ComposerBaseline
import HanlinPresentationKit
import SwiftUI
import UIKit
import XCTest

/// Uses the actual shipping shell and the exact 145801 source compiled in an
/// isolated module. The snapshots exercise the native glass compositor; the
/// geometry assertions are not presented as proof of the material's appearance.
@MainActor
final class ComposerGlassRenderingTests: XCTestCase {
    func testOriginalAndCorrectedGlassAcrossDraftsAndViewports() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let configurations: [(String, CGFloat, CGFloat, CGFloat, LayoutDirection)] = [
            ("wide-empty", 744, 102, 24, .leftToRight),
            ("narrow-empty-rtl", 320, 102, 24, .rightToLeft),
            ("wide-long", 744, 240, 24, .leftToRight),
            ("narrow-long-rtl", 320, 240, 24, .rightToLeft),
            ("expanded-rtl", 744, 420, 24, .rightToLeft),
            ("moved-origin-rtl", 600, 102, 230, .rightToLeft)
        ]
        defer { window.isHidden = true; window.rootViewController = nil }
        for (name, proposedWidth, inputHeight, origin, direction) in configurations {
            let width = min(proposedWidth, scene.coordinateSpace.bounds.width - 24)
            let available = scene.coordinateSpace.bounds.height - origin - 24
            var baselineFrames: [String: CGRect] = [:]
            for baseline in [true, false] {
                let measurements = ComposerProbeMeasurements()
                let root = ComposerProbeFixture(baseline: baseline, width: width,
                    inputHeight: inputHeight, origin: origin, availableHeight: available,
                    direction: direction, measurements: measurements)
                let host = UIHostingController(rootView: root)
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                // The native material must complete a display transaction. This
                // bounded wait is unrelated to app state or simulated progress.
                try await Task.sleep(for: .milliseconds(350))
                host.view.layoutIfNeeded()
                let input = try XCTUnwrap(measurements.frames["input"])
                let page = try XCTUnwrap(measurements.frames["page"])
                XCTAssertTrue(input.isFiniteAndPositive)
                XCTAssertTrue(page.isFiniteAndPositive)
                XCTAssertEqual(input.height, inputHeight, accuracy: 1)
                XCTAssertLessThan(page.maxY, input.minY)
                // Native targets under the extended panel material must still
                // receive hit tests. A decorative glass layer must never become
                // a touch shield over the editor or its bottom control row.
                for key in ["editor", "model", "tools", "microphone", "send"] {
                    let target = try XCTUnwrap(measurements.targets[key], key)
                    let targetFrame = target.convert(target.bounds, to: window)
                    XCTAssertTrue(targetFrame.isFiniteAndPositive, key)
                    let hit = try XCTUnwrap(window.hitTest(
                        CGPoint(x: targetFrame.midX, y: targetFrame.midY), with: nil), key)
                    XCTAssertTrue(hit === target || hit.isDescendant(of: target),
                                  "\(name): \(key) intercepted by \(type(of: hit))")
                    measurements.frames["hit-" + key] = targetFrame
                    if let button = target as? UIButton {
                        button.sendActions(for: .touchUpInside)
                        XCTAssertTrue(measurements.invokedActions.contains(key), key)
                    }
                }
                if baseline {
                    baselineFrames = measurements.frames
                } else {
                    // Material correction must not move content or the bottom
                    // controls, change width, or consume any page height.
                    for key in ["input", "page"] {
                        let actual = try XCTUnwrap(measurements.frames[key])
                        let previous = try XCTUnwrap(baselineFrames[key])
                        XCTAssertEqual(actual.minX, previous.minX, accuracy: 1, key)
                        XCTAssertEqual(actual.minY, previous.minY, accuracy: 1, key)
                        XCTAssertEqual(actual.width, previous.width, accuracy: 1, key)
                        XCTAssertEqual(actual.height, previous.height, accuracy: 1, key)
                    }
                }
                let label = "\(name)-\(baseline ? "145801" : "corrected")"
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = label
                attachment.lifetime = .keepAlways
                add(attachment)
                let detail = measurements.frames.mapValues {
                    ["x": $0.minX, "y": $0.minY, "width": $0.width, "height": $0.height]
                }
                let data = try JSONSerialization.data(withJSONObject: detail, options: [.sortedKeys, .prettyPrinted])
                let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                receipt.name = label + "-frames"
                receipt.lifetime = .keepAlways
                add(receipt)
            }
        }
        // Use the same public activity components as the app: Thinking keeps
        // its root sweep while actual visible tools retain their own motion.
        for expanded in [true, false] {
            let host = UIHostingController(rootView: ActivityProbeFixture(isExpanded: expanded))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(350))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = expanded ? "activity-expanded-leaf" : "activity-collapsed-parent"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

@MainActor
private struct ActivityProbeFixture: View {
    let isExpanded: Bool

    var body: some View {
        VStack {
            DisclosureGroup(isExpanded: .constant(isExpanded)) {
                HanlinActivityTitle("Checking the route", font: HanlinTypography.footnote,
                    baseColor: .secondary, isActive: isExpanded)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("activity-live-leaf")
            } label: {
                HanlinActivityHierarchyHeader(
                    title: "Thinking",
                    symbol: "sparkles", isExpanded: isExpanded, isActive: true)
                    .accessibilityIdentifier("activity-root")
            }
            .disclosureGroupStyle(HanlinActivityDisclosureStyle(depth: 0))
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }
}

@MainActor
private final class ComposerProbeMeasurements {
    var frames: [String: CGRect] = [:]
    var targets: [String: UIView] = [:]
    var invokedActions: Set<String> = []
}

@MainActor
private struct ComposerProbeFixture: View {
    let baseline: Bool
    let width: CGFloat
    let inputHeight: CGFloat
    let origin: CGFloat
    let availableHeight: CGFloat
    let direction: LayoutDirection
    let measurements: ComposerProbeMeasurements

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [.white, .cyan.opacity(0.38), .white, .orange.opacity(0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                Color.clear.frame(height: origin)
                shell.frame(width: width)
                Spacer(minLength: 0)
            }
        }
        .environment(\.layoutDirection, direction)
        .preferredColorScheme(.light)
        .coordinateSpace(name: "probe")
    }

    @ViewBuilder private var shell: some View {
        if baseline {
            Hanlin145801ComposerBaseline.HanlinMorphComposer(
                isExpanded: .constant(true), activePage: .constant(Optional<String>.none),
                availableHeight: availableHeight, accessoryHeight: 0, inputHeight: inputHeight,
                title: { _ in "Action Center" }, subtitle: { _ in "Live capabilities" },
                backIdentifier: { $0 }, onOpen: {}, onBackgroundTap: {}, onToolbarHeightChange: { _ in },
                home: { page }, detail: { _ in page }, input: { input })
        } else {
            HanlinChatUI.HanlinMorphComposer(
                isExpanded: .constant(true), activePage: .constant(Optional<String>.none),
                availableHeight: availableHeight, accessoryHeight: 0, inputHeight: inputHeight,
                title: { _ in "Action Center" }, subtitle: { _ in "Live capabilities" },
                backIdentifier: { $0 }, onOpen: {}, onBackgroundTap: {}, onToolbarHeightChange: { _ in },
                home: { page }, detail: { _ in page }, input: { input })
        }
    }

    private var page: some View {
        VStack(spacing: 10) {
            ForEach(["Search", "Tools", "Skills"], id: \.self) { title in
                Text(title).font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(HanlinMorphStyle.blue, in: RoundedRectangle(cornerRadius: 17))
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("probe")) } action: {
            measurements.frames["page"] = $0
        }
    }

    private var input: some View {
        ComposerProbeNativeInput(measurements: measurements, direction: direction)
        .frame(height: inputHeight)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("probe")) } action: {
            measurements.frames["input"] = $0
        }
    }
}

/// Real native input targets expose UIKit hit-test routing through the shell.
/// This tests material overlap without importing app accounts or Runtime state.
@MainActor
private struct ComposerProbeNativeInput: UIViewRepresentable {
    let measurements: ComposerProbeMeasurements
    let direction: LayoutDirection

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        let editor = UITextView()
        editor.backgroundColor = .clear
        editor.font = .preferredFont(forTextStyle: .body)
        editor.text = "Draft / טיוטה"
        editor.textContainerInset = .zero
        editor.textContainer.lineFragmentPadding = 0
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.accessibilityIdentifier = "probe-editor"
        container.addSubview(editor)
        measurements.targets["editor"] = editor

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        let controls = [("model", ""), ("tools", "hammer.circle.fill"),
                        ("microphone", "mic"), ("send", "arrow.up.circle.fill")]
        for (key, symbol) in controls {
            var configuration = UIButton.Configuration.plain()
            configuration.contentInsets = .zero
            if key == "model" {
                configuration.title = "nvidia/nemotron…"
                configuration.titleLineBreakMode = .byTruncatingTail
            } else {
                configuration.image = UIImage(systemName: symbol)
            }
            let button = UIButton(configuration: configuration)
            button.accessibilityIdentifier = "probe-" + key
            button.addAction(UIAction { [weak measurements] _ in
                measurements?.invokedActions.insert(key)
            }, for: .touchUpInside)
            row.addArrangedSubview(button)
            if key == "model" {
                button.setContentHuggingPriority(.defaultLow, for: .horizontal)
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            } else {
                button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            }
            measurements.targets[key] = button
        }
        NSLayoutConstraint.activate([
            editor.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 11),
            editor.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -11),
            editor.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            editor.bottomAnchor.constraint(equalTo: row.topAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            row.heightAnchor.constraint(equalToConstant: 44)
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.semanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        (measurements.targets["editor"] as? UITextView)?.textAlignment = direction == .rightToLeft ? .right : .left
    }
}

private extension CGRect {
    var isFiniteAndPositive: Bool {
        origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite
            && width > 0 && height > 0
    }
}
