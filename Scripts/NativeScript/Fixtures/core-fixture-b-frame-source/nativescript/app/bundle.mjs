import {
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
