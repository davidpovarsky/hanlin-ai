# Notification observer continuation: retained environment failure

The external notification observer continuation `notification-os-v3` stopped with `KeyError: 'SPLIT_EVIDENCE'` after its owned simulator setup. It started at 19:17:14.219337 UTC and finalized at 19:17:27.160829 UTC on 2026-11-25, retaining its actual 12.940106750000268-second charge.

This is a controller failure before the original selected XCTest command was recorded or invoked. A test child process was created and then terminated during owned cleanup; the packet confirms the absence of a selected-command file, finalized xcresult, worker log and observation directory. No notification push or delivery outcome is established by this attempt.

## Exact cause and retained state

The new parent-side container observer imported the unchanged original paired runner. That original module reads `os.environ["SPLIT_EVIDENCE"]` at import. The controller had prepared that value in the environment passed to its children, but had not provided it to the parent-side import. The parent therefore failed before observing a fresh test handshake. The controller retained the exception text; it did not retain a full traceback, and none is manufactured here.

The proposed correction supplies the actual evidence directory only for the helper import and restores the previous environment. It does not edit the original UI test, original worker, application source or SDK. A subsequent attempt has separate controls, decision and terminal evidence.

All owned process groups were absent after cleanup and the owned simulator was Shutdown. Source and cleanup error lists were empty. The actual current MCM identities and old handshake remained unchanged; the retained old active exchange is not presented as a fresh one.

The original 900-second OS observation allowance remains cumulative. The first attempt's 353.58866224999656 seconds and this attempt's 12.940106750000268 seconds total 366.5287689999968 seconds, leaving 533.4712310000032 seconds. The intervening `notification-os-v2` preflight rejection was uncharged and is retained separately in this packet.

## Evidence

[packet/receipt.json](packet/receipt.json) authenticates 42 exact members with stored and raw SHA-256 identities. They include the actual v3 decision/state/ledger, current primary state, controls, setup and event logs, unchanged current-container observation, and v2 preflight rejection/decision/launch/seal history.

The earlier selected UI timeout caused by stale container binding is retained in the sibling `notification-os-container-rebinding-attempt19-20261125` folder. The full52 and five-runtime PASS packets remain independent and unchanged.

This folder was assembled by copying finalized records and verifying every stored and decompressed member. Its assembly ran no new native test, build, import, push or product mutation.
