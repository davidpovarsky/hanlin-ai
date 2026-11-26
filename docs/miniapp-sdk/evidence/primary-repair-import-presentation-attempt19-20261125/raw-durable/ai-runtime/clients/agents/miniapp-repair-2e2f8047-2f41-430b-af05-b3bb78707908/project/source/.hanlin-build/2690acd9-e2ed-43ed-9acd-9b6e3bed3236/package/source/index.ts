export const answer: number = 42;
import {Application, Page, Label} from "@nativescript/core";
Application.run({create: () => {
  const page = new Page();
  page.actionBar.title = "MiniApp Authoring Acceptance";
  const label = new Label();
  label.text = "MiniApp repair result " + answer;
  label.accessibilityIdentifier = "miniapp-authoring-result";
  page.content = label;
  return page;
}});
