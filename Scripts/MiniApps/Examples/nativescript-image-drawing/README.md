# Native Image Drawing

An editable MiniApps gallery project using the original NativeScript Core and its existing public iOS metadata bridge.

The app renders an asymmetric red/blue image with UIKit UIGraphicsImageRenderer and rotates it clockwise around a destination rectangle's center using CGContextTranslateCTM and CGContextRotateCTM. The output retains a transparent 128×128 canvas. The Rotate image button cycles through 0°, 45°, 90° and 180°.

The example validates finite positions/angles, positive output and rectangle dimensions, and a 16-million-pixel allocation budget before entering UIKit. On launch, checkNativeDrawing exercises eight invalid input cases and a real 90° native render. Its receipt appears in the original runtime log as scenario miniapps-native-drawing. A successful TypeScript build is not proof this native scenario ran.

## Use

Copy this project from Developer Studio's Example Gallery. Edit drawing.ts or index.ts, validate, build, complete the existing package import flow and launch the installed copy. Source copies remain independent from the SDK example. Screenshots for the four angles plus the actual log receipt form the native acceptance evidence.

## Public original APIs

- https://docs.nativescript.org/core/image-source
- https://docs.nativescript.org/ui/image
- https://developer.apple.com/documentation/uikit/uigraphicsimagerenderer
- https://scriptable.app/docs/reference/drawcontext/ (feature comparison only)

No Scriptable runtime, new Expo module or frozen Hanlin Canvas implementation is used. ScriptWidget images already use the original bounded ImageIO pipeline; that separate engine has its own native raster tests.
