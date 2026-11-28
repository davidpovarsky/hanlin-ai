# SDK20 original whole-run: omitted test fixture prerequisite

This is the actual failed original whole-run on source `7f5dad540ade7fec6e5ace980eb99d1d6d0c2e8f`, not an acceptance pass. Both consumer builds exited zero. The original MiniApps result has 25 passed, zero failed and zero skipped; AI has 25 passed, two failed and zero skipped. Both failed HostServices cases stop at the original XCTest fixture-existence assertion before executing their fixture. Runtime warnings and original failure logs are retained unchanged.

The current original repair UI case passed, including the existing controlled HTTP model-response boundary; it does not turn the whole run into a pass. SDK20 input/manifest/Host, all 235 source inputs, consumer and native binary guards remained unchanged; controller cleanup recorded no error or remaining owned process. The owned simulator was shut down.

The measured failed run consumed 2501.629630375013 seconds from its 14400-second allowance. Recovery preparation and subsequent validation must retain this failed attempt and its elapsed charge. A later result must be a separately identified complete original run, never a sum of selected passing cases.

`packet-receipt.json` retains native-to-Oracle transport bindings. `verification.json` independently verifies all 15 stored payloads, lossless decompressed bytes, actual 25+27 case nodes, original summaries and source/cleanup state. This checkpoint does not claim current NS-five or corrected actual OS notification acceptance.
