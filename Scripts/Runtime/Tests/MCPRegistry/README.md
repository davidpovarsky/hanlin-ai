# Downstream MCP registry fixtures

These fixtures cover the versioned document, both legacy array forms,
primary-corrupt/backup-valid recovery, two corrupt copies, a genuinely empty
registry, and an intentional uninstall. The uninstall pair deliberately gives
the empty primary a higher generation than the stale non-empty backup; loading
must keep the deletion and repair the backup, never resurrect the server.
