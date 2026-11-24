# Minimum guarded execution after final source admission

All commands below are prepared and NOT_RUN. Root owns the current Apple run and assigns the single eligible prepared-artifact acquisition. No failed producer can be used. Current0b40 is a reviewed source snapshot, not a final delivery pin;07431 adoption and the separately reviewed SDK02 candidate decision remain part of final source qualification.

1. Receive the root's original terminal run/jobs/artifact indices. Require completed SUCCESS at the exact assigned source, reconcile the original requested test identities/arguments, and select one unexpired hanlin-sdk-native-prepared artifact. Keep the actual producer SHA in its catalog. Authenticate the one downloaded ZIP's exact API size/digest, CRCs and safe member paths. Check free space before download and central-directory expansion before extraction; inspect the eighteen inner expansion sizes before full installation.
2. Use an isolated exact-producer checkout. Require full scope, no missing targets, fourteen framework/four support entries. Invoke the unchanged original verify_source_inputs against Git/materialized source, including the complete eleven-input set; do not add the separate metadata helper to that contract. Run the original archive verifier:

       python3 Scripts/SDK/native_artifacts.py verify --catalog PREPARED/native-artifacts.json --assets PREPARED

3. Once the producer and acceptance are admitted, run the original immutable publisher, with no allow-selected-targets option:

       python3 Scripts/SDK/native_artifacts.py publish --catalog PREPARED/native-artifacts.json --assets PREPARED

   It rejects conflicting existing assets and anonymously readback-verifies all eighteen URLs. The preceding producer-success guard is mandatory because the CLI does not query it itself. Preserve the original catalog producer; integrate the published catalog into docs/native-artifacts.json and regenerate using Scripts/SDK/generate_manifest.py only as required. Let the resulting final integrated commit be FINAL_SDK_SHA.
4. Make one fresh owned full-profile Host, lock FINAL_SDK_SHA and all44 product names from that exact manifest. Use the existing installer, then its original check and native source guard:

       python3 Scripts/SDK/install.py --host-root FULL_PROFILE_HOST --source-cache CANONICAL_SOURCE --cache OWNED_NATIVE_CACHE
       python3 Scripts/SDK/install.py --host-root FULL_PROFILE_HOST --check
       python3 FULL_PROFILE_HOST/Vendor/HanlinSDK/Scripts/SDK/native_artifacts.py verify-source --root FULL_PROFILE_HOST/Vendor/HanlinSDK --catalog FULL_PROFILE_HOST/Vendor/HanlinSDK/docs/native-artifacts.json

   Preserve receipts, complete selected-source/manifest identity, all fourteen native framework installations and four support groups, original Node source/archive validation and the existing AppIntents HostResources projection. The original cache naming is checksum-archive; authenticated exported archives may be hardlinked into that owned cache to avoid duplicate bytes. Size/hash validation and published URL readback still run unchanged. Installation is not a substitute for native execution.
5. In the three existing isolated Host descendants, preserve product selection and actual Host behavior, update only reviewed final lock/Gitlink/source-binding metadata, and run each original wrapper once plus its check:

       # Maktabah; Gitlink Vendor/HanlinSDK must equal its lock.
       python3 Scripts/CI/prepare-hanlin-sdk.py --sha FINAL_SDK_SHA --source-cache CANONICAL_SOURCE --output OWNED_INSTALL_RECEIPT
       python3 Scripts/CI/prepare-hanlin-sdk.py --sha FINAL_SDK_SHA --verify-only --output OWNED_CHECK_RECEIPT
       # Lorvex
       python3 apps/apple/script/install_hanlin_sdk.py --source-cache CANONICAL_SOURCE
       python3 apps/apple/script/install_hanlin_sdk.py --check
       # Canonical Anytype; destination Dependencies/Hanlin.
       python3 Tools/Hanlin/prepare_sdk.py --source CANONICAL_SOURCE
       python3 Tools/Hanlin/prepare_sdk.py --check

   Requalify the final generated dependency profile and changed source closure. Attribute historical48/6/UI results to their original tested commits; use the source-bound shared/native evidence for changed inputs. Preserve the external Otzaria live owner and SDK06 owner. Do not dispatch accepted scopes again merely to change a report label.

Use ubuntu-owned Git/gh. Oracle origin has mirror=true, so authorized pushes require the existing command-local mirror=false override plus an explicit refspec. Lorvex origin is boyugou/lorvex; publish only to the verified davidpovarsky fork URL. No release operation, installation, pin update, new watcher or test dispatch was performed while preparing this recipe.
