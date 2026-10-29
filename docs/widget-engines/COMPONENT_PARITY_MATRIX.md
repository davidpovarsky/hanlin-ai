# Component Parity Matrix — Dual Native Widget Engines

## 1. ScriptWidget 29 Native Tags Matrix

| # | Tag Name | Upstream Implementation | Hanlin Native Implementation | Supported Attributes & Props | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `hstack` | `ScriptWidgetElementTagStack` | `HStack` with alignment & spacing | `alignment`, `spacing`, `padding`, `background` | **FULL_PARITY** |
| 2 | `vstack` | `ScriptWidgetElementTagStack` | `VStack` with alignment & spacing | `alignment`, `spacing`, `padding`, `background` | **FULL_PARITY** |
| 3 | `zstack` | `ScriptWidgetElementTagZStack` | `ZStack` with 9-point alignment | `alignment`, `padding`, `background` | **FULL_PARITY** |
| 4 | `hgrid` | `ScriptWidgetElementTagGrid` | `LazyHGrid` with dynamic GridItems | `rows`, `spacing`, `padding` | **FULL_PARITY** |
| 5 | `vgrid` | `ScriptWidgetElementTagGrid` | `LazyVGrid` with dynamic GridItems | `columns`, `spacing`, `padding` | **FULL_PARITY** |
| 6 | `text` | `ScriptWidgetElementTagText` | Native SwiftUI `Text` | `font`, `size`, `weight`, `bold`, `italic`, `color` | **FULL_PARITY** |
| 7 | `date` | `ScriptWidgetElementTagDate` | Native SwiftUI `Text(date, style:)` | `date`, `timestamp`, `style` (time/relative/offset/timer) | **FULL_PARITY** |
| 8 | `image` | `ScriptWidgetElementTagImage` | SFSymbol / Local UIImage | `systemName`, `name`, `src`, `url`, `color` | **FULL_PARITY** |
| 9 | `gif` | `ScriptWidgetElementTagGif` | Static / First frame Fallback | `src`, `name`, `systemName` | **SUPPORTED** |
| 10 | `spacer` | `ScriptWidgetElementTagSpacer` | Native SwiftUI `Spacer` | `minLength` | **FULL_PARITY** |
| 11 | `rect` | `ScriptWidgetElementTagShape` | Native SwiftUI `Rectangle` | `fill`, `color`, `width`, `height` | **FULL_PARITY** |
| 12 | `capsule` | `ScriptWidgetElementTagShape` | Native SwiftUI `Capsule` | `fill`, `color`, `width`, `height` | **FULL_PARITY** |
| 13 | `ellipse` | `ScriptWidgetElementTagShape` | Native SwiftUI `Ellipse` | `fill`, `color`, `width`, `height` | **FULL_PARITY** |
| 14 | `circle` | `ScriptWidgetElementTagShape` | Native SwiftUI `Circle` | `fill`, `color`, `width`, `height` | **FULL_PARITY** |
| 15 | `gauge` | `ScriptWidgetElementTagGauge` | Native SwiftUI `Gauge` / `ProgressView` | `value`, `min`, `max`, `label`, `title` | **FULL_PARITY** |
| 16 | `chart` | `ScriptWidgetElementTagChart` | Native SwiftUI `Chart` (Bar/Line/Point) | `type`, `data: [{x, y}]`, `color` | **FULL_PARITY** |
| 17 | `link` | `ScriptWidgetElementTagLink` | Native SwiftUI `Link` | `title`, `url` | **FULL_PARITY** |
| 18 | `divider` | `ScriptWidgetElementTagDivider` | Native SwiftUI `Divider` | None (system line) | **FULL_PARITY** |
| 19 | `line` | `ScriptWidgetElementTagLine` | Native 1pt `Rectangle` | `color`, `height` | **FULL_PARITY** |
| 20 | `roundedrect` | `ScriptWidgetElementTagShape` | Native SwiftUI `RoundedRectangle` | `radius`, `fill`, `color` | **FULL_PARITY** |
| 21 | `icon` | `ScriptWidgetElementTagExtras` | Native SF Symbol `Image(systemName:)` | `name`, `systemName`, `size`, `color` | **FULL_PARITY** |
| 22 | `label` | `ScriptWidgetElementTagExtras` | Native SwiftUI `Label` | `title`, `icon`, `systemImage` | **FULL_PARITY** |
| 23 | `progress` | `ScriptWidgetElementTagExtras` | Native SwiftUI `ProgressView` | `value`, `total` | **FULL_PARITY** |
| 24 | `ring` | `ScriptWidgetElementTagExtras` | Native circular progress ring | `value`, `lineWidth`, `color`, `width`, `height` | **FULL_PARITY** |
| 25 | `badge` | `ScriptWidgetElementTagExtras` | Pill styled caption | `text`, `color` | **FULL_PARITY** |
| 26 | `chip` | `ScriptWidgetElementTagExtras` | Interactive chip with icon | `text`, `icon` | **FULL_PARITY** |
| 27 | `stat` | `ScriptWidgetElementTagExtras` | Metric header + value + trend | `title`, `value`, `trend` | **FULL_PARITY** |
| 28 | `button` | `ScriptWidgetElementTagButton` | SwiftUI `Button` with AppIntent | `title`, `label`, `action`, `target` | **FULL_PARITY** |
| 29 | `toggle` | `ScriptWidgetElementTagToggle` | SwiftUI `Toggle` with AppIntent | `title`, `label`, `isOn`, `target` | **FULL_PARITY** |

---

## 2. Expo Widgets Renderer Matrix

| Component Type | Native SwiftUI Representation | Supported Modifiers | Interactivity | Status |
| :--- | :--- | :--- | :--- | :--- |
| `TextView` / `Text` | SwiftUI `Text` | `font`, `fontSize`, `fontWeight`, `color` | Static | **FULL_PARITY** |
| `HStackView` / `HStack` | SwiftUI `HStack` | `spacing`, `alignment`, `padding`, `background` | Container | **FULL_PARITY** |
| `VStackView` / `VStack` | SwiftUI `VStack` | `spacing`, `alignment`, `padding`, `background` | Container | **FULL_PARITY** |
| `ZStackView` / `ZStack` | SwiftUI `ZStack` | `alignment`, `padding`, `background` | Container | **FULL_PARITY** |
| `RectangleView` | SwiftUI `Rectangle` | `fill`, `width`, `height` | Static | **FULL_PARITY** |
| `RoundedRectangleView` | SwiftUI `RoundedRectangle` | `cornerRadius`, `fill` | Static | **FULL_PARITY** |
| `CapsuleView` | SwiftUI `Capsule` | `fill`, `width`, `height` | Static | **FULL_PARITY** |
| `CircleView` | SwiftUI `Circle` | `fill`, `width`, `height` | Static | **FULL_PARITY** |
| `EllipseView` | SwiftUI `Ellipse` | `fill`, `width`, `height` | Static | **FULL_PARITY** |
| `SpacerView` | SwiftUI `Spacer` | `minLength` | Static | **FULL_PARITY** |
| `DividerView` | SwiftUI `Divider` | Standard system divider | Static | **FULL_PARITY** |
| `ImageView` | SwiftUI `Image` | SFSymbol or App Group file URI | Static | **FULL_PARITY** |
| `ProgressView` | SwiftUI `ProgressView` | `value`, `total` | Dynamic | **FULL_PARITY** |
| `GaugeView` | SwiftUI `Gauge` | `value`, `min`, `max`, `label` | Dynamic | **FULL_PARITY** |
| `ChartView` | SwiftUI `Chart` | BarMark, LineMark, PointMark | Dynamic | **FULL_PARITY** |
| `Button` / `WidgetButtonView` | SwiftUI `Button` | `title`, `systemImage`, `target` | **Interactive AppIntent** | **FULL_PARITY** |
| `LinkView` | SwiftUI `Link` | `title`, `url` | URL Navigation | **FULL_PARITY** |
| `AccessoryWidgetBackgroundView` | `AccessoryWidgetBackground` | Standard watchOS / Lock Screen background | System background | **FULL_PARITY** |
| `ScriptWidgetSubtree` | `HanlinScriptWidgetElementView` | Embedded JSX script / element tree | Mixed Tree | **FULL_PARITY** |
