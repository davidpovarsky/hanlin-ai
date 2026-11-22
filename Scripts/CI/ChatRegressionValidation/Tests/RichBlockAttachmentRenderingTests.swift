#if canImport(UIKit)
import XCTest
import SwiftUI
import UIKit
@testable import SwiftStreamingMarkdown

/// Exercises TextKit's real provider lookup and viewport insertion, not just the
/// attributed-string selection map. A document icon is not a successful render.
@MainActor
final class RichBlockAttachmentRenderingTests: XCTestCase {
  private let source = """
  Before the rich blocks.

  ---

  | Place | Travel |
  | --- | --- |
  | Acre | Train |

  After the rich blocks.
  """

  private var config: MarkdownRenderConfig {
    .default.withTextSelectionConfig(value: .init(isEnabled: false, continuousSelection: true))
  }

  func testProviderLookupUsesRichRenderer() throws {
    let view = ParagraphUIView(frame: CGRect(x: 0, y: 0, width: 360, height: 600), textContainer: nil)
    view.setAttachmentEnvironment(EnvironmentValues())
    let layout = try XCTUnwrap(view.textLayoutManager, "The native selection document requires TextKit 2")
    let content = try XCTUnwrap(layout.textContentManager)
    let canonical = MarkdownRichBlockAttachment(block: .thematicBreak(id: "divider"), selectionText: "")
    let attachment = canonical.owned(by: view)
    let provider = try XCTUnwrap(attachment.viewProvider(for: view, location: content.documentRange.location,
                                                       textContainer: view.textContainer))
    XCTAssertTrue(provider is MarkdownRichBlockViewProvider,
                  "UIKit must resolve the rich-block provider, not its generic file-icon fallback; got \(type(of: provider))")
    // File metadata is not the contract of this in-memory provider. Its
    // attachment and layout manager must belong to this exact native document.
    XCTAssertTrue(provider.textAttachment === attachment,
                  "The rich provider must reference the exact owned attachment")
    XCTAssertTrue(provider.textLayoutManager === layout,
                  "The rich provider must reference the native document's layout manager")
    XCTAssertTrue(attachment.allowsTextAttachmentView)
    XCTAssertNotNil(view.textLayoutManager, "Provider lookup must not fall back to TextKit 1")

    // Exercise Foundation's attribute replacement/uniquing with the same
    // canonical document mounted independently in two native text views.
    let contents = NSMutableAttributedString(attachment: canonical)
    view.setParagraphContents(contents, animatedByWord: false)
    let sibling = ParagraphUIView(frame: view.frame, textContainer: nil)
    sibling.setAttachmentEnvironment(EnvironmentValues())
    sibling.setParagraphContents(contents, animatedByWord: false)
    let first = try XCTUnwrap(view.textStorage.attribute(.attachment, at: 0,
      effectiveRange: nil) as? MarkdownRichBlockAttachment)
    let second = try XCTUnwrap(sibling.textStorage.attribute(.attachment, at: 0,
      effectiveRange: nil) as? MarkdownRichBlockAttachment)
    XCTAssertTrue(first.owner === view, "Stored attachment must retain its own text view's environment")
    XCTAssertTrue(second.owner === sibling, "Equal document content must not reuse another text view's owner")
    XCTAssertFalse(first === second, "Independent native documents need independent attachment ownership")
    XCTAssertTrue(view.paragraphContents.attribute(.attachment, at: 0, effectiveRange: nil) as? MarkdownRichBlockAttachment === canonical,
                  "Streaming tail planning must retain canonical attributes, not mounted copies")
    XCTAssertNil(canonical.owner, "Mounting must not mutate the parser's canonical attachment")
  }

  func testNativeDocumentDisplaysDividerAndTableAcrossWidths() async throws {
    let document = await MarkdownParserImpl().parse(text: source, config: config)
    guard case .paragraph(_, let contents)? = document.selectionRenderables?.first else {
      return XCTFail("The real parser must produce a continuous native document")
    }
    let window = try makeWindow(size: CGSize(width: 700, height: 900))
    let controller = UIViewController()
    controller.view.backgroundColor = .systemBackground
    window.rootViewController = controller
    let view = ParagraphUIView(frame: CGRect(x: 20, y: 20, width: 640, height: 800), textContainer: nil)
    var environment = EnvironmentValues()
    environment.markdownConfig = config
    view.setAttachmentEnvironment(environment)
    // The first measurement occurs before a native view is inserted in a window.
    view.setParagraphContents(NSMutableAttributedString(attributedString: contents), animatedByWord: false)
    _ = view.sizeThatFits(CGSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
    controller.view.addSubview(view)
    window.makeKeyAndVisible()
    defer {
      view.setAttachmentEnvironment(nil)
      window.isHidden = true
    }

    for width in [CGFloat(640), 320] {
      view.frame.size.width = width
      await settleLayout(view)
      let hosts = richHosts(in: view)
      XCTAssertEqual(hosts.count, 2, "Both divider and table must mount their original rich renderer")
      XCTAssertNotNil(view.textLayoutManager)
      let geometry = hosts.map { "bounds=\($0.bounds), children=\($0.subviews.count)" }.joined(separator: "; ")
      XCTAssertTrue(hosts.allSatisfy { !$0.subviews.isEmpty && $0.bounds.width > width * 0.8 },
                    "Rich attachments must have their hosted content and fill the native line; \(geometry)")
      XCTAssertTrue(hosts.contains { $0.bounds.height > 30 }, "The table must occupy its real content height; \(geometry)")
      XCTAssertTrue(view.text.contains("Before the rich blocks.") && view.text.contains("After the rich blocks."))
      let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
        controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
      }
      let evidence = XCTAttachment(image: image)
      evidence.name = "rich-blocks-width-\(Int(width))"
      evidence.lifetime = .keepAlways
      add(evidence)
    }
  }

  func testAppendingTextPreservesSelectionAcrossRichBlocks() async throws {
    let parser = MarkdownParserImpl()
    let document = await parser.parse(text: source, config: config)
    let appended = await parser.parse(text: source + " More streamed content.", config: config)
    guard case .paragraph(_, let contents)? = document.selectionRenderables?.first,
          case .paragraph(_, let updated)? = appended.selectionRenderables?.first else {
      return XCTFail("Expected actual continuous selection documents")
    }
    let window = try makeWindow(size: CGSize(width: 500, height: 900))
    let controller = UIViewController()
    window.rootViewController = controller
    let view = ParagraphUIView(frame: CGRect(x: 20, y: 20, width: 460, height: 800), textContainer: nil)
    var environment = EnvironmentValues()
    environment.markdownConfig = config
    view.setAttachmentEnvironment(environment)
    view.setParagraphContents(NSMutableAttributedString(attributedString: contents), animatedByWord: false)
    controller.view.addSubview(view)
    window.makeKeyAndVisible()
    defer {
      view.setAttachmentEnvironment(nil)
      window.isHidden = true
    }
    await settleLayout(view)
    XCTAssertTrue(view.becomeFirstResponder())
    let selection = NSRange(location: 0, length: contents.length)
    view.selectedRange = selection
    let quote = MarkdownTextSelection(attributedText: view.textStorage, selectedRange: selection)
    XCTAssertTrue(quote.text.contains("Acre"))
    XCTAssertTrue(quote.text.contains("After the rich blocks."))
    view.setParagraphContents(NSMutableAttributedString(attributedString: updated), animatedByWord: false)
    await settleLayout(view)
    XCTAssertEqual(view.selectedRange, selection)
    XCTAssertEqual(richHosts(in: view).count, 2)
    XCTAssertNotNil(view.textLayoutManager)
  }

  private func makeWindow(size: CGSize) throws -> UIWindow {
    guard let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive }) else {
      throw XCTSkip("Mounted rich-block rendering requires an app host with a foreground UIWindowScene; the focused native probe rejects skips.")
    }
    let window = UIWindow(windowScene: scene)
    window.overrideUserInterfaceStyle = .light
    window.frame = CGRect(origin: .zero, size: size)
    return window
  }

  private func richHosts(in view: UIView) -> [MarkdownRichBlockHostView] {
    (view as? MarkdownRichBlockHostView).map { [$0] } ?? view.subviews.flatMap { richHosts(in: $0) }
  }

  private func settleLayout(_ view: ParagraphUIView) async {
    for _ in 0..<8 {
      view.setNeedsLayout()
      if let manager = view.textLayoutManager, let content = manager.textContentManager {
        manager.ensureLayout(for: content.documentRange)
      }
      view.layoutIfNeeded()
      try? await Task.sleep(for: .milliseconds(25))
    }
  }
}
#endif
