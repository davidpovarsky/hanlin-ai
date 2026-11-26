# Incoming composer and MiniSDK source fixtures

Status: **EXECUTED_PASS** at source `1710bc6119983799f7d22cb723659ac274fe96b1`.

- NativeScript app-image preflight: **9/9 Node tests passed**.
- NativeScript parity fixture: **5/5 Python tests passed**.
- The original Python fixture itself invokes the parity async-startup Node file: **15/15 nested Node tests passed**, executed exactly once.

Node24.22.0 and Python3.12.3 ran on Oracle Linux. All13 recorded original source/test/resource inputs matched their Git bytes before execution and remained unchanged afterward; the isolated tracked worktree remained clean. No test/assertion edits, dependency installs or native builds occurred.

The Python module was executed by the original unittest CLI through `runpy`. `observe_original_parity.py`, stored only with this evidence, passively observes the return of the original `subprocess.run` to retain its already-captured nested TAP output. It does not replace that function, change arguments/return values/assertions, or rerun the nested suite. The exact actual and delegated commands are in plan/receipts.

These are original source fixtures with synthetic Mach-O inspections/explicit VM bridge fixtures. They do not prove actual Apple/NativeScript runtime behavior, app/UI results or provider billing. Keep9 preflight,5 Python and15 nested Node counts distinct; one Python case is the Node suite wrapper.

See `receipt.json` for exact source/tree/toolchain/input/log hashes, case identities and timings. Initial sparse checkout omitted DemoMiniApps; only this isolated worktree-specific sparse selection was expanded before tests. Root integration files/configuration were not changed.
