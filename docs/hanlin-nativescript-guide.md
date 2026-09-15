# מדריך לפיתוח סקריפטים ויישומונים ב-Hanlin NativeScript (מדריך לסוכן ומפתח)
# Hanlin NativeScript Agent & Developer Guide: Direct Native iOS Bridge

מדריך זה מתעד את הארכיטקטורה, התחביר, מערכת הטיפוסים וכללי הפיתוח עבור סוכני AI ומפתחים המייצרים חבילות סקריפט ויישומונים (MiniApps) עבור **Hanlin AI** הפועלים על גבי מנוע **Hanlin NativeScript**.

---

## 1. מבוא ומודל עבודה (Mental Model)

באפליקציית Hanlin AI מוטמע מנוע ריצה מקורי של **NativeScript iOS Runtime** (הכתוב ב-C++ ו-Objective-C ומבוסס על מנוע JavaScriptCore / V8).

קיימות שתי דרכים עקרוניות לכתוב קוד NativeScript (ושניהן נתמכות במלואן ב-Hanlin AI וניתנות לשילוב):
1. **גישה ישירה מול גשר ה-iOS של ה-Runtime (Direct Native Metadata Bridge):**
   * קוד ה-JavaScript/TypeScript מדבר **ישירות** עם כל מחלקות ה-SDK של אפל (`UIKit`, `Foundation`, `CoreGraphics`, `SwiftUI`).
   * ללא צורך בספריות נוספות, ביצועי Native מלאים ואינטגרציה ישירה עם פקדי מערכת ההפעלה.
2. **מעטפת `@nativescript/core` (Cross-Platform / NativeScript Core APIs):**
   * שימוש במחלקות הרשמיות של `@nativescript/core` כגון `Application`, `Page`, `Frame`, `StackLayout`, `Button`, `Label`, `Http` וכו'.
   * גרסה `9.1.0` מוטמעת מראש כחלק מ-Runtime של Hanlin (NativeScriptSharedRuntime); יישומונים מצהירים על `"@nativescript/core": "9.1.0"` ב-`package.json` ויכולים לייבא את המודולים כרגיל ללא צורך בהתקנת npm מקומית או bundling ידני.
   * שני המודלים מתקיימים יחד: יישומון המשתמש ב-`@nativescript/core` יכול לגשת במקביל ישירות לכל פקד או API של iOS באמצעות הגשר הישיר (לדוגמה `UIDevice`, `UIColor` וכו').

---

## 2. כללי התחביר של גשר ה-iOS (Syntax & Marshalling Rules)

מנוע ה-Runtime סורק את כל ה-Metadata של ה-SDK של אפל וממפה אותו לשפת JavaScript/TypeScript ביחס של 1:1.

### א. יצירת אובייקטים (Class Instantiation)
כל מחלקת Objective-C / Swift עם `@objc` זמינה כמשתנה גלובלי:
* **בנאי ברירת מחדל (`init`):**
  ```javascript
  const label = UILabel.new();
  // או:
  const label = UILabel.alloc().init();
  ```
* **בנאי עם פרמטרים מותאמים אישית (`initWith...`):**
  ```javascript
  // ב-ObjC: [[UINavigationController alloc] initWithRootViewController:vc]
  const nav = UINavigationController.alloc().initWithRootViewController(vc);

  // ב-ObjC: [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium]
  const impact = UIImpactFeedbackGenerator.alloc().initWithStyle(UIImpactFeedbackStyleMedium);
  ```
* **פונקציות Factory (שיטות סטטיות של מחלקה):**
  ```javascript
  const btn = UIButton.buttonWithType(UIButtonTypeSystem);
  const blur = UIBlurEffect.effectWithStyle(UIBlurEffectStyleSystemMaterial);
  const symbolImg = UIImage.systemImageNamed("sparkles");
  ```

### ב. המרת שמות פונקציות (Selectors to camelCase)
ב-Objective-C שמות פונקציות מורכבים מחלקים המופרדים בנקודתיים. ב-NativeScript כל החלקים מתחברים לשם פונקציה אחד בסגנון **camelCase**:
* ב-ObjC: `[button setTitle:@"שלום" forState:UIControlStateNormal];`
* ב-JS/TS: `button.setTitleForState("שלום", UIControlStateNormal);`
* ב-ObjC: `[stackView addArrangedSubview:myView];`
* ב-JS/TS: `stackView.addArrangedSubview(myView);`
* ב-ObjC: `[NSLayoutConstraint activateConstraints:@[c1, c2]];`
* ב-JS/TS: `NSLayoutConstraint.activateConstraints([c1, c2]);`

### ג. מאפיינים (Properties)
מאפייני Objective-C ממפים ישירות ל-Getters ו-Setters של JS:
```javascript
view.backgroundColor = UIColor.systemBackgroundColor;
view.layer.cornerRadius = 14;
view.translatesAutoresizingMaskIntoConstraints = false;
label.text = "תוכן בעברית";
label.numberOfLines = 0;
label.font = UIFont.preferredFontForTextStyle(UIFontTextStyleHeadline);
```

### ד. קבועים, Enums וערכי מערכת
כל ה-Enums והקבועים של אפל חשופים כמשתנים גלובליים:
* `UIButtonTypeSystem`
* `UIControlStateNormal`
* `UILayoutConstraintAxisVertical`, `UILayoutConstraintAxisHorizontal`
* `UIModalPresentationPageSheet`, `UIModalPresentationPopover`
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
פונקציות חץ סטנדרטיות של JavaScript מומרות אוטומטית ל-Blocks של Objective-C:
```javascript
// שימוש ב-UIAction (הדרך המודרנית ללחיצות כפתור):
const action = UIAction.actionWithHandler(() => {
  console.log("הכפתור נלחץ!");
});
button.addActionForControlEvents(action, UIControlEventTouchUpInside);

// אנימציות UIView:
UIView.animateWithDurationAnimations(0.3, () => {
  heroView.alpha = 0.5;
});
```

---

## 3. ארכיטקטורת תצוגה והגשה ל-Hanlin (The Presentation Contract)

באפליקציית Hanlin AI, מנוע ה-Host תופס את התצוגה המרכזית דרך ה-`NativeScriptEmbedder`:

```javascript
const embedder = NativeScriptEmbedder.sharedInstance();
if (!embedder || !embedder.delegate) {
  throw new Error("Hanlin NativeScript presenter delegate is unavailable");
}

// הגשת הבקר הראשי ישירות לתוך ה-UI של Hanlin:
embedder.delegate.presentNativeScriptApp(rootViewController);
```

### מבנה הטאבים המומלץ (UITabBarController + UINavigationController):
```javascript
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
tabs.viewControllers = [tab1Nav, tab2Nav];
tabs.selectedIndex = 0;

// 3. הגשה ל-Hanlin
embedder.delegate.presentNativeScriptApp(tabs);
```

---

## 4. שילוב רכיבי SwiftUI 4.0 מקוריים

ב-Hanlin מובנה בקר Swift רשמי המייצא רכיב SwiftUI ל-Objective-C תחת השם **`HanlinNativeScriptSwiftUIFixtureProvider`**.
בקר זה הוא למעשה **`UIViewController`** לכל דבר שמארח SwiftUI View (`UIHostingController`):

```javascript
// 1. אתחול ספק ה-SwiftUI
const ProviderClass = NSClassFromString("HanlinNativeScriptSwiftUIFixtureProvider");
const swiftController = ProviderClass.alloc().init();

// 2. עטיפה ב-NavigationController או הטמעה כ-Child View Controller
const swiftNav = UINavigationController.alloc().initWithRootViewController(swiftController);
swiftNav.tabBarItem = UITabBarItem.alloc().initWithTitleImageSelectedImage(
  "SwiftUI",
  UIImage.systemImageNamed("swift"),
  null
);

// 3. סנכרון נתונים דו-כיווני:
// שליחה מ-JavaScript ל-SwiftUI:
const data = NSMutableDictionary.new();
data.setObjectForKey("כותרת חדשה מ-JS", "title");
swiftController.updateData(data);

// קבלת אירועים מ-SwiftUI ל-JavaScript:
NSNotificationCenter.defaultCenter.addObserverForNameObjectQueueUsingBlock(
  "HanlinSwiftUIEventNotification",
  null,
  NSOperationQueue.mainQueue,
  (notification) => {
    const count = notification.userInfo.objectForKey("count");
    console.log(`אירוע התקבל מ-SwiftUI! מונה: ${count}`);
  }
);
```

---

## 5. תמיכה ב-TypeScript ומערכת טיפוסים (Type Declarations)

כדי לקבל השלמה אוטומטית (IntelliSense) ובדיקת שגיאות סטטית של כל מחלקות ה-SDK של אפל ב-TypeScript, משתמשים בחבילת הטיפוסים הרשמית:
* חבילת NPM: **`@nativescript/types-ios`**

### הגדרת `tsconfig.json`:
```json
{
  "compilerOptions": {
    "module": "ESNext",
    "target": "ES2022",
    "moduleResolution": "Bundler",
    "lib": ["ESNext"],
    "types": ["@nativescript/types-ios"],
    "strict": false,
    "skipLibCheck": true
  },
  "include": ["src/**/*"]
}
```

---

## 6. מבנה החבילה והקבצים (Package Directory Structure)

חבילת יישומון מוכנה לייבוא ב-Hanlin AI צריכה להכיל את הקבצים הבאים:

```
my-miniapp/
├── script.json
└── nativescript/
    └── app/
        ├── package.json
        └── bundle.mjs
```

### א. `script.json` (שורש החבילה)
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
   חבילת הגדרות הטיפוסים של כל ה-SDK של iOS עבור TypeScript.
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
