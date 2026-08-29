import {
  Application,
  Button,
  Label,
  Page,
  StackLayout,
  View,
  knownFolders
} from '@nativescript/core';
import { localModuleProof } from './local-module';

declare const UIDevice: {
  currentDevice: {
    systemName: string;
    systemVersion: string;
  };
};

declare const NSUserDefaults: {
  standardUserDefaults: {
    setObjectForKey(value: string, key: string): void;
    synchronize(): boolean;
  };
};

declare const HanlinNativeScriptCompatibility: {
  roundTripValueKey(value: string, key: string): string;
};

declare global {
  var __HANLIN_NATIVESCRIPT_PACKAGE_NAME__: string | undefined;
}

const packageName = globalThis.__HANLIN_NATIVESCRIPT_PACKAGE_NAME__ ?? 'unknown';
const systemName = UIDevice.currentDevice.systemName;
const systemVersion = UIDevice.currentDevice.systemVersion;
const proof = `${packageName}|${systemName}|${systemVersion}`;

function logMarker(message: string): void {
  console.log(message);
}

logMarker(`HANLIN_NS_FIXTURE_STARTED package=${packageName}`);
logMarker(`HANLIN_NS_NATIVE_API_OK system=${systemName} version=${systemVersion}`);

const compatibilityProof = HanlinNativeScriptCompatibility.roundTripValueKey(
  `compatibility-${packageName}`,
  packageName
);
if (compatibilityProof !== `compatibility-${packageName}`) {
  throw new Error('Hanlin Scripting compatibility round-trip failed');
}
logMarker('HANLIN_NS_SCRIPTING_ADAPTER_OK adapter=HanlinNativeScriptCompatibility');

const resourceProof = knownFolders.currentApp().getFile('fixture-resource.txt').readTextSync().trim();
if (localModuleProof(resourceProof) !== 'local-module:bundled-resource') {
  throw new Error('NativeScript local module/resource proof failed');
}
logMarker('HANLIN_NS_MODULE_RESOURCE_OK module=local-module resource=fixture-resource.txt');

NSUserDefaults.standardUserDefaults.setObjectForKey(
  proof,
  `HanlinNativeScriptFixture.${packageName}`
);
NSUserDefaults.standardUserDefaults.synchronize();

Application.run({
  create: () => {
    const page = new Page();
    const layout = new StackLayout();
    layout.padding = 24;

    const title = new Label();
    title.text = `NativeScript ${packageName}`;
    title.fontSize = 26;
    title.textWrap = true;

    const device = new Label();
    device.text = `${systemName} ${systemVersion}`;
    device.fontSize = 18;
    device.textWrap = true;
    device.accessibilityIdentifier = 'hanlin-nativescript-device-proof';

    const button = new Button();
    button.text = 'NativeScript Core Button';
    button.accessibilityIdentifier = 'hanlin-nativescript-core-button';

    // NativeScript 9.1's generic symbol-index declarations are invariant in
    // TypeScript 5.9 even though every control is a View at runtime.
    layout.addChild(title as unknown as View);
    layout.addChild(device as unknown as View);
    layout.addChild(button as unknown as View);
    page.content = layout;
    logMarker('HANLIN_NS_CORE_UI_READY controls=Label,Button');
    return page;
  }
});
