# NativeScript informational-message authority correction

The actual Apple run 45354885323 compiled and executed the eight selected modern import-contract methods: seven passed and one failed. The complete authenticated log is retained without alteration. This receipt does not convert that failure into a native pass.

The failure was in the test expectation, not the importer policy. The supported fixture requests @nativescript/core 9.1.0. The analyzer validates it against the generated Core version (currently 9.1.4), then reports the embedded iOS runtime version (currently 9.1.1). The previous expectation incorrectly inserted the Core version into the phrase naming the runtime.

The only test-source change binds that existing success-message expectation to HanlinMiniAppHostVersions.nativeScriptRuntimeVersion. The supported and unsupported fixtures, installability assertions and exact negative Core message remain unchanged. No product or workflow file changes.

Source hashes confirm the relevant analyzer, generated authority, generator and pre-fix test are identical between the executed source and this isolated base. The source corroboration records the distinct upstream package bindings and expected strings; it is not analyzer execution. The changed Swift file parses. The corrected Apple execution remains pending and is owned by root.

The evidence collector initially matched the aggregate failed-run summary as a second failed method. The collection was corrected to count quoted individual test names; the raw native log and test patch were not changed by that correction.
