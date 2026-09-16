import { mkdir, writeFile, rm, cp } from 'node:fs/promises';
import { resolve } from 'node:path';
import { execSync } from 'node:child_process';

const scriptRoot = resolve(import.meta.dirname);
const repoRoot = resolve(scriptRoot, '..', '..');
const fixturesDir = resolve(scriptRoot, 'Fixtures');
const e2eDir = resolve(repoRoot, 'build', 'NativeScriptE2E');

function zipDir(sourceDir, targetZip) {
  const pyCmd = `python3 -c "import zipfile, os, sys; zf = zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED); [zf.write(os.path.join(r, f), os.path.relpath(os.path.join(r, f), sys.argv[2]).replace('\\\\\\\\', '/')) for r, d, files in os.walk(sys.argv[2]) for f in files]; zf.close()" "${targetZip}" "${sourceDir}"`;
  try {
    execSync(pyCmd);
  } catch {
    execSync(pyCmd.replace('python3', 'python'));
  }
}

async function buildFixture({ name, displayName, description, bundleCode, isCore = true }) {
  const sourceDir = resolve(fixturesDir, `${name}-source`);
  const appDir = resolve(sourceDir, 'nativescript', 'app');
  const targetZip = resolve(fixturesDir, `${name}.hanlinNativeScript`);

  await rm(sourceDir, { recursive: true, force: true });
  await mkdir(appDir, { recursive: true });

  const packageJSON = {
    name,
    version: '1.0.0',
    private: true,
    type: 'module',
    main: 'bundle.mjs',
    hanlinRuntime: 'hanlin-nativescript',
    dependencies: {
      '@nativescript/core': '9.1.0'
    }
  };

  const scriptJSON = {
    name: displayName,
    version: '1.0.0',
    description,
    entry: 'nativescript/app/bundle.mjs',
    runInApp: true,
    hanlinRuntime: 'hanlin-nativescript'
  };

  await writeFile(resolve(appDir, 'package.json'), JSON.stringify(packageJSON, null, 2) + '\n');
  await writeFile(resolve(appDir, 'bundle.mjs'), bundleCode);
  await writeFile(resolve(sourceDir, 'script.json'), JSON.stringify(scriptJSON, null, 2) + '\n');

  await rm(targetZip, { force: true });
  zipDir(sourceDir, targetZip);
  console.log(`Built fixture ${name} -> ${targetZip}`);

  // Copy to build/NativeScriptE2E if exists
  try {
    await mkdir(e2eDir, { recursive: true });
    await cp(targetZip, resolve(e2eDir, `${name}.hanlinNativeScript`));
  } catch (err) {
    console.warn(`Could not copy to ${e2eDir}: ${err.message}`);
  }
}

// 0. Direct UIKit TabBar Bridge Baseline (No @nativescript/core)
const uikitTabBarCode = `// Direct UIKit TabBar Bridge Baseline Test
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
`;

// 1. Fixture A: Unbundled Core TabView Only (No Frame)
const coreFixtureACode = `import {
  Application,
  TabView,
  TabViewItem,
  StackLayout,
  Label,
  Button,
  Color
} from "@nativescript/core";

function createTabA() {
  const item = new TabViewItem();
  item.title = "Tab A";
  item.accessibilityIdentifier = "core-fixture-a-tab-a";

  const layout = new StackLayout();
  layout.padding = 24;
  layout.backgroundColor = new Color("#FFFFFF");

  const title = new Label();
  title.text = "Core TabView Page A Active";
  title.fontSize = 24;
  title.fontWeight = "700";
  title.color = new Color("#007AFF");
  title.accessibilityIdentifier = "core-tabview-title-a";
  layout.addChild(title);

  const status = new Label();
  status.text = "Page A Ready";
  status.fontSize = 18;
  status.accessibilityIdentifier = "core-tabview-status-a";
  layout.addChild(status);

  item.view = layout;
  return item;
}

function createTabB() {
  const item = new TabViewItem();
  item.title = "Tab B";
  item.accessibilityIdentifier = "core-fixture-a-tab-b";

  const layout = new StackLayout();
  layout.padding = 24;
  layout.backgroundColor = new Color("#F2F2F7");

  const title = new Label();
  title.text = "Core TabView Page B Active";
  title.fontSize = 24;
  title.fontWeight = "700";
  title.color = new Color("#34C759");
  title.accessibilityIdentifier = "core-tabview-title-b";
  layout.addChild(title);

  item.view = layout;
  return item;
}

export function createRoot() {
  const tabView = new TabView();
  tabView.selectedIndex = 0;
  tabView.items = [createTabA(), createTabB()];
  return tabView;
}

Application.run({
  create: () => createRoot()
});
`;

// 2. Fixture B: Unbundled Core Frame Only (Navigation Stack)
const coreFixtureBCode = `import {
  Application,
  Frame,
  Page,
  StackLayout,
  Label,
  Button,
  Color
} from "@nativescript/core";

function createPage2(frame) {
  const page = new Page();
  page.title = "Page 2";
  page.backgroundColor = new Color("#F2F2F7");

  const layout = new StackLayout();
  layout.padding = 24;

  const title = new Label();
  title.text = "Core Frame Page 2 Active";
  title.fontSize = 24;
  title.fontWeight = "700";
  title.color = new Color("#FF9500");
  title.accessibilityIdentifier = "core-frame-page2-title";
  layout.addChild(title);

  const backButton = new Button();
  backButton.text = "Back to Page 1";
  backButton.accessibilityIdentifier = "core-frame-back-button";
  backButton.on("tap", () => {
    frame.goBack();
  });
  layout.addChild(backButton);

  page.content = layout;
  return page;
}

function createPage1(frame) {
  const page = new Page();
  page.title = "Page 1";
  page.backgroundColor = new Color("#FFFFFF");

  const layout = new StackLayout();
  layout.padding = 24;

  const title = new Label();
  title.text = "Core Frame Page 1 Active";
  title.fontSize = 24;
  title.fontWeight = "700";
  title.color = new Color("#007AFF");
  title.accessibilityIdentifier = "core-frame-page1-title";
  layout.addChild(title);

  const nextButton = new Button();
  nextButton.text = "Navigate to Page 2";
  nextButton.accessibilityIdentifier = "core-frame-next-button";
  nextButton.on("tap", () => {
    frame.navigate({
      create: () => createPage2(frame),
      animated: false
    });
  });
  layout.addChild(nextButton);

  page.content = layout;
  return page;
}

export function createRoot() {
  const frame = new Frame();
  frame.navigate({
    create: () => createPage1(frame),
    clearHistory: true,
    animated: false
  });
  return frame;
}

Application.run({
  create: () => createRoot()
});
`;

// 3. Fixture C: Unbundled Core TabView + Frame (Sefaria Architecture)
const coreFixtureCCode = `import {
  Application,
  TabView,
  TabViewItem,
  Frame,
  Page,
  StackLayout,
  Label,
  Button,
  Color
} from "@nativescript/core";

function createTab1Page() {
  const page = new Page();
  page.title = "Tab 1";
  page.backgroundColor = new Color("#FFFFFF");

  const layout = new StackLayout();
  layout.padding = 24;

  const title = new Label();
  title.text = "Core TabView+Frame Tab 1 Active";
  title.fontSize = 24;
  title.fontWeight = "700";
  title.color = new Color("#007AFF");
  title.accessibilityIdentifier = "core-tabview-frame-tab1-title";
  layout.addChild(title);

  page.content = layout;
  return page;
}

function createTab2Page() {
  const page = new Page();
  page.title = "Tab 2";
  page.backgroundColor = new Color("#F2F2F7");

  const layout = new StackLayout();
  layout.padding = 24;

  const title = new Label();
  title.text = "Core TabView+Frame Tab 2 Active";
  title.fontSize = 24;
  title.fontWeight = "700";
  title.color = new Color("#5856D6");
  title.accessibilityIdentifier = "core-tabview-frame-tab2-title";
  layout.addChild(title);

  page.content = layout;
  return page;
}

function createTab(title, pageFactory) {
  const frame = new Frame();
  frame.navigate({
    create: () => pageFactory(),
    clearHistory: true,
    animated: false
  });

  const item = new TabViewItem();
  item.title = title;
  item.view = frame;
  return item;
}

export function createRoot() {
  const tabView = new TabView();
  tabView.selectedIndex = 0;
  tabView.items = [
    createTab("First Tab", createTab1Page),
    createTab("Second Tab", createTab2Page)
  ];
  return tabView;
}

Application.run({
  create: () => createRoot()
});
`;

await buildFixture({
  name: 'uikit-tabbar-bridge',
  displayName: 'Hanlin UIKit TabBar Bridge E2E',
  description: 'Direct NativeScript bridge UITabBarController baseline fixture.',
  bundleCode: uikitTabBarCode,
  isCore: false
});

await buildFixture({
  name: 'core-fixture-a-tabview',
  displayName: 'Hanlin NativeScript Core TabView A E2E',
  description: 'Unbundled Core TabView without Frame verification fixture.',
  bundleCode: coreFixtureACode,
  isCore: true
});

await buildFixture({
  name: 'core-fixture-b-frame',
  displayName: 'Hanlin NativeScript Core Frame B E2E',
  description: 'Unbundled Core Frame navigation verification fixture.',
  bundleCode: coreFixtureBCode,
  isCore: true
});

await buildFixture({
  name: 'core-fixture-c-tabview-frame',
  displayName: 'Hanlin NativeScript Core TabView+Frame C E2E',
  description: 'Unbundled Core TabView containing Frames verification fixture.',
  bundleCode: coreFixtureCCode,
  isCore: true
});

console.log('All controller fixtures built successfully.');
