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
        ExpoUIView(HanlinSlotView.self)
        ExpoUIView(HanlinSearchableView.self)
        ExpoUIView(HanlinPresentationView.self)
        ExpoUIView(HanlinInspectorView.self)
        ExpoUIView(HanlinFocusedView.self)
        ExpoUIView(HanlinSafeAreaInsetView.self)
        ExpoUIView(HanlinAsyncImageView.self)
        ExpoUIView(HanlinTableView.self)
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

public final class HanlinSlotProps: UIBaseViewProps {
    @Field public var name = ""
}

public struct HanlinSlotView: ExpoSwiftUI.View {
    @ObservedObject public var props: HanlinSlotProps
    public var body: some View { Children() }
}

@ViewBuilder
private func hanlinNamedSlot(_ props: UIBaseViewProps, _ name: String) -> some View {
    if let slot = props.children?
        .compactMap({ $0.childView as? HanlinSlotView })
        .first(where: { $0.props.name == name }) {
        slot
    }
}

public enum HanlinSearchPlacement: String, Enumerable {
    case automatic
    case navigationBar
    case toolbar

    var value: SearchFieldPlacement {
        switch self {
        case .automatic: .automatic
        case .navigationBar: .navigationBarDrawer(displayMode: .automatic)
        case .toolbar: .toolbar
        }
    }
}

public final class HanlinSearchableProps: UIBaseViewProps {
    @Field public var value: String?
    @Field public var defaultValue = ""
    @Field public var isPresented: Bool?
    @Field public var defaultPresented = false
    @Field public var prompt: String?
    @Field public var placement: HanlinSearchPlacement = .automatic
    public var onValueChange = EventDispatcher()
    public var onPresentedChange = EventDispatcher()
    public var onSubmit = EventDispatcher()
}

public struct HanlinSearchableView: ExpoSwiftUI.View {
    @ObservedObject public var props: HanlinSearchableProps
    @State private var text: String
    @State private var presented: Bool

    public init(props: HanlinSearchableProps) {
        self.props = props
        _text = State(initialValue: props.value ?? props.defaultValue)
        _presented = State(initialValue: props.isPresented ?? props.defaultPresented)
    }

    public var body: some View {
        searchableContent
            .onSubmit(of: .search) { props.onSubmit(["value": text]) }
            .onChange(of: props.value) { _, value in
                guard let value, value != text else { return }
                text = value
            }
            .onChange(of: props.isPresented) { _, value in
                guard let value, value != presented else { return }
                presented = value
            }
            .onChange(of: text) { _, value in
                guard value != props.value else { return }
                props.onValueChange(["value": value])
            }
            .onChange(of: presented) { _, value in
                guard value != props.isPresented else { return }
                props.onPresentedChange(["value": value])
            }
    }

    @ViewBuilder private var searchableContent: some View {
        if let prompt = props.prompt {
            hanlinNamedSlot(props, "content")
                .searchable(
                    text: $text,
                    isPresented: $presented,
                    placement: props.placement.value,
                    prompt: Text(prompt)
                ) { hanlinNamedSlot(props, "suggestions") }
        } else {
            hanlinNamedSlot(props, "content")
                .searchable(
                    text: $text,
                    isPresented: $presented,
                    placement: props.placement.value
                ) { hanlinNamedSlot(props, "suggestions") }
        }
    }
}

public enum HanlinPresentationKind: String, Enumerable {
    case sheet
    case fullScreenCover
    case popover
}

public final class HanlinPresentationProps: UIBaseViewProps {
    @Field public var kind: HanlinPresentationKind = .sheet
    @Field public var isPresented: Bool?
    @Field public var defaultPresented = false
    public var onPresentedChange = EventDispatcher()
    public var onDismiss = EventDispatcher()
}

public struct HanlinPresentationView: ExpoSwiftUI.View {
    @ObservedObject public var props: HanlinPresentationProps
    @State private var presented: Bool

    public init(props: HanlinPresentationProps) {
        self.props = props
        _presented = State(initialValue: props.isPresented ?? props.defaultPresented)
    }

    @ViewBuilder public var body: some View {
        switch props.kind {
        case .sheet:
            hanlinNamedSlot(props, "content")
                .sheet(isPresented: $presented) {
                    hanlinNamedSlot(props, "presented")
                }
                .modifier(PresentationStateSync(props: props, presented: $presented))
        case .fullScreenCover:
            hanlinNamedSlot(props, "content")
                .fullScreenCover(isPresented: $presented) {
                    hanlinNamedSlot(props, "presented")
                }
                .modifier(PresentationStateSync(props: props, presented: $presented))
        case .popover:
            hanlinNamedSlot(props, "content")
                .popover(isPresented: $presented) {
                    hanlinNamedSlot(props, "presented")
                }
                .modifier(PresentationStateSync(props: props, presented: $presented))
        }
    }

}

private struct PresentationStateSync: ViewModifier {
    @ObservedObject var props: HanlinPresentationProps
    @Binding var presented: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: props.isPresented) { _, value in
                guard let value, value != presented else { return }
                presented = value
            }
            .onChange(of: presented) { _, value in
                guard value != props.isPresented else { return }
                props.onPresentedChange(["value": value])
                if !value { props.onDismiss([:]) }
            }
    }
}

public final class HanlinInspectorProps: UIBaseViewProps {
    @Field public var isPresented: Bool?
    @Field public var defaultPresented = false
    public var onPresentedChange = EventDispatcher()
}

public struct HanlinInspectorView: ExpoSwiftUI.View {
    @ObservedObject public var props: HanlinInspectorProps
    @State private var presented: Bool

    public init(props: HanlinInspectorProps) {
        self.props = props
        _presented = State(initialValue: props.isPresented ?? props.defaultPresented)
    }

    public var body: some View {
        hanlinNamedSlot(props, "content")
            .inspector(isPresented: $presented) { hanlinNamedSlot(props, "inspector") }
            .onChange(of: props.isPresented) { _, value in
                guard let value, value != presented else { return }
                presented = value
            }
            .onChange(of: presented) { _, value in
                guard value != props.isPresented else { return }
                props.onPresentedChange(["value": value])
            }
    }
}

public final class HanlinFocusedProps: UIBaseViewProps {
    @Field public var isFocused: Bool?
    @Field public var defaultFocused = false
    public var onFocusedChange = EventDispatcher()
}

public struct HanlinFocusedView: ExpoSwiftUI.View {
    @ObservedObject public var props: HanlinFocusedProps
    @FocusState private var focused: Bool

    public var body: some View {
        hanlinNamedSlot(props, "content")
            .focused($focused)
            .onAppear { focused = props.isFocused ?? props.defaultFocused }
            .onChange(of: props.isFocused) { _, value in
                guard let value, value != focused else { return }
                focused = value
            }
            .onChange(of: focused) { _, value in
                guard value != props.isFocused else { return }
                props.onFocusedChange(["value": value])
            }
    }
}

public enum HanlinSafeAreaEdge: String, Enumerable {
    case top
    case bottom
    case leading
    case trailing
}

public final class HanlinSafeAreaInsetProps: UIBaseViewProps {
    @Field public var edge: HanlinSafeAreaEdge = .bottom
    @Field public var spacing: CGFloat?
}

public struct HanlinSafeAreaInsetView: ExpoSwiftUI.View {
    @ObservedObject public var props: HanlinSafeAreaInsetProps

    @ViewBuilder public var body: some View {
        switch props.edge {
        case .top:
            content.safeAreaInset(edge: .top, spacing: props.spacing) { inset }
        case .bottom:
            content.safeAreaInset(edge: .bottom, spacing: props.spacing) { inset }
        case .leading:
            content.safeAreaInset(edge: .leading, spacing: props.spacing) { inset }
        case .trailing:
            content.safeAreaInset(edge: .trailing, spacing: props.spacing) { inset }
        }
    }

    private var content: some View { hanlinNamedSlot(props, "content") }
    private var inset: some View { hanlinNamedSlot(props, "inset") }
}

public final class HanlinAsyncImageProps: UIBaseViewProps {
    @Field public var url: String?
    @Field public var scale: CGFloat = 1
    public var onPhaseChange = EventDispatcher()
}

public struct HanlinAsyncImageView: ExpoSwiftUI.View {
    @ObservedObject public var props: HanlinAsyncImageProps

    public var body: some View {
        AsyncImage(url: props.url.flatMap(URL.init(string:)), scale: props.scale) { phase in
            switch phase {
            case .empty:
                hanlinNamedSlot(props, "placeholder")
                    .onAppear { props.onPhaseChange(["phase": "empty"]) }
            case .success(let image):
                image
                    .resizable()
                    .onAppear { props.onPhaseChange(["phase": "success"]) }
            case .failure:
                hanlinNamedSlot(props, "failure")
                    .onAppear { props.onPhaseChange(["phase": "failure"]) }
            @unknown default:
                EmptyView()
            }
        }
    }
}

public final class HanlinTableColumnRecord: Record {
    @Field public var key = ""
    @Field public var title = ""
    public required init() {}
}

public final class HanlinTableRowRecord: Record {
    @Field public var id = ""
    @Field public var values: [String: String] = [:]
    public required init() {}
}

private struct HanlinTableRow: Identifiable {
    let id: String
    let values: [String: String]
}

public final class HanlinTableProps: UIBaseViewProps {
    @Field public var columns: [HanlinTableColumnRecord] = []
    @Field public var rows: [HanlinTableRowRecord] = []
    @Field public var selection: String?
    public var onSelectionChange = EventDispatcher()
}

public struct HanlinTableView: ExpoSwiftUI.View {
    @ObservedObject public var props: HanlinTableProps
    @State private var selection: String?

    public init(props: HanlinTableProps) {
        self.props = props
        _selection = State(initialValue: props.selection)
    }

    public var body: some View {
        Table(rows, selection: $selection) {
            TableColumnForEach(props.columns, id: \.key) { column in
                TableColumn(column.title) { row in
                    Text(row.values[column.key] ?? "")
                }
            }
        }
        .onChange(of: props.selection) { _, value in
            guard value != selection else { return }
            selection = value
        }
        .onChange(of: selection) { _, value in
            guard value != props.selection else { return }
            props.onSelectionChange(["value": value as Any])
        }
    }

    private var rows: [HanlinTableRow] {
        props.rows.map { HanlinTableRow(id: $0.id, values: $0.values) }
    }
}
