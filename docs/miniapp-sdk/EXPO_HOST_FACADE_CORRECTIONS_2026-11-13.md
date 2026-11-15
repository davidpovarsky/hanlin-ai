# Expo host facade corrections

[נועם | DEV] [MAIN_SESSION], SDK-04/INT-06, same implementation branch.

The existing `hostServices.readFile` treated an empty Base64 string as a missing
file. It now returns an empty `Uint8Array` for an actual zero-byte file and null
only for an absent/null native result. Its existing native API and storage scope
are preserved. The Swift facade regression writes/reads/deletes actual empty
and binary files through `ExpoHostServicesAdapter.invoke`, and distinguishes a
missing file. Actual native execution of this new case is still **NOT_RUN**.

The existing SDK runtime types now expose native `outputFiles` descriptors
(path/byte count/SHA256) and allow an omitted deadline while retaining the
required preview-byte budget. These declarations match current Swift Codable
fields; they do not create an artifact readback/cancellation API. Artifact paths
are not a grant to read another package's storage.

The local package peers and its one workspace lock entry now match the tooling's
existing Expo58.0.0/React19.3.0/RN0.88.0 pins. No package resolution, resolved
version, integrity, SDK engine or generated UI bridge changed.

The exact previous production TypeScript source at91f8c0d4 reproduced the
empty-file→null error in a local transpiled execution. Current production source
passed empty/binary/missing/null and native-rejection checks. The native module
in that harness is an explicit fixture; this is **not** real Expo/Hermes, Metro,
iOS or physical device acceptance. The ephemeral harness and output are under
ignored `build/verify-expo-host-file-wire.mjs`. SDK-04 remains open for strict
full SDK type/Metro and actual JS→module→native coverage across documented APIs.
