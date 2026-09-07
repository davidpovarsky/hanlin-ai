import {
  Application,
  Button,
  Label,
  Page,
  StackLayout,
  View
} from '@nativescript/core';
import {
  registerSwiftUI,
  SwiftUI,
  SwiftUIEventData,
  UIDataDriver
} from '@nativescript/swift-ui';

declare const UIDevice: {
  currentDevice: { systemName: string; systemVersion: string };
};

declare const HanlinNativeScriptCompatibility: {
  createSwiftUIFixtureProvider(): any;
} | undefined;

declare const HanlinNativeScriptSwiftUIFixtureProvider: {
  alloc(): { init(): any };
} | undefined;

declare global {
  var __HANLIN_NATIVESCRIPT_PACKAGE_NAME__: string | undefined;
}

const packageName = globalThis.__HANLIN_NATIVESCRIPT_PACKAGE_NAME__ ?? 'unknown';
const systemName = UIDevice.currentDevice.systemName;
const systemVersion = UIDevice.currentDevice.systemVersion;

console.log(`HANLIN_NS_FIXTURE_STARTED package=${packageName}`);
console.log(`HANLIN_NS_NATIVE_API_OK system=${systemName} version=${systemVersion}`);
console.log('HANLIN_NS_SWIFTUI_MODULE_OK package=@nativescript/swift-ui version=4.0.2');

function createFixtureProvider(): any {
  const g = globalThis as any;
  const getClass = (name: string): any => {
    try {
      if (typeof g.NSClassFromString === 'function') {
        const cls = g.NSClassFromString(name);
        if (cls) return cls;
      }
    } catch {}
    try {
      if (typeof g.objc_getClass === 'function') {
        const cls = g.objc_getClass(name);
        if (cls) return cls;
      }
    } catch {}
    return g[name] ?? null;
  };

  const instantiate = (cls: any): any => {
    if (!cls) return null;
    try {
      if (typeof cls.alloc === 'function') {
        return cls.alloc().init();
      }
    } catch {}
    try {
      if (typeof cls.new === 'function') {
        return cls.new();
      }
    } catch {}
    try {
      if (typeof cls === 'function') {
        return new cls();
      }
    } catch {}
    return null;
  };

  // First priority: HanlinNativeScriptCompatibility bridge helper
  const compatCls = getClass('HanlinNativeScriptCompatibility');
  if (compatCls && typeof compatCls.createSwiftUIFixtureProvider === 'function') {
    const provider = compatCls.createSwiftUIFixtureProvider();
    if (provider) return provider;
  }

  // Second priority: direct HanlinNativeScriptSwiftUIFixtureProvider class
  const providerCls = getClass('HanlinNativeScriptSwiftUIFixtureProvider');
  const directProvider = instantiate(providerCls);
  if (directProvider) return directProvider;

  throw new Error('HanlinNativeScriptSwiftUIFixtureProvider could not be instantiated');
}

registerSwiftUI('hanlinFixture', (view) => new UIDataDriver(
  createFixtureProvider(),
  view
));

Application.run({
  create: () => {
    const page = new Page();
    const layout = new StackLayout();
    layout.padding = 20;

    const title = new Label();
    title.text = `NativeScript SwiftUI ${packageName}`;
    title.fontSize = 24;
    title.textWrap = true;

    const device = new Label();
    device.text = `${systemName} ${systemVersion}`;
    device.fontSize = 17;
    device.textWrap = true;
    device.accessibilityIdentifier = 'hanlin-nativescript-device-proof';

    const coreButton = new Button();
    coreButton.text = 'NativeScript Core Button';
    coreButton.accessibilityIdentifier = 'hanlin-nativescript-core-button';

    const swiftView = new SwiftUI<{ count: number; source: string }>();
    swiftView.swiftId = 'hanlinFixture';
    swiftView.height = 300;
    swiftView.data = { title: 'SwiftUI in Hanlin', initialCount: 0 };

    const eventProof = new Label();
    eventProof.text = 'NativeScript event count: 0';
    eventProof.fontSize = 17;
    eventProof.textWrap = true;
    eventProof.accessibilityIdentifier = 'hanlin-swiftui-event-proof';
    swiftView.on(SwiftUI.swiftUIEventEvent, (event: SwiftUIEventData<{ count: number; source: string }>) => {
      eventProof.text = `NativeScript event count: ${event.data.count}`;
      console.log(`HANLIN_NS_SWIFTUI_EVENT_OK count=${event.data.count} source=${event.data.source}`);
    });

    layout.addChild(title as unknown as View);
    layout.addChild(device as unknown as View);
    layout.addChild(coreButton as unknown as View);
    layout.addChild(swiftView as unknown as View);
    layout.addChild(eventProof as unknown as View);
    page.content = layout;
    console.log('HANLIN_NS_CORE_UI_READY controls=Label,Button,SwiftUI');
    return page;
  }
});
