import {
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

function createTab1DetailPage(frame) {
  const page = new Page();
  page.title = "Tab 1 Detail";
  page.backgroundColor = new Color("#F2F2F7");

  const layout = new StackLayout();
  layout.padding = 24;

  const title = new Label();
  title.text = "Core TabView+Frame Tab 1 Detail Active";
  title.fontSize = 24;
  title.fontWeight = "700";
  title.color = new Color("#34C759");
  title.accessibilityIdentifier = "core-tabview-frame-tab1-detail-title";
  layout.addChild(title);

  const backButton = new Button();
  backButton.text = "Back to Tab 1 Root";
  backButton.accessibilityIdentifier = "core-tabview-frame-back-button";
  backButton.on("tap", () => {
    frame.goBack();
  });
  layout.addChild(backButton);

  page.content = layout;
  return page;
}

function createTab1Page(frame) {
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

  const navButton = new Button();
  navButton.text = "Navigate in Tab 1 Frame";
  navButton.accessibilityIdentifier = "core-tabview-frame-nav-button";
  navButton.on("tap", () => {
    frame.navigate({
      create: () => createTab1DetailPage(frame),
      animated: false
    });
  });
  layout.addChild(navButton);

  page.content = layout;
  return page;
}

function createTab2Page(frame) {
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
    create: () => pageFactory(frame),
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
