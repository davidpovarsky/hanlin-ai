# Paired initial-input focus: bounded caller diagnostics

Original run45283243206@4cfa failed before Send: the actual editor accepted focus, then lost it before the first native PAIRED chunk. The original activity/AX/video/native console packet is paired-native-45283243206. No specific dismissing caller is established.

This change observes the existing original component and Host under both DEBUG/HANLIN_TESTING and the existing explicit HANLIN_COMPOSER_EDIT_DIAGNOSTICS=1 flag. The UITextView override captures at most24 caller symbols, each at most512 characters, records the same native object identity and before/after first-responder flags plus the Boolean result, and calls super exactly once. It does not log draft text, selection content or credentials. Existing coordinator diagnostics now include the same object identity for correlation. Existing Host native-focus and FocusState transitions are recorded without assigning state or changing callback order.

Every original text/state/layout action and the native return value are preserved. No delay, retry, programmatic focus request, test selector, test body, typing method, timeout or predicate changed. Outside diagnostic builds there is no responder override. With the runtime flag disabled, caller stacks and diagnostic prints are absent.

The two source preimages exactly match executed4cfa. Inverting only these diagnostic changes restores both original files byte-for-byte. Linux Swift parser PASS is syntax-only; native compilation and caller diagnosis are NOT_RUN. No diagnostic-only native job is planned: this instrumentation is intended for the next reviewed, already-required original two-case continuation, alongside the independently diagnosed product fixes. The passing original transfer/rollback case is preserved.

Apple's documented FocusState behavior updates the binding on focus entry/exit; absence of a manual Host assignment is therefore not treated as a proved defect:
https://developer.apple.com/documentation/swiftui/focusstate/
https://developer.apple.com/documentation/swiftui/view/focused(_:)

The same executed product also contained duplicate NativeMultilineTextEditor.Coordinator and MultilineInnerTextView images. That independently demonstrated link composition issue remains separate from the unproved focus-loss cause.
