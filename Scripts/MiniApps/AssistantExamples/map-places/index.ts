import { Application, Label, Page } from '@nativescript/core';

Application.run({ create: () => {
  const page = new Page();
  const label = new Label();
  label.text = 'Local places demo. Attach this app as a chat tool to choose a map pin and radius.';
  label.textWrap = true;
  page.content = label;
  return page;
}});
