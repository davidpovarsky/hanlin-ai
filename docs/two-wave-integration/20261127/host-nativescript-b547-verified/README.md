# Actual Host and NativeScript producer qualification

The original Host producer executed on `b5475156e7b0253b24c0a4385236b60da21f6f7e`. All **12 phases passed**, including **188/188 tests** with zero failures, cancellations or skips. The actual long-running Node job took **305,044.987583 ms**. The unchanged original packing and archive verification phases produced the recorded Host archive.

The original producer generated exactly four documentation files, sealed in `1d94b855ed58c692f028b55b6e14dacdd025fd80`. Independent review confirms that the fourth file only updates the unchanged `isBeta` source reference from line1980 to2023. The actual packaged SDK has **396 inputs**, fingerprint `7af6ecb6a4041d98d37bd71cf65fa9520ec93978e09ea8f7c9cfe4f1e0cad986`; every input matches the integrated Git source at `5c7e81d7cfaec125f4dee6b673c705f2851fd1bb`. Subsequent numeric-test/proof-only integration changes none of those inputs.

## Original strict NativeScript result

Both original CLI operations passed against that exact extracted SDK: validate in3.24s and build in4.21s, with the original300/600-second limits. All seven authored inputs and original CLI/paired-runner bytes matched the integrated source. The actual33,751-byte archive has18 unique ZIP members and passes CRC verification. Its18 generated files were atomically retained before source-cleanliness checks, without changing bytes.

The actual reports specify `strict: true`, `checkJs: false`, `skipLibCheck: true`, and `dependencyDeclarationsChecked: false`. This qualifies the authored TypeScript scope; it does not claim all SDK declaration libraries were typechecked.

## Evidence and limits

Root rehashed42 Host payload members,38 NativeScript payload members and4 imported-header probe members. The compact files here retain raw hashes, native phases, counts, exact source bindings and the original Host test log. The complete transferred packets remain preserved. The81MB Host archive remains on the Mac and was verified by its original native gate; root did not transfer and independently rehash that archive. Root independently verified the actual NativeScript archive and SDK input bytes.

The separate narrow UInt/XCTest imported-header probe passed after the installed Swift overlay search path was supplied. That does not qualify the complete corrected test file or any app/OS case. Original failed attempts and the initial root log-reader format failure remain preserved.

Application/runtime-origin/Widget/Shortcuts/VoiceOver acceptance, affected consumers, physical devices and release gates remain separate. No frozen engine work, assertions, pins or native deadlines were changed for this qualification.
