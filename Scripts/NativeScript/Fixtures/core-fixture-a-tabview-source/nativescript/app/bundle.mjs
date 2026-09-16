import {
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
