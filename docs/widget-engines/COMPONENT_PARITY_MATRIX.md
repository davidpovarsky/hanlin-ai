> Pass 3, observed 2026-10-31: original native builders are source-ported and Apple compiled. Run 41239674500 at 5bfcf03b executes originalTagProducesDistinctNativeRaster for all 29 tags, originalChartVariantUsesItsNativeDataSchema for ten charts and gridColumnsDateAndNativeElementSemantics. Raw native PNGs are in its widget-package artifact. This is PARTIAL semantic coverage, not complete per-prop, WidgetKit, RTL or Dynamic Type parity. Mixed-tree is DEFERRED_OPTIONAL.

# Component Parity Matrix — Dual Native Widget Engines

## 1. ScriptWidget 29 Native Tags Matrix

| # | Tag Name | Upstream Implementation | Hanlin Native Implementation | Supported Attributes & Props | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `hstack` | `ScriptWidgetElementTagStack` | `HStack` with alignment & spacing | `alignment`, `spacing`, `padding`, `background` | **PARTIAL** |
| 2 | `vstack` | `ScriptWidgetElementTagStack` | `VStack` with alignment & spacing | `alignment`, `spacing`, `padding`, `background` | **PARTIAL** |
| 3 | `zstack` | `ScriptWidgetElementTagZStack` | Original centered `ZStack` with authored child draw order | general `frame` alignment, `padding`, `background` | **PARTIAL** |
| 4 | `hgrid` | `ScriptWidgetElementTagGrid` | `LazyHGrid` with dynamic GridItems | `columns` (JSON grid descriptors), `spacing`, `padding` | **PARTIAL** |
| 5 | `vgrid` | `ScriptWidgetElementTagGrid` | `LazyVGrid` with dynamic GridItems | `columns`, `spacing`, `padding` | **PARTIAL** |
| 6 | `text` | `ScriptWidgetElementTagText` | Native SwiftUI `Text` | `font`, `fontWeight`/`weight`, `fontDesign`, `color`, `alignment` | **PARTIAL** |
| 7 | `date` | `ScriptWidgetElementTagDate` | Native SwiftUI `Text(date, style:)` | `date` (name or milliseconds), `style` (date/time/relative/offset/timer) | **PARTIAL** |
| 8 | `image` | `ScriptWidgetElementTagImage` | SFSymbol / Local UIImage | `systemName`, `name`, `src`, `url`, `color` | **PARTIAL** |
| 9 | `gif` | `ScriptWidgetElementTagGif` | Original GIF frame pipeline | `file`, image/general modifiers | **PARTIAL** |
| 10 | `spacer` | `ScriptWidgetElementTagSpacer` | Native SwiftUI `Spacer` | `frame` (original Spacer has no minLength prop) | **PARTIAL** |
| 11 | `rect` | `ScriptWidgetElementTagShape` | Native SwiftUI `Rectangle` | `color`, `frame`, `stroke`, `trim` | **PARTIAL** |
| 12 | `capsule` | `ScriptWidgetElementTagShape` | Native SwiftUI `Capsule` | `color`, `frame`, `stroke`, `trim` | **PARTIAL** |
| 13 | `ellipse` | `ScriptWidgetElementTagShape` | Native SwiftUI `Ellipse` | `color`, `frame`, `stroke`, `trim` | **PARTIAL** |
| 14 | `circle` | `ScriptWidgetElementTagShape` | Native SwiftUI `Circle` | `color`, `frame`, `stroke`, `trim` | **PARTIAL** |
| 15 | `gauge` | `ScriptWidgetElementTagGauge` | Original MineGaugeView / native SwiftUI `Gauge` | `type`, `style`, `value`, `current`, `min`, `max`, `sections`, `label`, `title` | **PARTIAL** |
| 16 | `chart` | `ScriptWidgetElementTagChart` | Native SwiftUI `Chart` (Bar/Line/Point) | `type`, JSON-string `data: [{label, value}]`; Gantt and rule schemas differ | **PARTIAL** |
| 17 | `link` | `ScriptWidgetElementTagLink` | Native SwiftUI `Link` | `title`, `url` | **PARTIAL** |
| 18 | `divider` | `ScriptWidgetElementTagDivider` | Native SwiftUI `Rectangle` | `axis`, `thickness`, `color` | **PARTIAL** |
| 19 | `line` | `ScriptWidgetElementTagLine` | Native sized `Rectangle` | `axis`, `length`, `thickness`, `color` | **PARTIAL** |
| 20 | `roundedrect` | `ScriptWidgetElementTagRoundedRect` | Native SwiftUI `RoundedRectangle` | `radius`, `color`, `frame` | **PARTIAL** |
| 21 | `icon` | `ScriptWidgetElementTagExtras` | Native SF Symbol `Image(systemName:)` | `name`, `systemName`, `size`, `color` | **PARTIAL** |
| 22 | `label` | `ScriptWidgetElementTagExtras` | Native SwiftUI `Label` | `title`, `systemName` | **PARTIAL** |
| 23 | `progress` | `ScriptWidgetElementTagExtras` | Native SwiftUI `ProgressView` | `value`, `total` | **PARTIAL** |
| 24 | `ring` | `ScriptWidgetElementTagExtras` | Native circular progress ring | `value`, `thickness`, `color`, `trackColor`, `frame` | **PARTIAL** |
| 25 | `badge` | `ScriptWidgetElementTagExtras` | Pill styled caption | `text`, `color` | **PARTIAL** |
| 26 | `chip` | `ScriptWidgetElementTagExtras` | Original styled chip text | `text`, `borderColor`, `radius`, `background` | **PARTIAL** |
| 27 | `stat` | `ScriptWidgetElementTagExtras` | Metric header + value + trend | `title`, `value`, `subtitle`, `color`, `mutedColor` | **PARTIAL** |
| 28 | `button` | `ScriptWidgetElementTagButton` | SwiftUI `Button` with AppIntent | native child labels; `onClick`, declared `actionID` | **PARTIAL** |
| 29 | `toggle` | `ScriptWidgetElementTagToggle` | SwiftUI `Toggle` with AppIntent | native child labels; `on` Bool, declared `actionID`, `stateKey`, `onClick` | **PARTIAL** |

---

## 2. Expo Widgets Renderer Matrix

| Component Type | Native SwiftUI Representation | Original props / modifier path | Interactivity | Status |
| :--- | :--- | :--- | :--- | :--- |
| `TextView` / `Text` | Original native SwiftUI `Text` with nested styles/slots | original `font` and common modifiers | Static | **PARTIAL — native concatenation/style pixel reference PASS** |
| `HStackView` / `HStack` | SwiftUI `HStack` | `spacing`, `alignment`, `padding`, `background` | Container | **NOT_TESTED** |
| `VStackView` / `VStack` | SwiftUI `VStack` | `spacing`, `alignment`, `padding`, `background` | Container | **NOT_TESTED** |
| `ZStackView` / `ZStack` | SwiftUI `ZStack` | `alignment`, `padding`, `background` | Container | **NOT_TESTED** |
| `RectangleView` | SwiftUI `Rectangle` | original common modifiers, including foregroundColor/frame | Static | **NOT_TESTED** |
| `RoundedRectangleView` | SwiftUI `RoundedRectangle` | `cornerRadius`; common modifiers | Static | **NOT_TESTED** |
| `CapsuleView` | SwiftUI `Capsule` | `cornerStyle`; common modifiers | Static | **NOT_TESTED** |
| `CircleView` | SwiftUI `Circle` | common modifiers | Static | **NOT_TESTED** |
| `EllipseView` | SwiftUI `Ellipse` | common modifiers | Static | **NOT_TESTED** |
| `SpacerView` | SwiftUI `Spacer` | `minLength` | Static | **NOT_TESTED** |
| `DividerView` | SwiftUI `Divider` | Standard system divider | Static | **NOT_TESTED** |
| `ImageView` | SwiftUI `Image` | `systemName`/`variableValue`, verified `assetName`/`uiImage`; original image/common modifiers | Static | **NOT_TESTED** |
| `LabelView` | SwiftUI `Label` with original title/icon slots | prepared `children` slots | Static | **PARTIAL — original title slot pixel reference PASS** |
| `ProgressView` | SwiftUI `ProgressView` with prepared child label | `value`, `children` | Dynamic | **PARTIAL — original label/value pixel reference PASS** |
| `GaugeView` | SwiftUI `Gauge` | `value`, `min`, `max`, current/label/minimum/maximum slots | Dynamic | **PARTIAL — typed data/currentValue and invalid-range diagnostic PASS** |
| `ChartView` | Original native SwiftUI `Chart` | original typed data and mark enum | Dynamic | **PARTIAL — original typed bar data PASS** |
| `Button` / `WidgetButtonView` | SwiftUI `Button` | `label` or native children, `systemImage`, `target`, `role` | **Interactive AppIntent** | **NOT_TESTED** |
| `LinkView` | SwiftUI `Link` | `label` or native children, `destination` | URL Navigation | **NOT_TESTED** |
| `AccessoryWidgetBackgroundView` | `AccessoryWidgetBackground` source component | No accessory families are registered by Hanlin's generic widget | Source component only | **NOT_REGISTERED — no accessory-family acceptance claim** |
| `ScriptWidgetSubtree` | No supported mixed-tree ABI | Explicitly rejected ABI-0 fixture | Optional | **DEFERRED_OPTIONAL** |

All five original iOS renderer methods passed in 41261389588 at 6e3e7f54, including repaired Gauge/Label/Progress children. Text/overlay/background/mask/Label/Progress tests compare exact native PNG references; Chart/Gauge inspect original typed props and children. Other rows remain NOT_TESTED for their own assertions. The next exact method testOriginalShapesStacksImagesLinksAndModifiersMatchNativeReferences covers 17 inputs in LTR/standard and RTL/accessibility3: shapes, stacks/alignment/spacing/flattening, spacer, divider, SF symbol, verified image asset, Link label/children, injected Button target/role/label and ordered modifiers. Its two earlier builds stopped at unrelated test teardown isolation; corrected run 41267448297 is pending. No pixel-reference pass or OS interaction is inferred before execution.

A new test-only follow-up at 76e6b938 exercises all 29 tags with changed semantic inputs: stack spacing, ZStack draw order, grid column/row count, text/date labels, two actual resource PNG/GIF colors, framed Spacer layout, shape colors, gauge/chart/progress/ring values, Link/Button labels, divider orientation, line length, SF symbols, label/badge/chip/stat content and declared Toggle Boolean state. It also records the installed ScriptWidget Dashboard/Actions and legacy archives through their actual native builders. The first run 41261944370 failed four cases. Corrected frozen numeric bridging and Text input then passed all 29 in 41262728948, and all passed again in 41263527148 at 23ee9f15. These are EXECUTED_PASS for the specific semantic dimensions listed, not blanket per-attribute/RTL/Dynamic Type/WidgetKit parity.

Run 41305235263 at e020ee11 also passes all six original-native methods after the narrow Gauge numeric/section guards: twelve invalid-input diagnostic pixel references and valid original Gauge needle images join the existing 29 semantic input pairs and ten chart variants. The original valid builder is retained; this does not assert that WidgetKit continuously animates Gauge/GIF/clock content.

## Latest scoped evidence — 2026-11-01

Run 41304461973 passes the two added iOS native renderer methods: 17 references in both LTR and RTL/accessibility, and raw/tagged/date wire through publication and source action. Its three SpringBoard widget methods failed before native actions. Original Gauge guards have package PASS in 41305235263. Full per-component/device parity is not inferred. The owner requested TestFlight delivery for iPad QA.
