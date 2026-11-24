# Table Share

An original SDK-only NativeScript Core MiniApp. Edit subtotal, tax and tip, change the group from one to twelve people, and optionally round contributions up to whole dollars. Totals use integer cents. Uneven-cent splits explicitly show both contribution amounts; round-up mode shows excess collected. Invalid or out-of-range inputs show a correction message. Reset restores the editable example.

Source entry: index.ts. Calculation module: model.ts.

The project tsconfig only selects authored files. Compiler policy and dependency resolution come from the supplied SDK. No extra dependency installation, suppressions or compiler overrides.

Portable validation/build evidence does not establish native launch, installation, layout or interaction success.
