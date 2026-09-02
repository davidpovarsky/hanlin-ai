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

declare const HanlinNativeScriptSwiftUIFixtureProvider: {
  alloc(): { init(): any };
};

declare global {
  var __HANLIN_NATIVESCRIPT_PACKAGE_NAME__: string | undefined;
}

const packageName = globalThis.__HANLIN_NATIVESCRIPT_PACKAGE_NAME__ ?? 'unknown';
const systemName = UIDevice.currentDevice.systemName;
const systemVersion = UIDevice.currentDevice.systemVersion;

console.log(`HANLIN_NS_FIXTURE_STARTED package=${packageName}`);
console.log(`HANLIN_NS_NATIVE_API_OK system=${systemName} version=${systemVersion}`);
console.log('HANLIN_NS_SWIFTUI_MODULE_OK package=@nativescript/swift-ui version=4.0.2');

registerSwiftUI('hanlinFixture', (view) => new UIDataDriver(
  HanlinNativeScriptSwiftUIFixtureProvider.alloc().init(),
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
