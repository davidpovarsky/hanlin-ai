# Actual installed repair package and import presentation ownership

The focused19-v8 original repair case ran source 7bf0c2fdc2f7168d6b98dda66f443ae032fe1c11 with SDK19. The original AI build-for-testing passed in 135.76386762500624 seconds. The actual repair case failed after 467.930 seconds: 0 passed, 1 failed, 0 skipped; Xcode exit 65. Its failure at MiniAppAuthoringUITests.swift:110 is the Search Apps exists/enabled/hittable waiter. It is not the whole-case 600 or outer 915.964 timeout. This evidence retains that failed case.

## Real build, receiver validation and installation

The actual AI build job 74b7afb4 completed successfully with exit 0 in 104.485 seconds. The corrected archive is 7,247 bytes, SHA256 02d9e28ece89f212f18f65924a29bc43bdec3025d40122f0c070f02cded19396. Identical bytes exist in the build output and installation transfer; all 16 ZIP entries pass CRC verification. MiniApps then ran the original compiler on the received source: job 567cd014 completed successfully with exit 0 in 34.605 seconds.

The fresh transfer 56f463ee-f2a6-4f6c-ad43-7614f7dcf2b1 has an actual installed receipt at 14:48:36.843681 UTC, with installedPackageID install-script-d7e81598bd3fabb072c5e57c. Its exact receipt SHA256 is 2dea9f53e15c9f031a8ca0da56d733afbe71ffbe5c2e575852a5339c1067c90d. The actual failure screenshot and accessibility tree show the installed MiniApp Authoring Acceptance card in the catalog. This proves installation of this new transfer; it does not establish the subsequently required native result 42 or final agent marker, which the failed UI case did not reach.

## Observed presentation race and production correction

The receiver synchronization assertions passed. The original test tapped Import Done at elapsed 428.65 seconds and Add Done at 429.69 seconds, then could not interact with Search Apps. The final AX contains the real catalog card at line 66 and a Script Package presentation with hanlin-package-import-done at line 100 over the catalog. The actual screenshot 02386859-DA1F-4E19-BA08-A47BFAFD8720.png shows that empty importer covering the installed catalog.

Source review identifies the ownership race: the install-URL task awaited receiveImport, then checked only whether an importer was currently visible. If its original owner closed the existing importer while final publication/catalog work completed, the finishing task reopened a new empty importer.

Commit 43212054f21bf93440df961cc312d1307dc2da8c changes only HanlinMiniAppsApp/HanlinMiniAppsApp.swift. It captures the existing presentation state immediately before the await, and auto-presents after completion only if neither an initial nor a current importer exists. It preserves first-use presentation, errors and actual receipts while respecting dismissal of the existing presentation. The test file remains byte-identical 60a786ea3864a118710f8814a41f52cc454d35c71e4fb911b611a70ba5c2f565, including native 42 and final installed-receipt assertions. The production correction has not yet been executed in this packet.

## Accounting and provenance

All seven actual focused charges remain in their original receipts. Their math.fsum is 3820.004503627002 seconds. The original 3600 allowance and the separately recorded 400 continuation grant remain distinct; the total 4000 leaves 179.99549637299788 seconds. V8 itself charged 735.968727458996 seconds, and primary cumulative time is 19292.91627621104. Both V8 controller layers report empty cleanupErrors and sourceErrors; the owned simulator ended Shutdown.

The three complete immutable source packets and their byte-identical source receipts are retained. Overlapping packet files intentionally preserve their original relative paths and deduplicate as Git blobs. The original V8 controls/recovery, exact production patch, source bindings and derived timeline are included. SDK and original Mini build producer remain a2c8a1b1; the actual AI consumer is 7bf0c2fd. No next Mini build, Repair PASS, original52 PASS, NS5 or OS delivery is claimed here.
