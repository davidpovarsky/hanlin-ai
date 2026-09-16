import { Property } from '../core/properties';
import { EditableTextBase } from '../editable-text-base';
export class TextViewBase extends EditableTextBase {
}
TextViewBase.returnPressEvent = 'returnPress';
/**
 * (iOS Only) Behavior for Apple Intelligence Writing Tools
 * @since 8.9
 */
export var WritingToolsBehavior;
(function (WritingToolsBehavior) {
    WritingToolsBehavior[WritingToolsBehavior["Complete"] = 0] = "Complete";
    WritingToolsBehavior[WritingToolsBehavior["Default"] = 1] = "Default";
    WritingToolsBehavior[WritingToolsBehavior["Limited"] = 2] = "Limited";
    WritingToolsBehavior[WritingToolsBehavior["None"] = 3] = "None";
})(WritingToolsBehavior || (WritingToolsBehavior = {}));
export const iosWritingToolsBehaviorProperty = new Property({
    name: 'iosWritingToolsBehavior',
    defaultValue: WritingToolsBehavior.Default,
});
iosWritingToolsBehaviorProperty.register(TextViewBase);
/**
 * (iOS Only) Allowed input for Apple Intelligence Writing Tools
 * @since 8.9
 */
export var WritingToolsAllowedInput;
(function (WritingToolsAllowedInput) {
    WritingToolsAllowedInput[WritingToolsAllowedInput["Default"] = 0] = "Default";
    WritingToolsAllowedInput[WritingToolsAllowedInput["List"] = 1] = "List";
    WritingToolsAllowedInput[WritingToolsAllowedInput["PlainText"] = 2] = "PlainText";
    WritingToolsAllowedInput[WritingToolsAllowedInput["RichText"] = 3] = "RichText";
    WritingToolsAllowedInput[WritingToolsAllowedInput["Table"] = 4] = "Table";
})(WritingToolsAllowedInput || (WritingToolsAllowedInput = {}));
export const iosWritingToolsAllowedInputProperty = new Property({
    name: 'iosWritingToolsAllowedInput',
    defaultValue: [WritingToolsAllowedInput.Default],
});
iosWritingToolsAllowedInputProperty.register(TextViewBase);
//# sourceMappingURL=text-view-common.js.map