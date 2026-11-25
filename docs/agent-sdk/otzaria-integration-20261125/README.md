# Maktabah shared Hanlin integration - 2026-11-25

Merges current canonical SDK c309eb4028f905f0909777ce86e176ecdeb10251 with Maktabah lineage f8cf6ca543c5ceed05a60141644664c93e4565b4. Retains current MiniApps/source implementations and newer Markdown/NativeScript pins. The original module manifests and all matching tracked resolutions use verified Core 3f38f1302764635c9991d0d00fd7b12471a5373c. No engine or UI implementation is copied.

Actual Mac job_efa2cbfb43ad: generate_manifest.py and --check exited 0 in 13.76 seconds, retaining 513 original app sources, 113 targets and zero unresolved local package edges. Adjacent stdout/stderr contain the actual receipts. The root manifest changes only the Core revision; receipt input hashes bind the two edited module manifests.

This proves manifest generation and source integration only. Final Maktabah compilation, Hanlin Live and MiniApps native acceptance are pending. Prior Core4194 evidence remains bound to its original source; this merge claims no new runtime test pass. Other agents' active worktrees are unchanged.
