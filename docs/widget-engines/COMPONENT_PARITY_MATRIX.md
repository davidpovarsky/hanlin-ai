> Pass 3, 2026-10-30: original native builders are now source-ported. Every native semantic/screenshot result remains NOT_TESTED until an Apple run supplies matching assertions. Previous AnyView construction checks did not establish parity. Mixed-tree is DEFERRED_OPTIONAL.

# Component Parity Matrix — Dual Native Widget Engines

## 1. ScriptWidget 29 Native Tags Matrix

| # | Tag Name | Upstream Implementation | Hanlin Native Implementation | Supported Attributes & Props | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `hstack` | `ScriptWidgetElementTagStack` | `HStack` with alignment & spacing | `alignment`, `spacing`, `padding`, `background` | **NOT_TESTED** |
| 2 | `vstack` | `ScriptWidgetElementTagStack` | `VStack` with alignment & spacing | `alignment`, `spacing`, `padding`, `background` | **NOT_TESTED** |
| 3 | `zstack` | `ScriptWidgetElementTagZStack` | `ZStack` with 9-point alignment | `alignment`, `padding`, `background` | **NOT_TESTED** |
| 4 | `hgrid` | `ScriptWidgetElementTagGrid` | `LazyHGrid` with dynamic GridItems | `columns` (JSON grid descriptors), `spacing`, `padding` | **NOT_TESTED** |
| 5 | `vgrid` | `ScriptWidgetElementTagGrid` | `LazyVGrid` with dynamic GridItems | `columns`, `spacing`, `padding` | **NOT_TESTED** |
| 6 | `text` | `ScriptWidgetElementTagText` | Native SwiftUI `Text` | `font`, `size`, `weight`, `bold`, `italic`, `color` | **NOT_TESTED** |
| 7 | `date` | `ScriptWidgetElementTagDate` | Native SwiftUI `Text(date, style:)` | `date` (name or milliseconds), `style` (date/time/relative/offset/timer) | **NOT_TESTED** |
| 8 | `image` | `ScriptWidgetElementTagImage` | SFSymbol / Local UIImage | `systemName`, `name`, `src`, `url`, `color` | **NOT_TESTED** |
| 9 | `gif` | `ScriptWidgetElementTagGif` | Original GIF frame pipeline | `file`, image/general modifiers | **NOT_TESTED** |
| 10 | `spacer` | `ScriptWidgetElementTagSpacer` | Native SwiftUI `Spacer` | `minLength` | **NOT_TESTED** |
| 11 | `rect` | `ScriptWidgetElementTagShape` | Native SwiftUI `Rectangle` | `fill`, `color`, `width`, `height` | **NOT_TESTED** |
| 12 | `capsule` | `ScriptWidgetElementTagShape` | Native SwiftUI `Capsule` | `fill`, `color`, `width`, `height` | **NOT_TESTED** |
| 13 | `ellipse` | `ScriptWidgetElementTagShape` | Native SwiftUI `Ellipse` | `fill`, `color`, `width`, `height` | **NOT_TESTED** |
| 14 | `circle` | `ScriptWidgetElementTagShape` | Native SwiftUI `Circle` | `fill`, `color`, `width`, `height` | **NOT_TESTED** |
| 15 | `gauge` | `ScriptWidgetElementTagGauge` | Original MineGaugeView / native SwiftUI `Gauge` | `value`, `min`, `max`, `label`, `title` | **NOT_TESTED** |
| 16 | `chart` | `ScriptWidgetElementTagChart` | Native SwiftUI `Chart` (Bar/Line/Point) | `type`, JSON-string `data: [{label, value}]`; Gantt and rule schemas differ | **NOT_TESTED** |
| 17 | `link` | `ScriptWidgetElementTagLink` | Native SwiftUI `Link` | `title`, `url` | **NOT_TESTED** |
| 18 | `divider` | `ScriptWidgetElementTagDivider` | Native SwiftUI `Rectangle` | `axis`, `thickness`, `color` | **NOT_TESTED** |
| 19 | `line` | `ScriptWidgetElementTagLine` | Native sized `Rectangle` | `axis`, `length`, `thickness`, `color` | **NOT_TESTED** |
| 20 | `roundedrect` | `ScriptWidgetElementTagShape` | Native SwiftUI `RoundedRectangle` | `radius`, `fill`, `color` | **NOT_TESTED** |
| 21 | `icon` | `ScriptWidgetElementTagExtras` | Native SF Symbol `Image(systemName:)` | `name`, `systemName`, `size`, `color` | **NOT_TESTED** |
| 22 | `label` | `ScriptWidgetElementTagExtras` | Native SwiftUI `Label` | `title`, `icon`, `systemImage` | **NOT_TESTED** |
| 23 | `progress` | `ScriptWidgetElementTagExtras` | Native SwiftUI `ProgressView` | `value`, `total` | **NOT_TESTED** |
| 24 | `ring` | `ScriptWidgetElementTagExtras` | Native circular progress ring | `value`, `lineWidth`, `color`, `width`, `height` | **NOT_TESTED** |
| 25 | `badge` | `ScriptWidgetElementTagExtras` | Pill styled caption | `text`, `color` | **NOT_TESTED** |
| 26 | `chip` | `ScriptWidgetElementTagExtras` | Interactive chip with icon | `text`, `icon` | **NOT_TESTED** |
| 27 | `stat` | `ScriptWidgetElementTagExtras` | Metric header + value + trend | `title`, `value`, `trend` | **NOT_TESTED** |
| 28 | `button` | `ScriptWidgetElementTagButton` | SwiftUI `Button` with AppIntent | `title`, `label`, `action`, `target` | **NOT_TESTED** |
| 29 | `toggle` | `ScriptWidgetElementTagToggle` | SwiftUI `Toggle` with AppIntent | `title`, `label`, `isOn`, `target` | **NOT_TESTED** |

---

## 2. Expo Widgets Renderer Matrix

| Component Type | Native SwiftUI Representation | Supported Modifiers | Interactivity | Status |
| :--- | :--- | :--- | :--- | :--- |
| `TextView` / `Text` | SwiftUI `Text` | `font`, `fontSize`, `fontWeight`, `color` | Static | **NOT_TESTED** |
| `HStackView` / `HStack` | SwiftUI `HStack` | `spacing`, `alignment`, `padding`, `background` | Container | **NOT_TESTED** |
| `VStackView` / `VStack` | SwiftUI `VStack` | `spacing`, `alignment`, `padding`, `background` | Container | **NOT_TESTED** |
| `ZStackView` / `ZStack` | SwiftUI `ZStack` | `alignment`, `padding`, `background` | Container | **NOT_TESTED** |
| `RectangleView` | SwiftUI `Rectangle` | `fill`, `width`, `height` | Static | **NOT_TESTED** |
| `RoundedRectangleView` | SwiftUI `RoundedRectangle` | `cornerRadius`, `fill` | Static | **NOT_TESTED** |
| `CapsuleView` | SwiftUI `Capsule` | `fill`, `width`, `height` | Static | **NOT_TESTED** |
| `CircleView` | SwiftUI `Circle` | `fill`, `width`, `height` | Static | **NOT_TESTED** |
| `EllipseView` | SwiftUI `Ellipse` | `fill`, `width`, `height` | Static | **NOT_TESTED** |
| `SpacerView` | SwiftUI `Spacer` | `minLength` | Static | **NOT_TESTED** |
| `DividerView` | SwiftUI `Divider` | Standard system divider | Static | **NOT_TESTED** |
| `ImageView` | SwiftUI `Image` | SFSymbol or App Group file URI | Static | **NOT_TESTED** |
| `ProgressView` | SwiftUI `ProgressView` | `value`, `total` | Dynamic | **NOT_TESTED** |
| `GaugeView` | SwiftUI `Gauge` | `value`, `min`, `max`, `label` | Dynamic | **NOT_TESTED** |
| `ChartView` | SwiftUI `Chart` | BarMark, LineMark, PointMark | Dynamic | **NOT_TESTED** |
| `Button` / `WidgetButtonView` | SwiftUI `Button` | `title`, `systemImage`, `target` | **Interactive AppIntent** | **NOT_TESTED** |
| `LinkView` | SwiftUI `Link` | `title`, `url` | URL Navigation | **NOT_TESTED** |
| `AccessoryWidgetBackgroundView` | `AccessoryWidgetBackground` | Standard watchOS / Lock Screen background | System background | **NOT_TESTED** |
| `ScriptWidgetSubtree` | `HanlinScriptWidgetElementView` | Embedded JSX script / element tree | Mixed Tree | **NOT_TESTED** |
