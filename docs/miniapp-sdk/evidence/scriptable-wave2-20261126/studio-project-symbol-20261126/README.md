# Project symbol selection

The existing Studio appearance sheet let a user save a project SF Symbol, but the library row ignored the saved symbol and always displayed `curlybraces.square`. Color selection already worked. This is a correction to the existing Task10 control.

The row now displays the existing `FolderStyle.symbol`. The workspace style reader accepts a caller default only when metadata is absent. Unstyled projects retain `curlybraces.square`, unstyled folders retain `folder`, and a saved symbol (including an explicitly selected `folder`) takes precedence. The same default is supplied to the existing appearance sheet. The metadata schema, coordinated writes, editor contents, cloud-root lifecycle and source boundaries are unchanged.

The original eight Foundation workspace/lifecycle tests passed on Swift 6.4.3 Linux with the exact test source unchanged. Both modified source files passed Swift syntax parsing. The portable module contains the exact production Foundation workspace source and original tests; it supplies no replacement UI or runtime implementation.

No Apple/native UI execution is claimed. The existing Studio native inventory remains fourteen invocations. Actual selection, return to the library and reopening of the saved style remain part of the original Studio UI gate. No new native job was launched.
