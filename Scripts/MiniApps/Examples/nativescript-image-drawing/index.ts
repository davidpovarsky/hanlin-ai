import { Application, Button, Image, ImageSource, Label, Page, StackLayout, Trace } from '@nativescript/core';
import { checkNativeDrawing, drawImageInRect, drawingSource } from './drawing';

function createPage(): Page {
  const page = new Page();
  page.actionBarHidden = true;
  const content = new StackLayout();
  content.padding = 24;
  page.content = content;

  const heading = new Label();
  heading.text = 'Native image drawing';
  heading.fontSize = 24;
  content.addChild(heading);
  const explanation = new Label();
  explanation.text = 'Rotate the red and blue image around its center. The transparent canvas stays 128 × 128 pixels.';
  explanation.textWrap = true;
  content.addChild(explanation);

  const source = drawingSource();
  const receipt = checkNativeDrawing(source);
  Trace.addCategories('MiniApps.Drawing');
  Trace.enable();
  Trace.write(JSON.stringify({scenario: 'miniapps-native-drawing', ...receipt}), 'MiniApps.Drawing', Trace.messageType.info);
  const image = new Image();
  image.width = 256;
  image.height = 256;
  image.stretch = 'aspectFit';
  image.automationText = 'miniapps-drawing-image';
  content.addChild(image);
  const status = new Label();
  status.textWrap = true;
  content.addChild(status);
  const angles = [0, 45, 90, 180] as const;
  let index = 0;
  function render(): void {
    const angle = angles[index] ?? 0;
    image.src = new ImageSource(drawImageInRect(source, {width: 128, height: 128},
      {x: 24, y: 44, width: 80, height: 40}, angle));
    status.text = `${angle}° clockwise • ${receipt.rejectedInputs} invalid inputs rejected`;
  }
  const rotate = new Button();
  rotate.text = 'Rotate image';
  rotate.automationText = 'miniapps-drawing-rotate';
  rotate.on(Button.tapEvent, () => { index = (index + 1) % angles.length; render(); });
  content.addChild(rotate);
  render();
  return page;
}

Application.run({create: createPage});
