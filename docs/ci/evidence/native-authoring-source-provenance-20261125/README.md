# Native authoring support source validation

The SDK native installer previously projected only the Node Host sources and
runtime_host_archive.py into its validation directory. The original validator
also invokes Scripts/MiniApps/stage-sdk.mjs --fingerprint for an authoring Host.
That script and its input closure were missing from a sparse consumer.

The correction materializes exact Git source roots for the original fingerprint,
retains newly tracked inputs so stale support cannot silently pass, and invokes
the unchanged original archive validator. Four generated SDK documents are
projected only when their packaged bytes match both the SDK source inventory and
the packaged file inventory. Materialized document edits still reject.

The original fingerprint also includes all five prepared Widget resource files.
Node support therefore declares a dependency on the existing 40,471-byte Widget
support ZIP and installs it before Node Host validation. No Expo native framework
is selected. Old full catalogs remain usable because installation and checking
share the same canonical support closure; a selected catalog missing the carrier
fails closed.

The installer records exact ownership of only those five files. Pristine tracked
resources may be adopted after full equality checks; existing edits, additional
files, symlinks and changed managed output reject. Legacy ownership is upgraded
only after comparison with the immutable carrier. The complete extracted carrier
is validated before destination mutation. Upgrade restores only verified owned
outputs before switching source revisions.

## Evidence

qualification.json binds the changed files, original inputs and raw logs.

- The original implementation reproduced the missing fingerprint-script failure.
- The corrected provenance scope passed 13 cases, including real Git sparse
  installation, source drift, prepared-document tampering, missing support,
  legacy adoption, modified unmanaged files, safe upgrade and incomplete carrier
  rejection before mutation.
- The original native artifact scope passed 9 cases. Its selected-Node assertion
  now requires exactly the five Widget resource files and still excludes Expo
  native artifacts and unrelated runtime support.
- The unchanged installer lifecycle proof retains its original 11 passing cases.
- Genuine Host 052c7162 and Widget support e81c0643 passed the unchanged
  original validator against sparse source 705163fb in 3.882 seconds on Oracle
  Node 24.22.0. All 16 native preparation input hashes and both original producer
  scripts are identical in source705, the donor base and integrated source86d.

This evidence validates SDK source/archive consumption. It does not claim a new
native build, app UI acceptance, Host functional-suite run or catalog publication.
The newer Host module sources still require their original module-only sync;
the retained 052c archive is qualified here against its actual source705.
