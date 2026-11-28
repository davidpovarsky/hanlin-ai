# Paired command checkpoints — 2026-11-24

Scope: `run_paired_acceptance.py` command observations only, based on
`3a67bd43ed273a6948207e4db4e3ff446d2fa351`. Existing stdout/stderr already streamed
straight into the command log. The missing evidence was command identity and
progress before completion; this change does not attribute or fix external CI cancellation.

`command-events.jsonl` is a separate append-only, flushed/fsynced observation
journal. Every invocation has an ID, argv, log name, parent/child PID, actual
start/observation time, elapsed seconds, log bytes and timeout. A durable start
exists before launch; observations and flushed console heartbeats continue every
30 seconds. `active-command.json` is atomically replaced for convenient latest
state; later cleanup cannot remove prior unfinished journal entries. An abrupt
termination can leave the last observed running state; it is not a claim that the
process is still alive or that a native result exists. Completion is explicit.

The completed-only `commands.jsonl` fields, combined child-log streaming, cwd,
inherited environment, timeout values and exception policy are retained.
The POSIX `subprocess.run` lifecycle is expressed with `Popen.communicate` to
expose the real PID. No signal handler, process group, cancellation retry,
watchdog or altered native command is introduced. Python may not yet observe the
child exit immediately after KeyboardInterrupt; `observed_returncode: null`
remains truthful rather than inventing a completion.

## Executed portable evidence

`receipt.json` and `focused-tests.log` retain the first five-case execution:
four passed, while one SIGINT test made an incorrect immediate-reaping assumption.
Only that assertion/test observer changed; production was unchanged.
`assertion-correction.json` records the test/helper AST hashes proving all four
passing cases unchanged. The corrected single case passed in
`sigint-recheck/receipt.json` and its raw log. `summary.json` combines these
five distinct current cases without claiming they all ran in the second run.

The cases exercise actual child processes for pre-completion state, partial
output and flushed heartbeat, SIGTERM, cleanup after interruption, SIGINT,
success/environment/combined output, nonzero/allow_failure behavior, a signal
exit that must not be mislabeled timeout, and timeout kill/reap with the original
`-1` return policy. Tests accelerate only the heartbeat to 50 ms; production uses
30 seconds. All raw command logs, journals and observed states are retained.

`unchanged-native-command-comparison.json` proves all 35 `command()` call ASTs,
test plans/counts and all native/source-metadata code after the helper are
unchanged from the isolated base. Parent-owned later selector additions are
separate. No Apple build, simulator, CI dispatch or workflow/product edits ran.
