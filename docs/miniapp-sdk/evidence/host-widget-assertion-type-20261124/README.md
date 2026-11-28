# Hosted Expo widget equality construction

The static changed-test review found a definite type mismatch: the stored
state is a Swift Dictionary, while the compared HanlinValue.object case takes
HanlinObject. The single test change constructs that object using the existing
throwing public initializer. The equality assertion, expected value and all
surrounding real installed-package/consumer checks remain unchanged.

The previously executed primary-Mac constructor proof is reused only for the
identical real value API and construction expression, with source identities
recorded. No new compiler, test, app build or CI was run. That earlier proof
does not certify this XCTest method or the complete hosted target.

The separate requested HanlinWidgetUI static scope is also recorded: its only
Swift file is an unchanged re-export, with no changed bodies in the PR range.
This does not establish that its native module was emitted successfully.
