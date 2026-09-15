// Minimal Unbundled NativeScript Core E2E Test
// Imports directly from Hanlin's shared @nativescript/core@9.1.0 runtime
// without per-package Core bundling.

import {
  Application,
  Page,
  StackLayout,
  Label,
  Button,
  Color,
  Http,
  knownFolders,
  Frame
} from "@nativescript/core";

function createRootPage() {
  const page = new Page();
  page.actionBarHidden = false;
  page.title = "Unbundled Core Test";
  page.backgroundColor = new Color("#F2F2F7");

  const layout = new StackLayout();
  layout.padding = 20;

  const titleLabel = new Label();
  titleLabel.text = "Unbundled Shared Core Active";
  titleLabel.fontSize = 24;
  titleLabel.fontWeight = "700";
  titleLabel.color = new Color("#007AFF");
  titleLabel.accessibilityIdentifier = "unbundled-core-title";
  layout.addChild(titleLabel);

  const statusLabel = new Label();
  statusLabel.text = "Ready";
  statusLabel.fontSize = 18;
  statusLabel.color = new Color("#1C1C1E");
  statusLabel.accessibilityIdentifier = "unbundled-core-status";
  layout.addChild(statusLabel);

  const actionButton = new Button();
  actionButton.text = "Verify Core Features";
  actionButton.accessibilityIdentifier = "unbundled-core-verify-button";
  actionButton.backgroundColor = new Color("#34C759");
  actionButton.color = new Color("#FFFFFF");
  actionButton.fontSize = 18;
  actionButton.on("tap", () => {
    try {
      // 1. Styling verification
      statusLabel.color = new Color("#34C759");

      // 2. Core filesystem verification
      const appFolder = knownFolders.currentApp();
      const docsFolder = knownFolders.documents();
      if (!appFolder || !docsFolder) {
        statusLabel.text = "FS Error: folders missing";
        return;
      }

      // 3. Http module API verification
      if (typeof Http.getString !== "function" || typeof Http.request !== "function") {
        statusLabel.text = "Http Error: API missing";
        return;
      }

      statusLabel.text = "All Core Features Verified";

      // Also trigger an asynchronous Http call in background
      Http.getString("https://example.com").catch(() => {});
    } catch (err) {
      statusLabel.text = "Error: " + (err?.message || err);
    }
  });

  layout.addChild(actionButton);

  page.content = layout;
  return page;
}

Application.run({
  create: () => createRootPage()
});
