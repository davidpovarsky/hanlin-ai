# Primary RuntimeCore authenticated transfer

The actual fourth native preparation attempt passed the NativeScript generator check and rebuilt original ExpoModulesJSI using its own React Native 0.88.1 graph. It then stopped because the primary Mac GitHub CLI was unauthenticated. Raw state and log are retained; this is not an application test result.

The unchanged original `runtime_bundle_source.py` ran on the already authenticated Linux host and verified the successful same-repository producer, one live artifact, and the exact inner bundle checksum pinned in `RuntimeDependencies.lock.json`. The 86,253,335-byte inner ZIP was transferred without credentials and verified again by the same original function on the Mac. The authenticated outer artifact digest is metadata; the outer ZIP was not downloaded twice merely to retain it.

`prepare-runtime-core.sh` now accepts an explicit local `RUNTIME_CORE_BUNDLE_ARCHIVE`. It copies the file into its existing private work directory and runs the unchanged common native identity, archive, provenance, ownership-smoke and installation checks. The network alternatives remain the default when no local archive is supplied. Actual full common preparation and the 52 application cases are pending the next controlled resume.
