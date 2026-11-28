# Focused SDK19 environment and launcher recovery

This packet records the preparation failure and the environment/launcher corrections before the final focused native result. It does not claim any new native test pass.

## Immutable application and SDK inputs

Application source: `6c006c948f0a6f371f7fc68b90e393f43734f8dd`; tree: `ecd109e872e08873410a6bf55db697bd42864fa2`.
SDK19 was produced at `a2c8a1b1be746461272ba77254603304567c309d`. Its host archive SHA-256 remains `7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc`, manifest `4505c28495d8b6ecd1073254e0e395adcc898cc02dd1d40699591f51db4dee92`, and235-source input digest `ba8f3f1f09054887eed62532fa1d5ca2ac3bd60e6aa99a98ab1035c7653882a2`.

## Actual preparation failure

Focused19-v3 started at12:22:22.297370 UTC and finished at12:23:01.973504 UTC on2026-11-25. The original probe producer exited1 before the affected AI build or either selected UI case. The original declaration guard rejected the environment: the actual process used Node22.23.5 whereas both unchanged installed tooling receipts required Node24.5.0. The recorded comparison found the other input identities and all642 Expo package rows unchanged.

The attempt charged39.67624695900304 seconds. Cumulative active time became16856.44515633505; cumulative focused time became1383.5333837510116, leaving2216.4666162489884 of the separately recorded3600-second focused allowance. These are execution accounting values, not limits imposed on the application. The terminal source/cleanup error arrays were empty and the owned simulator was confirmed Shutdown.

The original15-member native failure packet and its receipt are retained byte for byte under `raw/environment-failure/`.

## Restore the original prepared Node runtime

The native owner restored the official Node24.5.0 darwin-arm64 archive into the existing owned tools directory. The official SHASUMS256.txt and publication identity are retained.

- Official archive:26194704 bytes; SHA-256 `8b6379059b3347a9d0335dd682b0ec9eb7888e1a9c8b23483d3dd2c32e744420`.
- Executable:116870064 bytes; SHA-256 `336b5b3ebc5deb86df842102b20b6e4761605b7a667823e68dda7761b91a161b`.
- Observed identity:24.5.0, darwin, arm64.
- Installed Expo and NativeScript receipts remained unchanged. No npm installation, receipt reseal or SDK regeneration was used to hide the mismatch.

Controllerv4/v5 explicitly bind that executable and compare its version, platform and architecture against both installed receipts before launching the child.

## Uncharged launcher rejection and narrow correction

V4 was rejected by a historical controller PID check before creating its native output or launching a child. Its charged time is0. The error log did not preserve the identity of the matched live process. At12:35:19.149327 UTC the follow-up found none of the six historical controller PIDs live. This packet therefore does not claim which process caused the original rejection.

V5 corrects that source-visible numeric-PID weakness: it excludes its own PID, checks the actual Python command and an owned control-script path, and reports the matching argv if an owned prior controller is still live. It does not terminate or reject an unrelated process based solely on a historical PID. The existing historical phase process-group checks remain unchanged.

The unchanged native child SHA-256 is `bfa992d6793451374eb847f9e0b0f4d28d32a153163ded9ae427acd0bfa5f478`. Controllerv5 is `d5fd2939cf2082d449ced62dd7e5b1c5107067280e6d36fa6f13689b0f54a4f8`.

## Bounded V5 startup observation

V5 actually started at12:39:49.505756 UTC. The retained12:42:45 observation records that original probe production and its TypeScript/Metro preparation completed, and the affected AI build was still running. This startup packet does not establish either selected UI outcome. Final focused and original25+27 acceptance belong to subsequent native result packets.

All included raw files are copied without content changes. The top-level receipt hashes every member except itself. Referenced original packet receipts retain their original schema and provenance.
