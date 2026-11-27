# R2: bind all exercised embedded runtime images

Root's independent review found that R1 required the NativeScript image but did not require NodeMobile and Python even though the existing checkpoint had exercised both. R1 commit `6f6c37bac32add5982b56d4e250d76560d403c78` and its actual 14-test receipt remain unchanged.

R2 adds the actual `Frameworks/NodeMobile.framework/NodeMobile` and `Frameworks/Python.framework/Python` paths to the NativeScript checkpoint's mandatory product images. Each must be present in the actual bound process sample and match that attempt's current built/installed SHA256 and LC_UUID. The new control independently removes each image and changes each loaded UUID; all 15 controlled reader/protocol cases passed with zero failures/skips.

The source path is direct: NativeScriptHostServicesAdapter → HanlinRuntimeWireProtocol → HanlinRuntimeBroker → AppRuntimeCore.shared.node/python. NodeRunner calls `node_start` on a local NSThread; PythonRuntimeBridge calls the embedded Python C API in this process. The historical device report confirms only the two framework names. No historical device UUID/hash is reused for the new Simulator proof. JavaScriptCore remains a recorded platform image and is not mislabelled a producer-owned framework.

The Swift UI file and existing runner are identical to R1, so all 23 original method bodies, all original plans/selectors/assertions and budgets remain preserved. Only the observer's mandatory-image set and its controlled fixtures/negatives changed. There remains zero SDK392 intersection.

`runtime-topology.json` retains exact source hashes/excerpts and static-name attribution. `source-validation.json` binds the two-file delta and actual 15-test raw receipt. Native Swift compilation and the actual Simulator origin gate remain **NOT_RUN** for this candidate.
