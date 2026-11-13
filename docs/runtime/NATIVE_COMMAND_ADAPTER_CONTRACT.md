# Explicit native command adapters

`hanlin:runtime` extends the existing durable execution/command receipts. It does not create a second Node/Python/Shell engine or emulate Node's ChildProcess class.

```js
import { runCommand, openOutput, capabilities } from 'hanlin:runtime';

const result = await runCommand('python3', ['process.py', 'argument with spaces'], {
  cwd: process.cwd(),
  env: { ...process.env, OUTPUT_LANGUAGE: 'he' },
  stdinFile: 'input.bin',
});
// This is the actual command's exit status, including a nonzero status.
console.log(result.executionID, result.exitCode);
for await (const bytes of openOutput(result, 'stdout')) {
  // Consume the complete durable output with stream backpressure.
}
```

The same module works through synchronous `require('hanlin:runtime')` in CommonJS. It has no top-level await. Input is finite: `stdin` accepts a Node stream, string or byte view, or `stdinFile` names a regular file. Choose one input; no input means EOF. Relative file paths follow the actual execution workspace. Arguments preserve quoting boundaries and Unicode; NUL is rejected because native argv cannot represent it. Environment names/values retain the existing OS-validity checks and effective-scope precedence.

`runCommand(command, args, options)` accepts `cwd`, `env`, `stdin`, and `stdinFile`. It returns the actual `exitCode`, native `executionID` when a native job ran, `commandID`, `parentExecutionID`, `stdoutPath`, and `stderrPath`. Preview budgets do not discard those output files. A nonzero native exit is returned, allowing normal caller control flow; an unavailable/disconnected adapter throws. A rejected command can return the existing dispatcher error status without a native execution ID, and must not be reported as an executed job. `openOutput(receipt, 'stdout' | 'stderr')` opens the corresponding complete file as a readable stream.

Cancellation belongs to the original parent job and waits for the actual native command receipt. A running linked C call may finish naturally before interruption settles. The API does not accept a process signal or claim independent process/IPC/TTY behavior. Unsupported option names are rejected, never silently ignored. Background continuation remains optional OS admission for the original user operation; this module does not request it automatically.

| Need | Local route | Exact boundary |
| --- | --- | --- |
| Finite Node/Python script or installed JS/Python bin | `runCommand` through existing actors | Real argv/cwd/environment, file stdin/stdout/stderr, exit and durable job ownership; no separate OS process |
| Linked BSD utility | Same command receipt through ios_system | Only commands actually linked/registered; linked C cancellation cannot promise immediate termination |
| npm install/pre/main/post lifecycle | Original portable-shell interpreter and same command adapters | Original source, quoting, pipes, redirection, actual hooks, integrity and transactional publication retained |
| Worker thread | Native `worker_threads` | A thread in the app's process; not POSIX process isolation |
| `child_process.spawn/exec/execFile/fork`, sync variants | Full POSIX semantics require an owner server | No fake PID, ChildProcess, signal, IPC or TTY success |
| `cluster`, process IPC or interactive TTY | Owner server | No local substitute is advertised |
| Desktop `.node` extension | Compatible prelinked provider or owner server | An arbitrary downloaded desktop binary is not made compatible by changing a permission flag; no Node prelinked-provider registration contract exists yet |
| Persistent MCP server requesting native child commands | No inherited chat command port | `capabilities().finiteCommandsConnected` is false and execution throws; a server must not silently inherit another chat's owner |

Apple DTS explicitly distinguishes the iOS process restriction from macOS App Sandbox and states that iOS apps cannot spawn child processes. This is a documented platform constraint; the MCP compatibility guard is separately reported as a host guard. A portable test's guard rejection is not presented as a physical iPad OS enforcement test. [Apple DTS](https://developer.apple.com/forums/thread/747499). The linked library's own documentation explains its in-process command replacement and incompatible fork/exec semantics. [ios_system](https://github.com/holzschu/ios_system).

The authenticated `/v1/runtime/capabilities` endpoint reports the observed Node/V8 version, platform, architecture, compiled pointer representation, actual WebAssembly presence and selected Fetch transport, together with these installed routes. The original `get_runtime_capabilities` tool reads it only when Node has already launched, preserving stopped/failed engine status. An installed route is not a claim that every package or current native bundle has passed acceptance.

**Owner decision, 2026-11-10: local only, with iOS limitations reported explicitly.** External execution is **not configured and is outside this delivery**; a missing server is not an implementation blocker for the selected local scope. No code, files, credentials or package installation are transferred to a server. The unsupported POSIX/IPC/TTY/desktop-addon rows above remain explicit local limitations, not capabilities obtained by removing a guard. A future complementary route would require a new owner-configured endpoint, credentials, capability contract and ownership of the entire POSIX execution context.
