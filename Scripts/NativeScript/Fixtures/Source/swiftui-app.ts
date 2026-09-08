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
  console.log('[HanlinSwiftUI] createFixtureProvider starting lookup');

  const compatCandidates = [
    g.HanlinNativeScriptCompatibility,
    typeof g.NSClassFromString === 'function' ? g.NSClassFromString('HanlinNativeScriptCompatibility') : null,
    typeof g.objc_getClass === 'function' ? g.objc_getClass('HanlinNativeScriptCompatibility') : null,
  ].filter(Boolean);

  let provider: any = null;
  let activeCompat: any = null;

  // 1. Try createSwiftUIFixtureProvider on compatibility bridge
  for (const compat of compatCandidates) {
    if (provider) break;
    try {
      if (typeof compat.createSwiftUIFixtureProvider === 'function') {
        console.log('[HanlinSwiftUI] Invoking compat.createSwiftUIFixtureProvider()');
        provider = compat.createSwiftUIFixtureProvider();
        if (provider) {
          activeCompat = compat;
        }
      } else if (typeof compat.performSelector === 'function' && typeof g.NSSelectorFromString === 'function') {
        console.log('[HanlinSwiftUI] Invoking compat.performSelector(createSwiftUIFixtureProvider)');
        provider = compat.performSelector(g.NSSelectorFromString('createSwiftUIFixtureProvider'));
        if (provider) {
          activeCompat = compat;
        }
      }
    } catch (e) {
      console.log(`[HanlinSwiftUI] compat.createSwiftUIFixtureProvider candidate note: ${e}`);
    }
  }

  // 2. Try direct HanlinNativeScriptSwiftUIFixtureProvider
  if (!provider) {
    const directCandidates = [
      g.HanlinNativeScriptSwiftUIFixtureProvider,
      g['HanlinNativeScriptRuntime.HanlinNativeScriptSwiftUIFixtureProvider'],
    ].filter(Boolean);

    for (const Cls of directCandidates) {
      if (provider) break;
      try {
        if (typeof Cls.alloc === 'function') {
          console.log('[HanlinSwiftUI] Instantiating direct Cls via alloc().init()');
          provider = Cls.alloc().init();
        } else if (typeof Cls.new === 'function') {
          provider = Cls.new();
        } else if (typeof Cls === 'function') {
          provider = new Cls();
        }
      } catch (e) {
        console.log(`[HanlinSwiftUI] direct candidate note: ${e}`);
      }
    }
  }

  // 3. Try shared provider on compatibility bridge
  if (!provider) {
    for (const compat of compatCandidates) {
      if (provider) break;
      try {
        if (typeof compat.sharedSwiftUIFixtureProvider === 'function') {
          console.log('[HanlinSwiftUI] Invoking compat.sharedSwiftUIFixtureProvider()');
          provider = compat.sharedSwiftUIFixtureProvider();
          if (provider) {
            activeCompat = compat;
          }
        } else if (typeof compat.performSelector === 'function' && typeof g.NSSelectorFromString === 'function') {
          console.log('[HanlinSwiftUI] Invoking compat.performSelector(sharedSwiftUIFixtureProvider)');
          provider = compat.performSelector(g.NSSelectorFromString('sharedSwiftUIFixtureProvider'));
          if (provider) {
            activeCompat = compat;
          }
        }
      } catch (e) {
        console.log(`[HanlinSwiftUI] compat.sharedSwiftUIFixtureProvider candidate note: ${e}`);
      }
    }
  }

  if (!provider) {
    throw new Error('HanlinNativeScriptSwiftUIFixtureProvider could not be instantiated');
  }

  console.log(`[HanlinSwiftUI] Provider created: ${provider}`);
  try {
    const v = provider.view;
    console.log(`[HanlinSwiftUI] Provider view loaded: ${v}`);
  } catch (e) {
    console.log(`[HanlinSwiftUI] Provider view access note: ${e}`);
  }

  // Ensure updateDataWithData is callable by @nativescript/swift-ui UIDataDriver
  if (typeof provider.updateDataWithData !== 'function') {
    provider.updateDataWithData = function (data: any) {
      try {
        if (typeof provider.updateData === 'function') {
          provider.updateData(data);
        } else if (typeof provider.updateDataDirect === 'function') {
          provider.updateDataDirect(data);
        } else if (activeCompat && typeof activeCompat.updateSwiftUIProviderData === 'function') {
          activeCompat.updateSwiftUIProviderData(provider, data);
        } else if (activeCompat && typeof activeCompat.performSelectorWithObjectWithObject === 'function' && typeof g.NSSelectorFromString === 'function') {
          activeCompat.performSelectorWithObjectWithObject(g.NSSelectorFromString('updateSwiftUIProvider:data:'), provider, data);
        }
      } catch (e) {
        console.log(`[HanlinNativeScript] updateDataWithData note: ${e}`);
      }
    };
  }

  // Bridge onEvent so NativeScript UIDataDriver event registration reaches the Swift fixture model
  let registeredEventCallback: any = provider.onEvent ?? null;
  try {
    Object.defineProperty(provider, 'onEvent', {
      configurable: true,
      enumerable: true,
      get() {
        return registeredEventCallback;
      },
      set(callback: any) {
        registeredEventCallback = callback;
        const wrapped = (dict: any) => {
          try {
            if (typeof callback === 'function') {
              callback(dict);
            }
          } catch (err) {
            console.log(`[HanlinNativeScript] callback error: ${err}`);
          }
        };
        try {
          if (activeCompat && typeof activeCompat.registerSwiftUIProviderEventHandler === 'function') {
            activeCompat.registerSwiftUIProviderEventHandler(provider, wrapped);
          }
        } catch (e) {
          console.log(`[HanlinNativeScript] registerSwiftUIProviderEventHandler note: ${e}`);
        }
        try {
          if (typeof (provider as any).registerEventHandler === 'function') {
            (provider as any).registerEventHandler(wrapped);
          }
        } catch (e) {
          console.log(`[HanlinNativeScript] provider.registerEventHandler note: ${e}`);
        }
      }
    });
  } catch (e) {
    console.log(`[HanlinNativeScript] defineProperty onEvent note: ${e}`);
  }

  return provider;
}

registerSwiftUI('hanlinFixture', (view) => {
  console.log('[HanlinSwiftUI] registerSwiftUI generator invoked');
  const provider = createFixtureProvider();
  const driver = new UIDataDriver(provider, view);
  if (view.data) {
    driver.updateData(view.data);
  }
  return driver;
});

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
    swiftView.width = 400;
    swiftView.horizontalAlignment = 'stretch';
    swiftView.data = { title: 'SwiftUI in Hanlin', initialCount: 0 };
    swiftView.on('loaded', () => {
      if (swiftView.data) {
        swiftView.updateData(swiftView.data);
      }
    });

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
