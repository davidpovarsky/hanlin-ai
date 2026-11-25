# Native List delete confirmation query

The actual SDK18/source f33 EditButton case failed at line769 after the native minus control had already revealed a visible Delete confirmation. The exact failure accessibility tree and screenshot show that UIKit places this button beside the swiped Cell under the List CollectionView. The existing query looked inside that Cell and therefore could not see the button. The initial row-label query remains valid; it is not the cause of this later failure.

The primary reviewer read the complete case log and accessibility tree and viewed the actual screenshot. The native Delete button is visible, but this failed run did not activate it or complete deletion. The observed callback count stays0 and both alpha/beta rows remain.

The isolated correction c954d9a21b6789368305548e8e2502a6aada7131 scopes the confirmation query to the actual list, identified by its stable Original editable list header. All original edit-mode, removal, exact callback count, remaining-row, return-state and selector assertions stay unchanged. The existing10-second wait also stays unchanged. No application implementation, fixture, original library or capability changes.

The correction has passed source review and git diff checking only. Corrected native compilation and the original test remain NOT_RUN at this evidence snapshot. The contemporaneous full MiniApps result is22PASS/3FAIL/0SKIP; its other two failures concern TextEditor and are tracked separately. This packet does not promote the original52 result or infer AI27 success.

The four raw members are byte-for-byte retained producer records; analysis.json binds the source correction and the precise observed boundary.
