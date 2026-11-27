# Long-running NativeScript fixture diagnostic repair

The original shipping-SDK authoring command rejected the newly authored NativeScript fixture because its strict declarations do not expose a global console. The failure occurred before NativeScript build; the two Expo authoring operations had passed. The complete original outcome and raw report hashes remain recorded in SOURCE_PROOF.json.

The source repair imports the existing public Trace export from @nativescript/core and sends the same diagnostic message through Trace.write with its public error category and error type. The actual shipped implementation sends that error through its existing writers before normal filtering; its default writer preserves error visibility. The throwing Trace.error API is not used.

The listener, current window identity, invocation token, nonce, evidence writes and catch behavior are otherwise byte-preserved. No compiler options, DOM declarations, package pins, runtime product code, existing fixture bytes or SDK inputs change.

The independent reviewer and integration owner approved this exact two-line repair. This proof records source qualification and the retained failed attempt. Subsequent original strict validate/build results remain separate native evidence; no OS execution is inferred here.
