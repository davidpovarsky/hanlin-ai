import { Application, Button, Color, Label, Page, ScrollView, StackLayout, Switch, TextField, } from '@nativescript/core';
import { dollars, readNonNegative, splitBill } from "./model.js";
export function createTableSharePage() {
    const page = new Page();
    page.actionBarHidden = true;
    page.backgroundColor = new Color('#F4F7FC');
    const scroll = new ScrollView();
    const content = new StackLayout();
    content.padding = 24;
    scroll.content = content;
    page.content = scroll;
    function label(text, size = 16) {
        const view = new Label();
        view.text = text;
        view.fontSize = size;
        view.textWrap = true;
        view.color = new Color('#152344');
        view.marginBottom = 10;
        content.addChild(view);
        return view;
    }
    function input(title, initial) {
        label(title);
        const field = new TextField();
        field.text = initial;
        field.hint = title;
        field.keyboardType = 'number';
        field.returnKeyType = 'done';
        field.autocorrect = false;
        field.fontSize = 20;
        field.padding = 12;
        field.marginBottom = 18;
        field.backgroundColor = new Color('#FFFFFF');
        field.color = new Color('#152344');
        content.addChild(field);
        return field;
    }
    const heading = label('Table Share', 30);
    heading.fontWeight = 'bold';
    label('Split a bill in USD. Tax and tip are calculated on the subtotal.');
    const subtotal = input('Subtotal · USD', '84.00');
    const tax = input('Tax · %', '8.5');
    const tip = input('Tip · %', '18');
    label('People at the table');
    let people = 3;
    const peopleRow = new StackLayout();
    peopleRow.orientation = 'horizontal';
    peopleRow.marginBottom = 18;
    const less = new Button();
    less.text = '−';
    less.width = 64;
    const peopleLabel = new Label();
    peopleLabel.width = 92;
    peopleLabel.fontSize = 24;
    peopleLabel.textAlignment = 'center';
    peopleLabel.verticalAlignment = 'middle';
    const more = new Button();
    more.text = '+';
    more.width = 64;
    peopleRow.addChild(less);
    peopleRow.addChild(peopleLabel);
    peopleRow.addChild(more);
    content.addChild(peopleRow);
    label('Round each contribution up to a whole dollar');
    const wholeDollars = new Switch();
    wholeDollars.checked = false;
    wholeDollars.horizontalAlignment = 'left';
    wholeDollars.marginBottom = 18;
    content.addChild(wholeDollars);
    const result = label('', 26);
    result.fontWeight = 'bold';
    const shares = label('');
    const breakdown = label('');
    const note = label('');
    note.fontSize = 14;
    const reset = new Button();
    reset.text = 'Reset to example bill';
    reset.marginTop = 14;
    content.addChild(reset);
    function update() {
        peopleLabel.text = String(people);
        less.isEnabled = people > 1;
        more.isEnabled = people < 12;
        const subtotalValue = readNonNegative(subtotal.text, 1_000_000);
        const taxValue = readNonNegative(tax.text, 50);
        const tipValue = readNonNegative(tip.text, 100);
        if (subtotalValue === null || taxValue === null || tipValue === null) {
            result.text = 'Check the amounts';
            shares.text = 'Use nonnegative numbers with at most two decimal places.';
            breakdown.text = '';
            note.text = 'Subtotal limit: $1,000,000 · Tax: 0–50% · Tip: 0–100%';
            return;
        }
        const bill = splitBill(subtotalValue, taxValue, tipValue, people, wholeDollars.checked);
        result.text = dollars(bill.totalCents) + ' total';
        if (bill.higherShareCount > 0) {
            shares.text = `${bill.higherShareCount} pay ${dollars(bill.higherShareCents)}; ${people - bill.higherShareCount} pay ${dollars(bill.lowerShareCents)}.`;
        }
        else {
            shares.text = `${people} ${people === 1 ? 'person pays' : 'people pay'} ${dollars(bill.lowerShareCents)} each.`;
        }
        breakdown.text = `Subtotal ${dollars(bill.subtotalCents)}\nTax ${dollars(bill.taxCents)}\nTip ${dollars(bill.tipCents)}`;
        note.text = bill.extraCollectedCents > 0
            ? `Whole-dollar rounding collects ${dollars(bill.extraCollectedCents)} extra. Decide together where that goes.`
            : 'The contributions add up exactly to the total; any remaining cents are distributed.';
    }
    subtotal.on(TextField.textChangeEvent, update);
    tax.on(TextField.textChangeEvent, update);
    tip.on(TextField.textChangeEvent, update);
    wholeDollars.on(Switch.checkedChangeEvent, update);
    less.on(Button.tapEvent, () => { people = Math.max(1, people - 1); update(); });
    more.on(Button.tapEvent, () => { people = Math.min(12, people + 1); update(); });
    reset.on(Button.tapEvent, () => {
        subtotal.text = '84.00';
        tax.text = '8.5';
        tip.text = '18';
        people = 3;
        wholeDollars.checked = false;
        update();
    });
    update();
    return page;
}
Application.run({ create: createTableSharePage });
//# sourceMappingURL=index.js.map