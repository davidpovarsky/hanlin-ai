# Task 10 original drawing and image handoff

Source base: e641105fdc7ac5b418c49b9a146c96cfccf0f078.
This checkpoint adds original-engine code, one source-gallery project and native regressions. It does not claim native drawing execution.

## Audit and implementation

The live ScriptWidget renderer already used SwiftUI rotationEffect around the default center. Its ImageIO pipeline already limited encoded input to 8 MiB, source images to 16 million pixels, default output thumbnails to 1024 pixels, and its NSCache to 24 MiB. These capabilities were not absent.

The actual gaps were numeric validation: square frame values rejected non-finite/negative dimensions, while two- and three-component frames did not; image aspect ratios and rotation values also passed invalid numbers to SwiftUI. The existing modifiers now apply consistent finite/nonnegative frame validation, positive finite ratios and finite rotations. Center anchoring is explicit. Ordinary valid original rendering remains on the original code path.

The new nativescript-image-drawing gallery project uses existing original NativeScript UIKit metadata: UIGraphicsImageRenderer, UIImage, CGContextTranslateCTM, CGContextRotateCTM and ImageSource. It renders a red/blue asymmetric image into a transparent canvas and rotates clockwise around the destination rectangle's center. Validation occurs before the native allocation. The source includes eight real invalid-input checks and verifies the native output dimensions when the app actually launches. NativeScript Trace emits the actual receipt; there is no console ambient shim.

No Expo module was added. Expo ImageManipulator's presence in upstream documentation was not treated as evidence it is embedded here. The frozen scripting Canvas declarations were not used.

## Executed verification

- Swift syntax parse: three original modifiers and the new native image test source PASS, Oracle Swift 6.4.3.
- Original installed TypeScript 5.9.3 and original NativeScript declarations: strict sample source check PASS with zero diagnostics, job_b9bc0b04b095. Actual packages in that existing recovery installation are core/types/types-ios 9.1.0. This is preliminary source compatibility, not the pending fresh combined SDK 9.1.4 graph or native runtime acceptance.
- Focused real SDK documentation/example copy test: 1 PASS, job_47a7cc4e37b5. It copies all five actual projects and verifies exact source bytes, authored resources, output exclusions and engine filtering. No unrelated SDK tests were rerun.
- Native tests and sample launch: NOT_RUN in this lane.

## Required native selection

HanlinScriptExtensionsTests/HanlinOriginalScriptWidgetImageTests: 4 definitions / 9 cases:
- imageRotationKeepsTheOriginalSwiftUICenter: 4 angles (0, 45, 90, 180), actual PNG comparison with the corresponding native SwiftUI image transform.
- invalidImageDimensionsAndTransformsNeverReachSwiftUI: 3 attribute groups (frame/rotation/ratio), 19 invalid input assertions inside those groups.
- largeValidImagesUseTheOriginalBoundedDownsampler: 1 case, real 3072×2048 encoded source downsampled to at most 1024 pixels.
- oversizedAndMalformedImagesAreRejectedBeforeDisplay: 1 case, real compressed 4097×4097 image, oversized encoded bytes and malformed image data.

These changed common modifiers affect existing original ScriptWidget image/general rendering. Preserve the original native baseline and apply the dependency-aware gate; do not count a source parse as a raster pass. If HANLIN_WIDGET_EVIDENCE_DIR is set, the four center-rotation PNGs are saved there.

## Gallery end-to-end acceptance

The native preparation owner must stage the fifth SDK example from the exact integrated source, then run its canonical original authoring validate/build against the fresh locked graph. In standalone Developer Studio, copy Native Image Drawing, edit its independent source, build/import, launch it, and tap Rotate image through all four angles. Capture actual screenshots and the original runtime Trace receipt with scenario miniapps-native-drawing, rejectedInputs 8, width 128, height 128. Source constants or an expected JSON object are not a receipt.

## Primary references

- https://scriptable.app/docs/reference/drawcontext/
- https://developer.apple.com/documentation/uikit/uigraphicsimagerenderer
- https://docs.nativescript.org/core/image-source
- https://docs.nativescript.org/ui/image

Public API declarations were additionally read from the original installed @nativescript/types-ios UIKit definitions before authoring the sample. The current Mac SDK remains iOS 27.0; no iOS 27.2 execution is claimed.
