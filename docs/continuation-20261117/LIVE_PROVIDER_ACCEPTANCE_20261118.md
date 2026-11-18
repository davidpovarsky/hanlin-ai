# Original live-provider acceptance — 2026-11-18

## Current status
IN_PROGRESS; not accepted until the actual selected iOS UI case and original runtime receipt pass. The current connected development host contains an existing Google/Gemini credential. Only its presence and HTTP status were inspected; no value is included in source, launch arguments, reports or artifacts. The earlier missing-live-credential statement is superseded. A direct current-model HTTP 200 proves connectivity only, not Hanlin acceptance.

## Product path
The dedicated Debug/simulator opt-in seeds the original APIKeys, AllModels and ChatRecords models in a fresh isolated SwiftData store. It does not enable the fixture URLProtocol. All requests use the existing HanlinChatEngine, canonical GoogleProvider and original HostIntegration. Shipping Release behavior is unchanged.

The selected original-app UI test asks live Gemini 3.8 Flash for the original execute_local_python_code tool. Before Allow Once, it reads the actual native consent JSON and permits only the exact harmless script containing a fresh conversation UUID. It verifies native output and a cold-reopened conversation with its unsent draft and no repeated consent. The runner separately requires one successful original CPython 3.14.6 job receipt containing that UUID and the computed value, plus the selected native test result with no skipped execution.

## Existing credential delivery
Only the existing owner credential is used, through a dedicated temporary repository secret. The staging step installs the actual original product in the job-owned simulator, verifies its bundle identifier and OS data container, then writes one 0600 private input. Ownership is recorded before any credential write. The app consumes that input once; normal user stores are not accessed.

The finishing step removes only this job's freshly owned simulator even if assertions fail. Artifact upload is restricted to allowlisted metadata, selected test results, summary and the bounded non-secret runtime witness. Raw app databases, credentials, diagnostic transports and binary result bundles are not exported. A literal secret scan must authorize the allowlisted upload; all detected secret-bearing files are removed, and upload is disabled if sanitization fails. The temporary repository secret is removed after the native gate has finished.

No product/provider outcome is declared from source compilation, HTTP connectivity or a mock response.
