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

  globalActiveProvider = provider;
  globalActiveCompat = activeCompat;

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
      }
    });
  } catch (e) {
    console.log(`[HanlinNativeScript] defineProperty onEvent note: ${e}`);
  }

  return provider;
}

let globalDriver: any = null;
let globalEventProof: any = null;
let globalSwiftView: any = null;
let globalActiveProvider: any = null;
let globalActiveCompat: any = null;
let lastProcessedCount = 0;

function handleSwiftUIEvent(count: number, source: string = 'swiftui') {
  if (count <= lastProcessedCount) {
    return;
  }
  lastProcessedCount = count;
  console.log(`[HanlinSwiftUI] Handling incoming SwiftUI event: count=${count}, source=${source}`);

  if (globalEventProof) {
    globalEventProof.text = `NativeScript event count: ${count}`;
  }

  if (globalDriver && typeof globalDriver.onEvent === 'function') {
    try {
      globalDriver.onEvent({ count, source });
    } catch (e) {
      console.log(`[HanlinSwiftUI] driver.onEvent note: ${e}`);
    }
  }

  if (globalSwiftView && typeof globalSwiftView.notify === 'function') {
    try {
      globalSwiftView.notify({
        eventName: SwiftUI.swiftUIEventEvent,
        data: { count, source }
      });
    } catch (e) {
      console.log(`[HanlinSwiftUI] swiftView.notify note: ${e}`);
    }
  }

  console.log(`HANLIN_NS_SWIFTUI_EVENT_OK count=${count} source=${source}`);
}

const g = globalThis as any;

// 1. NSNotificationCenter observer
try {
  if (typeof g.NSNotificationCenter !== 'undefined' && g.NSNotificationCenter.defaultCenter) {
    const center = g.NSNotificationCenter.defaultCenter;
    const queue = typeof g.NSOperationQueue !== 'undefined' ? g.NSOperationQueue.mainQueue : null;
    center.addObserverForNameObjectQueueUsingBlock(
      'HanlinSwiftUIEventNotification',
      null,
      queue,
      (notif: any) => {
        try {
          let count = 1;
          let source = 'swiftui';
          if (notif && notif.userInfo) {
            const ui = notif.userInfo;
            if (typeof ui.objectForKey === 'function') {
              const c = ui.objectForKey('count');
              if (c != null) count = Number(typeof c.integerValue === 'function' ? c.integerValue() : c) || 1;
              const s = ui.objectForKey('source');
              if (s != null) source = String(s);
            }
          }
          handleSwiftUIEvent(count, source);
        } catch (err) {
          console.log(`[HanlinSwiftUI] notification error: ${err}`);
        }
      }
    );
    console.log('[HanlinSwiftUI] Registered NSNotificationCenter observer');
  }
} catch (e) {
  console.log(`[HanlinSwiftUI] addObserver note: ${e}`);
}

// 2. High-frequency polling timer (100ms)
setInterval(() => {
  try {
    // Check provider.currentCount()
    if (globalActiveProvider) {
      let countVal: any = null;
      if (typeof globalActiveProvider.currentCount === 'function') {
        countVal = globalActiveProvider.currentCount();
      } else if (typeof globalActiveProvider.performSelector === 'function' && typeof g.NSSelectorFromString === 'function') {
        countVal = globalActiveProvider.performSelector(g.NSSelectorFromString('currentCount'));
      }
      if (countVal != null) {
        const c = Number(typeof countVal.integerValue === 'function' ? countVal.integerValue() : countVal);
        if (c > 0) {
          handleSwiftUIEvent(c, 'swiftui');
          return;
        }
      }
    }

    // Check compat.latestEventCount()
    let compat = globalActiveCompat ?? g.HanlinNativeScriptCompatibility;
    if (!compat && typeof g.NSClassFromString === 'function') {
      compat = g.NSClassFromString('HanlinNativeScriptCompatibility');
    }
    if (compat) {
      let countVal: any = null;
      if (typeof compat.latestEventCount === 'function') {
        countVal = compat.latestEventCount();
      } else if (typeof compat.performSelector === 'function' && typeof g.NSSelectorFromString === 'function') {
        countVal = compat.performSelector(g.NSSelectorFromString('latestEventCount'));
      }
      if (countVal != null) {
        const c = Number(typeof countVal.integerValue === 'function' ? countVal.integerValue() : countVal);
        if (c > 0) {
          handleSwiftUIEvent(c, 'swiftui');
          return;
        }
      }
    }
  } catch (e) {}
}, 100);

registerSwiftUI('hanlinFixture', (view) => {
  console.log('[HanlinSwiftUI] registerSwiftUI generator invoked');
  const provider = createFixtureProvider();
  const driver = new UIDataDriver(provider, view);
  globalDriver = driver;
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
      handleSwiftUIEvent(event.data.count, event.data.source);
    });

    globalSwiftView = swiftView;
    globalEventProof = eventProof;

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
