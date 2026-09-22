import ExpoModulesCore
import ExpoUI
import SwiftUI

public final class HanlinExpoUIModule: Module {
    public func definition() -> ModuleDefinition {
        Name("HanlinExpoUI")

        Function("getBridgeMetadata") {
            HanlinExpoBridgeMetadata.dictionary
        }

        ExpoUIView(HanlinTextEditorView.self)
        ExpoUIView(HanlinLazyVGridView.self)
        ExpoUIView(HanlinLazyHGridView.self)
        ExpoUIView(HanlinViewThatFitsView.self)
    }
}

public final class HanlinTextEditorProps: UIBaseViewProps {
    @Field public var value: String?
    @Field public var defaultValue = ""
    @Field public var placeholder: String?
    @Field public var isEditable = true
    public var onValueChange = EventDispatcher()
}

public struct HanlinTextEditorView: ExpoSwiftUI.View {
    @ObservedObject public var props: HanlinTextEditorProps
    @State private var text: String

    public init(props: HanlinTextEditorProps) {
        self.props = props
        _text = State(initialValue: props.value ?? props.defaultValue)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty, let placeholder = props.placeholder {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .disabled(!props.isEditable)
        }
        .onChange(of: props.value) { _, newValue in
            guard let newValue, newValue != text else { return }
            text = newValue
        }
        .onChange(of: text) { _, newValue in
            guard newValue != props.value else { return }
            props.onValueChange(["value": newValue])
        }
    }
}

public enum HanlinGridItemSize: String, Enumerable {
    case fixed
    case flexible
    case adaptive
}

public final class HanlinGridItemRecord: Record {
    @Field public var size: HanlinGridItemSize = .flexible
    @Field public var value: CGFloat?
    @Field public var minimum: CGFloat?
    @Field public var maximum: CGFloat?
    @Field public var spacing: CGFloat?

    public required init() {}

    var item: GridItem {
        let gridSize: GridItem.Size = switch size {
        case .fixed:
            .fixed(value ?? 44)
        case .adaptive:
            .adaptive(minimum: minimum ?? value ?? 44, maximum: maximum ?? .infinity)
        case .flexible:
            .flexible(minimum: minimum ?? 10, maximum: maximum ?? .infinity)
        }
        return GridItem(gridSize, spacing: spacing)
    }
}

public final class HanlinLazyGridProps: UIBaseViewProps {
    @Field public var tracks: [HanlinGridItemRecord] = []
    @Field public var spacing: CGFloat?
    @Field public var pinnedSectionHeaders = false
    @Field public var pinnedSectionFooters = false
}

private extension HanlinLazyGridProps {
    var resolvedTracks: [GridItem] {
        let items = tracks.map(\.item)
        return items.isEmpty ? [GridItem(.flexible())] : items
    }

    var pinnedViews: PinnedScrollableViews {
        var result: PinnedScrollableViews = []
        if pinnedSectionHeaders { result.insert(.sectionHeaders) }
        if pinnedSectionFooters { result.insert(.sectionFooters) }
        return result
    }
}

public struct HanlinLazyVGridView: ExpoSwiftUI.View {
    @ObservedObject public var props: HanlinLazyGridProps

    public var body: some View {
        LazyVGrid(columns: props.resolvedTracks, spacing: props.spacing, pinnedViews: props.pinnedViews) {
            Children()
        }
    }
}

public struct HanlinLazyHGridView: ExpoSwiftUI.View {
    @ObservedObject public var props: HanlinLazyGridProps

    public var body: some View {
        LazyHGrid(rows: props.resolvedTracks, spacing: props.spacing, pinnedViews: props.pinnedViews) {
            Children()
        }
    }
}

public enum HanlinViewThatFitsAxes: String, Enumerable {
    case both
    case horizontal
    case vertical

    var axisSet: Axis.Set {
        switch self {
        case .both: [.horizontal, .vertical]
        case .horizontal: .horizontal
        case .vertical: .vertical
        }
    }
}

public final class HanlinViewThatFitsProps: UIBaseViewProps {
    @Field public var axes: HanlinViewThatFitsAxes = .both
}

public struct HanlinViewThatFitsView: ExpoSwiftUI.View {
    @ObservedObject public var props: HanlinViewThatFitsProps

    public var body: some View {
        ViewThatFits(in: props.axes.axisSet) {
            Children()
        }
    }
}
