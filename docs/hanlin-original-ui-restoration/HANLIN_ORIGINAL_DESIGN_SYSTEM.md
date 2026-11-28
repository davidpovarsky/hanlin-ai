# Hanlin Original Design System (`478cdd2c23ae2b1a52044cff52ce720830128ea2`)

Extracted directly from `AI_HLY/Assets.xcassets/**/*.colorset/Contents.json` and the five original source files (`ChatView.swift`, `ChatViewComponents.swift`, `ChatViewBottom.swift`, `ChatandFile.swift`, `ListView.swift`) at commit `478cdd2c23ae2b1a52044cff52ce720830128ea2`.

---

## 1. Authentic Color Assets (`AI_HLY/Assets.xcassets`, Display P3)

All Hanlin semantic colors are defined in `Display P3` color space with explicit Light (`universal`) and Dark (`luminosity: dark`) appearances:

| Asset Name | SwiftUI Symbol | Light Appearance (Display P3 Hex) | Dark Appearance (Display P3 Hex) | Primary Semantic Usage in Original UI |
|---|---|---|---|---|
| `AccentColor` | `.accentColor` | `#3A7CB4` (`R:0x3A G:0x7C B:0xB4`) | `#7EB2E6` (`R:0x7E G:0xB2 B:0xE6`) | Global app tint |
| `HLBlue` | `Color.hlBlue` / `Color(.hlBlue)` | `#3A7CB4` (`R:0x3A G:0x7C B:0xB4`) | `#3A7CB4` (`R:0x3A G:0x7C B:0xB4`) | Normal user message bubble fill (`Color.hlBlue`), search capsule outline, `ChatViewBottom` `GlassView` drop shadow (`Color.hlBlue.opacity(0.25)`), attachment card tints (`Color.hlBlue.opacity(0.1)`) |
| `HLBluefont` | `Color.hlBluefont` / `Color(.hlBluefont)` | `#3A7CB4` (`R:0x3A G:0x7C B:0xB4`) | `#7EB2E6` (`R:0x7E G:0xB2 B:0xE6`) | Primary interactive blue foreground for text/icons in both light & dark modes: `LoadingGradientText`, `ToggleButton` active state, `sendButtonColor`, selected model capsule text/background (`Color(.hlBluefont).opacity(0.1)`), knowledge backpack active tint |
| `HLAzure` | `Color.hlAzure` / `Color(.hlAzure)` | `#0288D1` (`R:0x02 G:0x88 B:0xD1`) | `#5ABFF0` (`R:0x5A G:0xBF B:0xF0`) | Online web search (`network` / `联网搜索`) toggle active foreground & background (`Color(.hlAzure).opacity(0.1)`) |
| `HLCyanite` | `Color.hlCyanite` | `#5E9BAF` (`R:0x5E G:0x9B B:0xAF`) | `#86C4D7` (`R:0x86 G:0xC4 B:0xD7`) | Secondary cyan-blue accent |
| `HLNavy` | `Color.hlNavy` | `#2C3E50` (`R:0x2C G:0x3E B:0x50`) | `#60788C` (`R:0x60 G:0x78 B:0x8C`) | Deep navy structural accent |
| `HLGray` | `Color.hlGray` | `#555B6E` (`R:0x55 G:0x5B B:0x6E`) | `#9CA3AF` (`R:0x9C G:0xA3 B:0xAF`) | Muted neutral icon/border accent |
| `HLBrown` | `Color.hlBrown` | `#8C756B` (`R:0x8C G:0x75 B:0x6B`) | `#B79D92` (`R:0xB7 G:0x9D B:0x92`) | Tool use (`hammer.circle` / `工具`) badge and toggle tint (`Color(.hlBrown).opacity(0.1)`) |
| `HLPurple` | `Color.hlPurple` | `#7560A3` (`R:0x75 G:0x60 B:0xA3`) | `#A48FCF` (`R:0xA4 G:0x8F B:0xCF`) | Reasoning (`lightbulb.circle` / `思考` / `深度思考`) badge and toggle tint |
| `HLIndigo` | `Color.hlIndigo` | `#5C6BC0` (`R:0x5C G:0x6B B:0xC0`) | `#9FA8DA` (`R:0x9F G:0xA8 B:0xDA`) | Planning (`location.circle` / `规划执行`) toggle tint |
| `HLTeal` | `Color.hlTeal` | `#00BFA5` (`R:0x00 G:0xBF B:0xA5`) | `#5BE0CC` (`R:0x5B G:0xE0 B:0xCC`) | Multimodal vision (`视觉`) capability badge tint |
| `HLGreen` | `Color.hlGreen` | `#4A9978` (`R:0x4A G:0x99 B:0x78`) | `#71C1A0` (`R:0x71 G:0xC1 B:0xA0`) | Copy confirmation (`checkmark.circle` / `已复制`), image generation (`camera.aperture` / `生图`), prompt edit button |
| `HLOrange` | `Color.hlOrange` | `#D67F3A` (`R:0xD6 G:0x7F B:0x3A`) | `#E1A76C` (`R:0xE1 G:0xA7 B:0x6C`) | On-device `LOCAL` model (`lock.circle` / `本地`) badge and toggle tint |
| `HLPink` | `Color.hlPink` | `#D86A9C` (`R:0xD8 G:0x6A B:0x9C`) | `#ED9CC0` (`R:0xED G:0x9C B:0xC0`) | Audio/voice generation (`waveform.circle` / `语音`) badge and toggle tint |
| `HLRed` | `Color.hlRed` | `#C54F4F` (`R:0xC5 G:0x4F B:0x4F`) | `#CF6565` (`R:0xCF G:0x65 B:0x65`) | Stop generation (`stop.circle.fill`), attachment remove (`xmark.circle.fill`), rotated plus close button, error capsule |

---

## 2. Materials, Corners, Shadows & Typography

### 2.1 Bottom Composer Shell (`ChatViewBottom.swift`)
- **Material**: `GlassView(style: .systemUltraThinMaterial)` clipped to `CustomCorners(tl: 20, tr: 20, bl: 30, br: 30)`.
- **Outer Shadow**: `.shadow(color: TemporaryRecord ? Color.primary.opacity(0.25) : Color.hlBlue.opacity(0.25), radius: 6, x: 0, y: 0)`.
- **Inner Composer Field Card**: `.background(.background.opacity(0.6))` with `.cornerRadius(20)`.
- **Floating Action Pills** (`画布` & Scroll-to-Bottom `arrow.down`): `BlurView(style: .systemUltraThinMaterial)` with `Capsule()` clip and `1pt` stroke `TemporaryRecord ? Color.primary : Color.hlBlue`.

### 2.2 Ordinary Chat Bubbles (`ChatViewComponents.swift`)
- **User Bubble (`userMessageView`)**:
  - Background: `TemporaryRecord ? Color.primary : Color.hlBlue`
  - Text color: `TemporaryRecord ? Color(.systemBackground) : .white`
  - Shape: `RoundedRectangle(cornerRadius: 20)`
- **Search Bubble (`searchMessageView`)**:
  - Background: `Color(.systemBackground)`
  - Border: `Capsule().stroke(temporaryRecord ? Color.primary : Color.hlBlue, lineWidth: 1)`
- **Foldable Reasoning / Tool / Audio / Translate / Reference Headers (`ToggleButton`)**:
  - Font: `.font(.footnote)`
  - Active color: `isExpanded ? .hlBluefont : .secondary`
- **Rich Embedded Cards (`CodeBlockRow`, `WebContentPreviewView`, `CanvasCardView`, `ChatEmbeddedResultHost`)**:
  - Background: `Color(.secondarySystemBackground)` / `Color(.systemBackground)` with `Color.hlBlue.opacity(0.06...0.18)` header/border accents and `RoundedRectangle(cornerRadius: 14...20)`.
- **Dynamic Type Scaling**:
  - Uses `@ScaledMetric(relativeTo: .body)` across `ChatBubbleView` (`size_5` through `size_60`) and `ChatViewBottom` (`size_16`, `size_20`, `size_30`, `size_32`, `size_40`, `size_44`, `size_80`).

---

## 3. Cross-Screen Adoption Guidelines for New Panels

When styling embedded or auxiliary surfaces (`ChatEmbeddedResultHost`, `NativeUIRenderer`, Runtime/MCP/Skills sheets):
1. **Never invent orange/gray chat shells**: Always use `Color.hlBlue` / `Color.hlBluefont` for primary borders, active icons, and capsule highlights, switching to `Color.primary` only when `TemporaryRecord == true`.
2. **Use `GlassView(style: .systemUltraThinMaterial)` or `Color.hlBlue.opacity(0.1)`**: Match the original capsule/rounded-rectangle geometry (`cornerRadius: 14...20`).
3. **Interactive Embedded Results (`ChatEmbeddedResultHost`)**: Uses `Color.hlBlue.opacity(0.08)` header fill, `Color.hlBluefont` icon/action pills, and `Color.hlBlue.opacity(0.18)` `1pt` border stroke so interactive `NativeScript` / `Svelte` / `WebView` mini-apps visually belong to the original Hanlin family.
