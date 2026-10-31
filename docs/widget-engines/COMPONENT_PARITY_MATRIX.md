> Pass 3, observed 2026-10-31: original native builders are source-ported and Apple compiled. Run 41239674500 at 5bfcf03b executes originalTagProducesDistinctNativeRaster for all 29 tags, originalChartVariantUsesItsNativeDataSchema for ten charts and gridColumnsDateAndNativeElementSemantics. Raw native PNGs are in its widget-package artifact. This is PARTIAL semantic coverage, not complete per-prop, WidgetKit, RTL or Dynamic Type parity. Mixed-tree is DEFERRED_OPTIONAL.

# Component Parity Matrix — Dual Native Widget Engines

## 1. ScriptWidget 29 Native Tags Matrix

| # | Tag Name | Upstream Implementation | Hanlin Native Implementation | Supported Attributes & Props | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `hstack` | `ScriptWidgetElementTagStack` | `HStack` with alignment & spacing | `alignment`, `spacing`, `padding`, `background` | **PARTIAL** |
| 2 | `vstack` | `ScriptWidgetElementTagStack` | `VStack` with alignment & spacing | `alignment`, `spacing`, `padding`, `background` | **PARTIAL** |
| 3 | `zstack` | `ScriptWidgetElementTagZStack` | `ZStack` with 9-point alignment | `alignment`, `padding`, `background` | **PARTIAL** |
| 4 | `hgrid` | `ScriptWidgetElementTagGrid` | `LazyHGrid` with dynamic GridItems | `columns` (JSON grid descriptors), `spacing`, `padding` | **PARTIAL** |
| 5 | `vgrid` | `ScriptWidgetElementTagGrid` | `LazyVGrid` with dynamic GridItems | `columns`, `spacing`, `padding` | **PARTIAL** |
| 6 | `text` | `ScriptWidgetElementTagText` | Native SwiftUI `Text` | `font`, `size`, `weight`, `bold`, `italic`, `color` | **PARTIAL** |
| 7 | `date` | `ScriptWidgetElementTagDate` | Native SwiftUI `Text(date, style:)` | `date` (name or milliseconds), `style` (date/time/relative/offset/timer) | **PARTIAL** |
| 8 | `image` | `ScriptWidgetElementTagImage` | SFSymbol / Local UIImage | `systemName`, `name`, `src`, `url`, `color` | **PARTIAL** |
| 9 | `gif` | `ScriptWidgetElementTagGif` | Original GIF frame pipeline | `file`, image/general modifiers | **PARTIAL** |
| 10 | `spacer` | `ScriptWidgetElementTagSpacer` | Native SwiftUI `Spacer` | `minLength` | **PARTIAL** |
| 11 | `rect` | `ScriptWidgetElementTagShape` | Native SwiftUI `Rectangle` | `fill`, `color`, `width`, `height` | **PARTIAL** |
| 12 | `capsule` | `ScriptWidgetElementTagShape` | Native SwiftUI `Capsule` | `fill`, `color`, `width`, `height` | **PARTIAL** |
| 13 | `ellipse` | `ScriptWidgetElementTagShape` | Native SwiftUI `Ellipse` | `fill`, `color`, `width`, `height` | **PARTIAL** |
| 14 | `circle` | `ScriptWidgetElementTagShape` | Native SwiftUI `Circle` | `fill`, `color`, `width`, `height` | **PARTIAL** |
| 15 | `gauge` | `ScriptWidgetElementTagGauge` | Original MineGaugeView / native SwiftUI `Gauge` | `type`, `style`, `value`, `current`, `min`, `max`, `sections`, `label`, `title` | **PARTIAL** |
| 16 | `chart` | `ScriptWidgetElementTagChart` | Native SwiftUI `Chart` (Bar/Line/Point) | `type`, JSON-string `data: [{label, value}]`; Gantt and rule schemas differ | **PARTIAL** |
| 17 | `link` | `ScriptWidgetElementTagLink` | Native SwiftUI `Link` | `title`, `url` | **PARTIAL** |
| 18 | `divider` | `ScriptWidgetElementTagDivider` | Native SwiftUI `Rectangle` | `axis`, `thickness`, `color` | **PARTIAL** |
| 19 | `line` | `ScriptWidgetElementTagLine` | Native sized `Rectangle` | `axis`, `length`, `thickness`, `color` | **PARTIAL** |
| 20 | `roundedrect` | `ScriptWidgetElementTagShape` | Native SwiftUI `RoundedRectangle` | `radius`, `fill`, `color` | **PARTIAL** |
| 21 | `icon` | `ScriptWidgetElementTagExtras` | Native SF Symbol `Image(systemName:)` | `name`, `systemName`, `size`, `color` | **PARTIAL** |
| 22 | `label` | `ScriptWidgetElementTagExtras` | Native SwiftUI `Label` | `title`, `systemName` | **PARTIAL** |
| 23 | `progress` | `ScriptWidgetElementTagExtras` | Native SwiftUI `ProgressView` | `value`, `total` | **PARTIAL** |
| 24 | `ring` | `ScriptWidgetElementTagExtras` | Native circular progress ring | `value`, `lineWidth`, `color`, `width`, `height` | **PARTIAL** |
| 25 | `badge` | `ScriptWidgetElementTagExtras` | Pill styled caption | `text`, `color` | **PARTIAL** |
| 26 | `chip` | `ScriptWidgetElementTagExtras` | Original styled chip text | `text`, `icon` | **PARTIAL** |
| 27 | `stat` | `ScriptWidgetElementTagExtras` | Metric header + value + trend | `title`, `value`, `subtitle`, `color`, `mutedColor` | **PARTIAL** |
| 28 | `button` | `ScriptWidgetElementTagButton` | SwiftUI `Button` with AppIntent | native child labels; `onClick`, declared `actionID` | **PARTIAL** |
| 29 | `toggle` | `ScriptWidgetElementTagToggle` | SwiftUI `Toggle` with AppIntent | native child labels; `on` Bool, declared `actionID`, `stateKey`, `onClick` | **PARTIAL** |

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
| `ScriptWidgetSubtree` | No supported mixed-tree ABI | Explicitly rejected ABI-0 fixture | Optional | **DEFERRED_OPTIONAL** |

Expo rows above remain NOT_TESTED for native semantic outcomes until the four real iOS renderer methods in HanlinNativeWidgetRendererTests finish. Both source-built modules compiled/linked against SDK 27 in 41239669157. Text/slot tests compare exact PNG bytes with native SwiftUI reference views; Chart/Gauge tests inspect their concrete original typed props. These assertions are distinct from actual Home Screen interactions and will be reported individually.
