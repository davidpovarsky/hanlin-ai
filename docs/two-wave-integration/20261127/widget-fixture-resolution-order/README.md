# Regenerate Widget samples after the original upstream resolution

## Observed cause

The original simulator job resolved the Expo host contract from 58.0.29 to 58.0.30 and built that resolved runtime. Its unchanged Counter archive still declared 58.0.29. The original exact Widget runtime compatibility guard correctly rejected installation. The retained resolution artifact contains the host-contract change and no Widget archive regeneration. Its authenticated ZIP SHA-256 is 3ee2460afb3457f840987bfe5a096b947226ac592a65a4e6ced5ea0004960040.

## Change

Each of the two existing simulator/device resolver steps now invokes the unchanged original Scripts/Widgets/build-sample-packages.mjs immediately after successful resolve-upstreams --apply. The existing set -euo pipefail and EXIT trap remain in place, so a failed resolution cannot proceed to the producer and a producer failure remains a failed step. The original git diff --binary capture and following always-upload retain the generated inputs.

The producer reads the actual resolved Expo package versions and produces eight archives in three existing mirrors plus the SHA256 manifest. All 25 outputs are already tracked, so the binary diff captures their actual changes. The checked-in archive bytes were not regenerated for this repair.

## Preservation and verification

Deleting only the two added producer lines recovers the entire original workflow. Every other parsed YAML value, original resolver command, pin, build/test selector, assertion and deadline remains unchanged. The producer itself is unchanged.

Two new controls in the existing Scripts/CI/Tests discovery passed, including eight negative subcases covering missing producer, reversed ordering, missing EXIT capture and missing artifact coverage in both jobs. The original full CI and native gates remain required. No native command was run in this source lane.

The workflow-only and controls-only commits are separate so the workflow can be published through the existing owner API route. Source review approves the change for the original native retry; it is not native acceptance evidence.
