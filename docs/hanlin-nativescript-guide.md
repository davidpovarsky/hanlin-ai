# מדריך לפיתוח סקריפטים ויישומונים ב-Hanlin NativeScript (מדריך לסוכן ומפתח)
# Hanlin NativeScript Agent & Developer Guide: Direct Native iOS Bridge

מדריך זה מתעד את הארכיטקטורה, התחביר, מערכת הטיפוסים וכללי הפיתוח עבור סוכני AI ומפתחים המייצרים חבילות סקריפט ויישומונים (MiniApps) עבור **Hanlin AI** הפועלים על גבי מנוע **Hanlin NativeScript**.

---

## 1. מבוא ומודל עבודה (Mental Model)

באפליקציות Hanlin מוטמע **מנוע NativeScript iOS המקורי**, עם גשר metadata למחלקות Objective-C הזמינות בבנייה. גרסאות ה־runtime, Core וחבילות הטיפוסים נקבעות יחד בזמן הכנת ה־host; קוראים את הגרסאות המדויקות מתוך `get_miniapp_sdk` עבור `nativescript`, ולא מתוך מספר גרסה ישן במדריך. מפת המקורות, הגרסאות וגבולות החיבור להרחבות נמצאת ב[מיפוי ה-SDK הקיים](miniapp-sdk/README.md). המיפוי מפריד בין הצהרת API, חיבור בקוד והוכחת הרצה במכשיר.

קיימות שתי דרכי כתיבה שניתן לשלב, בהתאם לממשקים שה-Host כולל:

בחבילה מוכנה, קובץ הכניסה הוא `nativescript/app/bundle.mjs`, ולצדו
`package.json` עם `"main":"bundle.mjs"` ו־`"hanlinRuntime":"hanlin-nativescript"`.
שמות כניסה חלופיים נדחים במפורש בייבוא ובהפעלת סשן. ה־host משתמש בכניסה יציבה מול מטמון
הגדרות החבילה של ה־runtime; אין כאן הבטחת החלפה חופשית של `main` או של כלל
הגדרות NativeScript בין חבילות. [ממצא המקור והבדיקות](miniapp-sdk/NATIVESCRIPT_RUNTIME_WIRE_2026-11-13.md).

1. **גישה ישירה מול גשר ה-iOS של ה-Runtime (Direct Native Metadata Bridge):**
   * קוד JavaScript/TypeScript ניגש למחלקות ולחתימות החשופות לגשר Objective-C של ה-Runtime. רכיבי SwiftUI משתמשים בספק SwiftUI המוטמע ובחוזה הגשר שלו.
   * ללא צורך בספריות נוספות, ביצועי Native מלאים ואינטגרציה ישירה עם פקדי מערכת ההפעלה.
2. **מעטפת `@nativescript/core` (Cross-Platform / NativeScript Core APIs):**
   * שימוש במחלקות הרשמיות של `@nativescript/core` כגון `Application`, `Page`, `Frame`, `StackLayout`, `Button`, `Label`, `Http` וכו'.
   * Core המקורי מוטמע כחלק מ־NativeScriptSharedRuntime. ב־`package.json` מצהירים על גרסת `@nativescript/core` המדויקת שב־`selectedEngine.packageVersions` של ה־SDK המותקן. אפשר לייבא את המודולים המקוריים; `build_miniapp` מכין את גרף המקור והחבילה התואמים ל־host.
   * שני המודלים מתקיימים יחד: יישומון המשתמש ב-`@nativescript/core` יכול לגשת במקביל ישירות לכל פקד או API של iOS באמצעות הגשר הישיר (לדוגמה `UIDevice`, `UIColor` וכו').

---

## 2. כללי התחביר של גשר ה-iOS (Syntax & Marshalling Rules)

מנוע ה-Runtime משתמש בהצהרות שנכללו ב-metadata של הבנייה. זמינות מחלקה וחתימה מסוימת נבדקת מול ה-Host המותקן; הרשאות מערכת והקשר ההרצה נשארים תנאי להפעלתה.

### א. יצירת אובייקטים (Class Instantiation)
מחלקות Objective-C וחתימות `@objc` שנכללו ב־metadata של ה־host חשופות דרך הגשר:
* **בנאי ברירת מחדל (`init`):**
  <!-- miniapp-snippet: ns.construction -->
  ```javascript
  const label = UILabel.new();
  // אותה פעולת init בכתיבה מפורשת:
  const explicitlyInitializedLabel = UILabel.alloc().init();
  ```
* **בנאי עם פרמטרים מותאמים אישית (`initWith...`):**
  <!-- miniapp-snippet: ns.initializers -->
  ```javascript
  const vc = UIViewController.new();
  // ב-ObjC: [[UINavigationController alloc] initWithRootViewController:vc]
  const nav = UINavigationController.alloc().initWithRootViewController(vc);

  // ב-ObjC: [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyle.Medium]
  const impact = UIImpactFeedbackGenerator.alloc().initWithStyle(UIImpactFeedbackStyle.Medium);
  ```
* **פונקציות Factory (שיטות סטטיות של מחלקה):**
  <!-- miniapp-snippet: ns.factories -->
  ```javascript
  const btn = UIButton.buttonWithType(UIButtonType.System);
  const blur = UIBlurEffect.effectWithStyle(UIBlurEffectStyle.SystemMaterial);
  const symbolImg = UIImage.systemImageNamed("sparkles");
  ```

### ב. המרת שמות פונקציות (Selectors to camelCase)
ב-Objective-C שמות פונקציות מורכבים מחלקים המופרדים בנקודתיים. ב-NativeScript כל החלקים מתחברים לשם פונקציה אחד בסגנון **camelCase**:
* ב-ObjC: `[button setTitle:@"שלום" forState:UIControlState.Normal];`
* ב-JS/TS: `button.setTitleForState("שלום", UIControlState.Normal);`
* ב-ObjC: `[stackView addArrangedSubview:myView];`
* ב-JS/TS: `stackView.addArrangedSubview(myView);`
* ב-ObjC: `[NSLayoutConstraint activateConstraints:@[c1, c2]];`
* ב-JS/TS: `NSLayoutConstraint.activateConstraints([c1, c2]);`

### ג. מאפיינים (Properties)
מאפייני Objective-C ממפים ישירות ל-Getters ו-Setters של JS:
<!-- miniapp-snippet: ns.properties -->
```javascript
const view = UIView.new();
const label = UILabel.new();
view.backgroundColor = UIColor.systemBackgroundColor;
view.layer.cornerRadius = 14;
view.translatesAutoresizingMaskIntoConstraints = false;
label.text = "תוכן בעברית";
label.numberOfLines = 0;
label.font = UIFont.preferredFontForTextStyle(UIFontTextStyleHeadline);
```

### ד. קבועים, Enums וערכי מערכת
כל ה-Enums והקבועים של אפל חשופים כמשתנים גלובליים:
* `UIButtonType.System`
* `UIControlState.Normal`
* `UILayoutConstraintAxis.Vertical`, `UILayoutConstraintAxis.Horizontal`
* `UIModalPresentationStyle.PageSheet`, `UIModalPresentationStyle.Popover`
* `UIFontTextStyleLargeTitle`, `UIFontTextStyleHeadline`, `UIFontTextStyleBody`
* `UIColor.systemBlueColor`, `UIColor.secondarySystemGroupedBackgroundColor`

### ה. מבנים גיאומטריים (C-Structs)
מבנים נפוצים של CoreGraphics ו-UIKit נתמכים ישירות:
* `CGSizeMake(width, height)`
* `CGRectMake(x, y, width, height)`
* `CGPointMake(x, y)`
* `CGAffineTransformMakeRotation(radians)`
* `CGAffineTransformMakeScale(sx, sy)`
* `CGAffineTransformIdentity`

### ו. בלוקים ו-Callbacks (Objective-C Blocks)
פונקציות חץ סטנדרטיות של JavaScript מומרות ל־Blocks של Objective-C. דוגמת הרישום משתמשת ב־Trace המקורי; הפלט מוצג כאשר קטגוריית Debug מופעלת בהגדרות Trace:
<!-- miniapp-snippet: ns.callbacks -->
```javascript
import { Trace } from '@nativescript/core';

const button = UIButton.buttonWithType(UIButtonType.System);
const heroView = UIView.new();
// שימוש ב-UIAction (הדרך המודרנית ללחיצות כפתור):
const action = UIAction.actionWithHandler(() => {
  Trace.write("הכפתור נלחץ!", Trace.categories.Debug);
});
button.addActionForControlEvents(action, UIControlEvents.TouchUpInside);

// אנימציות UIView:
UIView.animateWithDurationAnimations(0.3, () => {
  heroView.alpha = 0.5;
});
```

---

## 3. ארכיטקטורת תצוגה והגשה ל-Hanlin (The Presentation Contract)

באפליקציית Hanlin AI, מנוע ה-Host תופס את התצוגה המרכזית דרך ה-`NativeScriptEmbedder`:

<!-- miniapp-snippet: ns.presentation -->
```javascript
const rootViewController = UIViewController.new();
const embedder = NativeScriptEmbedder.sharedInstance();
if (!embedder || !embedder.delegate) {
  throw new Error("Hanlin NativeScript presenter delegate is unavailable");
}

// הגשת הבקר הראשי ישירות לתוך ה-UI של Hanlin:
embedder.delegate.presentNativeScriptApp(rootViewController);
```

### מבנה הטאבים המומלץ (UITabBarController + UINavigationController):
<!-- miniapp-snippet: ns.tabs -->
```javascript
const screen1VC = UIViewController.new();
const screen2VC = UIViewController.new();
const embedder = NativeScriptEmbedder.sharedInstance();
if (!embedder || !embedder.delegate) {
  throw new Error("Hanlin NativeScript presenter delegate is unavailable");
}

// 1. יצירת בקרים לכל מסך
const tab1Nav = UINavigationController.alloc().initWithRootViewController(screen1VC);
tab1Nav.navigationBar.prefersLargeTitles = true;
tab1Nav.tabBarItem = UITabBarItem.alloc().initWithTitleImageSelectedImage(
  "לוח בקרה",
  UIImage.systemImageNamed("gauge.with.dots.needle.bottom.50percent"),
  null
);

const tab2Nav = UINavigationController.alloc().initWithRootViewController(screen2VC);
tab2Nav.navigationBar.prefersLargeTitles = true;
tab2Nav.tabBarItem = UITabBarItem.alloc().initWithTitleImageSelectedImage(
  "הגדרות",
  UIImage.systemImageNamed("gearshape"),
  null
);

// 2. יצירת בקר הטאבים המרכזי של אפל
const tabs = UITabBarController.new();
tabs.viewControllers = NSArray.arrayWithArray([tab1Nav, tab2Nav]);
tabs.selectedIndex = 0;

// 3. הגשה ל-Hanlin
embedder.delegate.presentNativeScriptApp(tabs);
```

---

## 4. שילוב ספק SwiftUI דרך הספרייה המקורית

הספרייה המקורית @nativescript/swift-ui מגדירה את ISwiftUIProvider ואת
UIDataDriver. הדוגמה הבאה מקבלת ספק native אמיתי שה־host יצר, ורושמת אותו
לממשק המקורי. היא אינה מייצרת ספק SwiftUI או metadata מתוך הגדרת טיפוס.
המחלקה HanlinNativeScriptSwiftUIFixtureProvider משמשת את בדיקות ה־host;
אין להניח שהיא טיפוס authoring ציבורי או להוסיף הצהרה מקומית שממציאה לה API.

הפרמטר provider הוא ההקשר הדרוש לדוגמה. לאחר שה־host מספק אותו, הפונקציה
מחזירה View מקורי שאפשר לשלב ב־Page של NativeScript:

<!-- miniapp-snippet: ns.swiftui-provider -->
```typescript
import { Trace } from '@nativescript/core';
import {
  registerSwiftUI, SwiftUI, UIDataDriver,
  type ISwiftUIProvider, type SwiftUIEventData
} from '@nativescript/swift-ui';

export function makeSwiftUIView(provider: ISwiftUIProvider) {
  registerSwiftUI('provided-native-view', view => new UIDataDriver(provider, view));
  const view = new SwiftUI<{count: number}, {title: string}>();
  view.swiftId = 'provided-native-view';
  view.updateData({title: 'כותרת חדשה מ-JS'});
  view.on(SwiftUI.swiftUIEventEvent, (event: SwiftUIEventData<{count: number}>) => {
    Trace.write('אירוע התקבל מ-SwiftUI: ' + event.data.count, Trace.categories.Debug);
  });
  return view;
}
```

---

## 5. תמיכה ב-TypeScript ומערכת טיפוסים (Type Declarations)

כדי לקבל השלמה אוטומטית (IntelliSense) ובדיקת שגיאות סטטית של ממשקי iOS ש־NativeScript מפרסם, משתמשים בחבילת הטיפוסים המקורית הכלולה ב־SDK המותקן. הצהרה אינה מוסיפה מימוש native ל־host, ואין כאן הרחבה של מחולל Apple SDK עצמאי:
* חבילת NPM: **`@nativescript/types-ios`**

### הגדרת `tsconfig.json`:

ב־validate_miniapp וב־CLI המשותף, הגדרות ה־SDK המקוריות מצטרפות אוטומטית
להגדרות הפרויקט. הדוגמה מפעילה גם בדיקה סמנטית של קובצי JavaScript. היא אינה
משנה את מדיניות NativeScript המקורית: המקור נבדק ב־strict, וגופי קובצי ההצהרות
אינם נבדקים מחדש (skipLibCheck של ה־SDK). לעורך או tsc חיצוני מגדירים extends
לנתיב tsconfig המדויק שהוחזר עם ה־SDK, לצד נתיבי המודולים המקוריים שלו.
<!-- miniapp-snippet: ns.tsconfig -->
```json
{
  "compilerOptions": {
    "strict": true,
    "allowJs": true,
    "checkJs": true,
    "moduleDetection": "force"
  },
  "include": [
    "src/**/*"
  ]
}
```

---

## 6. מבנה החבילה והקבצים (Package Directory Structure)

לכתיבה ותיקון משתמשים ב־[תהליך ה־authoring המשותף](miniapp-sdk/AUTHORING_WORKFLOW.md): המקור ו־`hanlin.authoring.json` נבדקים עם הקומפיילר המקורי, ו־`build_miniapp` מפיק את המבנה המוכן להלן יחד עם `source/` לעריכה חוזרת. אין צורך לייצר ידנית את המטא־דאטה של חבילה מוכנה.

חבילת יישומון מוכנה לייבוא ב-Hanlin AI צריכה להכיל את הקבצים הבאים:

<!-- miniapp-snippet: ns.layout -->
```
my-miniapp/
├── script.json
└── nativescript/
    └── app/
        ├── package.json
        └── bundle.mjs
```

### א. `script.json` (שורש החבילה)
<!-- miniapp-snippet: ns.script -->
```json
{
  "name": "Hanlin iPadOS System UI Gallery",
  "version": "1.0.0",
  "description": "יישומוני טאבים מקוריים של UIKit הפועל ישירות מעל Hanlin NativeScript.",
  "entry": "nativescript/app/bundle.mjs",
  "runInApp": true,
  "hanlinRuntime": "hanlin-nativescript",
  "icon": "sparkles",
  "color": "#007AFF"
}
```

### ב. `nativescript/app/package.json`
<!-- miniapp-snippet: ns.package -->
```json
{
  "name": "hanlin-ipados-system-ui-gallery",
  "version": "1.0.0",
  "main": "bundle.mjs",
  "hanlinRuntime": "hanlin-nativescript"
}
```

### ג. אריזה לארכיון (Packaging)
את התיקייה מאגדים לקובץ ZIP בעל סיומת `.hanlinNativeScript` או `.scripting` (או `.zip`), תוך הקפדה על נתיבי POSIX קדמיים (`/`).

---

## 7. קישורים ומקורות תיעוד רשמיים (Official Documentation Links)

### תיעוד ה-Runtime של NativeScript (Accessing Native APIs):
1. **[NativeScript iOS Runtime Marshalling Overview](https://docs.nativescript.org/plugins/ios-runtime/marshalling/marshalling-overview)**
   הסבר מקיף על מיפוי טיפוסים בין JavaScript ל-Objective-C, כולל מחרוזות, מערכים, מילונים, מספרים ו-null.
2. **[Objective-C Method Calling Conventions in NativeScript](https://docs.nativescript.org/plugins/ios-runtime/how-to/ObjC-Subclassing)**
   הכללים המדויקים להמרת סלקטורים (Selectors) של אפל לפונקציות camelCase ב-JavaScript.
3. **[Types for iOS on NPM (`@nativescript/types-ios`)](https://www.npmjs.com/package/@nativescript/types-ios)**
   חבילת הטיפוסים המקורית של NativeScript לממשקי iOS; הגרסה והקבצים בפועל נמסרים ב־SDK של ה־host.
4. **[NativeScript iOS Runtime GitHub Repository](https://github.com/NativeScript/ios-runtime)**
   קוד המקור של מנוע ה-Runtime של NativeScript ל-iOS.

### תיעוד רשמי של Apple (Apple Developer Documentation):
כל רכיב UIKit ו-Foundation מבוסס במדויק על התיעוד הרשמי של אפל:
1. **[Apple UIKit Framework](https://developer.apple.com/documentation/uikit)** – דף הבית של רכיבי ממשק המשתמש ב-iOS.
2. **[UITabBarController](https://developer.apple.com/documentation/uikit/uitabbarcontroller)** – ניהול סרגלי טאבים ומעבר בין מסכים.
3. **[UINavigationController](https://developer.apple.com/documentation/uikit/uinavigationcontroller)** – ניהול מחסנית ניווט וכותרות עליונות גדולות.
4. **[UIViewController](https://developer.apple.com/documentation/uikit/uiviewcontroller)** – ניהול מחזור חיי תצוגה (`viewDidLoad`, `viewWillAppear`).
5. **[NSLayoutConstraint & Auto Layout](https://developer.apple.com/documentation/uikit/nslayoutconstraint)** – הגדרת אילוצי מיקום וגודל ברמת קוד.
6. **[UIFeedbackGenerator & Haptics](https://developer.apple.com/documentation/uikit/uifeedbackgenerator)** – הפעלת מנוע הרטט Taptic Engine במכשיר.
7. **[UIAction](https://developer.apple.com/documentation/uikit/uiaction)** – תגובה לאירועי משתמש בכפתורים ובקרים.
8. **[UIHostingController](https://developer.apple.com/documentation/swiftui/uihostingcontroller)** – הטמעת תצוגות SwiftUI בתוך היררכיית UIKit.
