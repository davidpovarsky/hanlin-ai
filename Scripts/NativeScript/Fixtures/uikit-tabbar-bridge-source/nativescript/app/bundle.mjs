// Direct UIKit TabBar Bridge Baseline Test
console.log("[UIKitTabBarBridge] Starting direct UIKit TabBar fixture...");

const tabBarController = UITabBarController.new();

// Tab 1
const vc1 = UIViewController.new();
vc1.view.backgroundColor = UIColor.systemBackgroundColor;
const tab1Item = UITabBarItem.alloc().initWithTitleImageTag("Direct Tab 1", null, 0);
tab1Item.accessibilityIdentifier = "uikit-tab-item-1";
vc1.tabBarItem = tab1Item;

const label1 = UILabel.alloc().initWithFrame(CGRectMake(30, 100, 350, 44));
label1.text = "UIKit TabBar Active";
label1.font = UIFont.boldSystemFontOfSize(24);
label1.accessibilityIdentifier = "uikit-tabbar-bridge-title";
vc1.view.addSubview(label1);

const button1 = UIButton.buttonWithType(1); // UIButtonTypeSystem
button1.frame = CGRectMake(30, 160, 200, 44);
button1.setTitleForState("Direct Button 1", 0);
button1.accessibilityIdentifier = "uikit-tabbar-bridge-button-1";
vc1.view.addSubview(button1);

// Tab 2
const vc2 = UIViewController.new();
vc2.view.backgroundColor = UIColor.secondarySystemBackgroundColor;
const tab2Item = UITabBarItem.alloc().initWithTitleImageTag("Direct Tab 2", null, 1);
tab2Item.accessibilityIdentifier = "uikit-tab-item-2";
vc2.tabBarItem = tab2Item;

const label2 = UILabel.alloc().initWithFrame(CGRectMake(30, 100, 350, 44));
label2.text = "Second Direct Tab";
label2.accessibilityIdentifier = "uikit-tabbar-bridge-tab2-label";
vc2.view.addSubview(label2);

tabBarController.viewControllers = NSArray.arrayWithArray([vc1, vc2]);
tabBarController.selectedIndex = 0;

try {
  if (typeof NativeScriptEmbedder !== 'undefined' && NativeScriptEmbedder.sharedInstance) {
    const embedder = NativeScriptEmbedder.sharedInstance();
    if (embedder && embedder.delegate) {
      console.log("[UIKitTabBarBridge] Presenting via NativeScriptEmbedder.delegate...");
      embedder.delegate.presentNativeScriptApp(tabBarController);
    }
  }
} catch (e) {
  console.error("[UIKitTabBarBridge] Present error: " + e);
}
