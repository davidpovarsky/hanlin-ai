import Foundation
import Testing
import HanlinLocalization

@Suite("Original SDK resource ownership")
struct HanlinLocalizationTests {
    @Test func resourceBundleIsIndependentOfHost() {
        #expect(HanlinLocalization.bundle.bundleURL != Bundle.main.bundleURL)
        #expect(FileManager.default.fileExists(atPath: HanlinLocalization.bundle.bundleURL.path))
    }

    #if canImport(Darwin)
    @Test(arguments: ["en", "he", "zh-Hans"])
    func originalTranslationTablesRemainAvailable(locale: String) throws {
        let languageURL = try #require(HanlinLocalization.bundle.url(forResource: locale, withExtension: "lproj"))
        let language = try #require(Bundle(url: languageURL))
        let expected: [String: [String]] = [
            "en": ["Thinking & tools", "MCP Servers", "Response stopped"],
            "he": ["חשיבה וכלים", "שרתי MCP", "התגובה נעצרה"],
            "zh-Hans": ["思考与工具", "MCP 服务器", "回复已停止"]
        ]
        let values = try #require(expected[locale])
        for (index, entry) in [("Localizable", "Thinking & tools"),
                               ("MCPLocalizable", "MCP Servers"),
                               ("RuntimeLocalizable", "Response stopped")].enumerated() {
            #expect(language.localizedString(forKey: entry.1, value: nil, table: entry.0) == values[index])
        }
    }
    #endif
}

#if canImport(SwiftUI)
import SwiftUI

@MainActor
@Suite("Native localized control public boundary")
struct HanlinLocalizedControlTests {
    @Test func labelsKeepTheOriginalNativeTypes() {
        let _: Label<Text, Image> = Label(hanlin: "Done", systemImage: "checkmark")
        let _: Button<Text> = Button(hanlin: "Done") {}
        let _: Button<Label<Text, Image>> = Button(hanlin: "Done", systemImage: "checkmark") {}
        let _: Toggle<Text> = Toggle(hanlin: "Enabled", isOn: .constant(true))
        let _: Picker<Text, Int, Text> = Picker(hanlin: "Action", selection: .constant(0)) { Text(verbatim: "option") }
        let _: Menu<Text, Text> = Menu(hanlin: "Actions") { Text(verbatim: "option") }
        let _: Menu<Label<Text, Image>, Text> = Menu(hanlin: "Actions", systemImage: "ellipsis") { Text(verbatim: "option") }
        let _: Section<Text, Text, EmptyView> = Section(hanlin: "Sources") { Text(verbatim: "source") }
        let _: LabeledContent<Text, Text> = LabeledContent(hanlin: "Name", value: "host-owned value")
        let _: Link<Text> = Link(hanlin: "Open source", destination: URL(string: "https://example.com")!)
        let _: ProgressView<Text, EmptyView> = ProgressView(hanlin: "Loading")
        let _: TextField<Text> = TextField(hanlin: "Message", text: .constant("host-owned text"))
        let _: DatePicker<Text> = DatePicker(hanlin: "Start date", selection: .constant(.distantPast), displayedComponents: [.date])
        let _: DatePicker<Text> = DatePicker(hanlin: "End date", selection: .constant(.distantPast), in: Date.distantPast..., displayedComponents: [.date])
        let _: ContentUnavailableView<Label<Text, Image>, Text?, EmptyView> = ContentUnavailableView(
            hanlin: "Content unavailable", systemImage: "rectangle.slash", description: Text(verbatim: "description"))
        let _: Image = Image(hanlinAsset: "applogo")
        let _: Color = .hanlinHLBlue
        let _: Color = Color.hanlinHLBlue
        let _ = Text(verbatim: "original foreground").foregroundStyle(.hanlinHLOrange)
        let _ = Text(verbatim: "original background").background(.hanlinHLBlue)
        let _ = Circle().fill(.hanlinHLBlue)
        #expect(HanlinLocalization.bundle.bundleURL != Bundle.main.bundleURL)
    }
}
#endif

#if canImport(UIKit)
import UIKit

@MainActor
@Suite("Original iOS visual assets")
struct HanlinOriginalAssetTests {
    @Test func sharedAssetsLoadFromTheirCanonicalBundle() throws {
        // Preserve the original UIColor-taking Color initializer as well.
        let _: Color = Color(.hanlinHLBlue)
        for image in ["applogo", "defaultIcon", "prompt", "translate", "translate_circle"] {
            _ = try #require(UIImage(named: image, in: HanlinLocalization.bundle, compatibleWith: nil))
        }
        for color in ["HLBlue", "HLBluefont", "HLRed", "HLGreen"] {
            _ = try #require(UIColor(named: color, in: HanlinLocalization.bundle, compatibleWith: nil))
        }
    }
}
#endif
