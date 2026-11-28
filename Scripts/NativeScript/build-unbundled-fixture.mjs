import { mkdir, writeFile, rm } from 'node:fs/promises';
import { resolve } from 'node:path';
import { execSync } from 'node:child_process';

const scriptRoot = resolve(import.meta.dirname);
const fixtureDir = resolve(scriptRoot, 'Fixtures', 'core-unbundled-source');
const appDir = resolve(fixtureDir, 'nativescript', 'app');
const targetZip = resolve(scriptRoot, 'Fixtures', 'core-unbundled.hanlinNativeScript');

await rm(fixtureDir, { recursive: true, force: true });
await mkdir(appDir, { recursive: true });

const packageJSON = {
  name: 'hanlin-core-unbundled-test',
  version: '1.0.0',
  private: true,
  type: 'module',
  main: 'bundle.mjs',
  hanlinRuntime: 'hanlin-nativescript',
  dependencies: {
    '@nativescript/core': '9.1.0'
  }
};

const bundleMJS = `// Minimal Unbundled NativeScript Core E2E Test
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
`;

const scriptJSON = {
  name: "Hanlin NativeScript Unbundled Core E2E",
  version: "1.0.0",
  description: "Unbundled NativeScript 9.1 Shared Core runtime verification fixture.",
  entry: "nativescript/app/bundle.mjs",
  runInApp: true,
  hanlinRuntime: "hanlin-nativescript"
};

await writeFile(resolve(appDir, 'package.json'), `${JSON.stringify(packageJSON, null, 2)}\n`);
await writeFile(resolve(appDir, 'bundle.mjs'), bundleMJS);
await writeFile(resolve(fixtureDir, 'script.json'), `${JSON.stringify(scriptJSON, null, 2)}\n`);

// Create zip archive
await rm(targetZip, { force: true });
const pyCmd = `python3 -c "import zipfile, os, sys; zf = zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED); [zf.write(os.path.join(r, f), os.path.relpath(os.path.join(r, f), sys.argv[2]).replace('\\\\\\\\', '/')) for r, d, files in os.walk(sys.argv[2]) for f in files]; zf.close()" "${targetZip}" "${fixtureDir}"`;
try {
  execSync(pyCmd);
} catch {
  execSync(pyCmd.replace('python3', 'python'));
}
console.log(`Created unbundled fixture at ${targetZip}`);

