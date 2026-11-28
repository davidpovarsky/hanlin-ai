# GroupBox children fallback

The public GroupBox declaration already accepted normal React children, but the
wrapper replaced them with explicit named-slot JSX. The retained failing test
executes that exact wrapper and observes the missing content slot.

The generator and both shipped TypeScript mirrors now use a default binding:
content = children. Missing or undefined content uses normal children; explicit
content, including null, false, zero or an empty string, takes precedence. The
label slot and native GroupBox implementation are unchanged.

The same original-React/TypeScript wrapper regression passes after the change.
A portable compile of the actual generator core and replay of its recorded
production inventory proves that its affected TSX output equals both checked-in
mirrors byte-for-byte. Full SwiftPM/Apple execution was not performed here.
The existing native GroupBox case is strengthened in the integration lane.
