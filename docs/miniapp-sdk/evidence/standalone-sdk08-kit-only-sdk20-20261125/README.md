# SDK20 standalone authoring: original six-command replay

All six original SDK08 CLI invocations executed against the frozen SDK20 payload. Expo and NativeScript validate/build passed with zero diagnostics. Both deliberate negative invocations rejected the original TS2322 at index.ts:36:14 and produced no install archive or build stage.

The production carrier is 7f5dad540ade7fec6e5ace980eb99d1d6d0c2e8f; the SDK producer is dff3b45c99a57bf8fe8ec721db3fa1fafce7134b plus three original generator outputs recorded in the producer proof. SDK manifest: 6f11ed8da3df18627f05932d47b5b68dec54eb26ac396151a21cbc8c3e65800e. All 25,682 files including the manifest remained identical in bytes and modes before/after. Both unchanged production CLI files and all 22 original fixture files were verified.

No historical runner script was retained. The new operational replay harness implements the unchanged recorded argv, environment and strace commands; it does not claim an invented historical script identity. The actual six command records are retained. Node24.22.0/Linuxarm64 and Python3.12.3 are the standalone prerequisites, distinct from exporter Node24.5.0. The exporter utility only copied/extracted authenticated files; no SDK/source generator or npm install ran in this replay.

Complete file/process/network traces were reassembled by PID. No successful dependency or project reads outside the isolated kit, no repository fallback, and no internet calls were observed. Failed optional ancestor package probes and ordinary system/Python library access remain explicit in the trace audit.

Expo uses TypeScript6.0.3 with strict:true, skipLibCheck:false. NativeScript uses its original TypeScript5.9.3 consumer configuration with strict:true, skipLibCheck:true; dependency declaration internals are therefore not revalidated by those NativeScript authoring commands. The authored negative source was rejected by both validate and build. Both positive ZIP archives passed CRC/member/source/manifest checks.

This packet proves standalone authoring only. It contains no native execution, corrected app acceptance, notification OS delivery, physical-device execution or current full52 result. Historical SDK19 standalone and native proofs remain separate and unchanged. SDK20's transport-only record-copy ZIP may differ in compression bytes while retaining the same manifest and every payload member.

Raw originals remain under the source root named in raw/receipt.json. Larger JSON/syscall traces are stored losslessly as gzip, with exact original sizes/hashes in this receipt. No full SDK copy is duplicated in Git.
