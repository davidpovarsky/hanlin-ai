import { Application, Button, Label, Page, StackLayout } from '@nativescript/core';

function createPage(): Page {
  const page = new Page();
  page.actionBarHidden = true;
  const content = new StackLayout();
  content.padding = 24;
  page.content = content;

  const greeting = new Label();
  greeting.text = 'Hello from NativeScript!';
  greeting.textWrap = true;
  content.addChild(greeting);

  // UIDevice is the original iOS metadata bridge, alongside NativeScript Core.
  const system = new Label();
  system.text = `${UIDevice.currentDevice.systemName} ${UIDevice.currentDevice.systemVersion}`;
  content.addChild(system);

  let count = 0;
  const result = new Label();
  result.text = 'Button taps: 0';
  content.addChild(result);
  const button = new Button();
  button.text = 'Say hello';
  button.on(Button.tapEvent, () => {
    count += 1;
    result.text = `Button taps: ${count}`;
  });
  content.addChild(button);
  return page;
}

Application.run({ create: createPage });

export const deliberateTypeError: number = "SDK08 should reject this";
