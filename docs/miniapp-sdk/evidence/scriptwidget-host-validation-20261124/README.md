# ScriptWidget host declaration consistency repair

The initial Apple run built the production ScriptWidget target successfully and executed both selected tests. Both failed during production manifest setup with `Invalid network host declaration: *.`: **0 passed / 2 failed**. The element-limit assertions were not reached. This is an executed failure, not NOT_RUN.

## Cause and minimal repair

`HanlinOriginalScriptWidgetSession` synthesizes `networkDomains = ["*"]` for packages without an original manifest. The already installed `ScriptWidgetNetworkPolicy.isValidDomainDeclaration` and host matcher deliberately support this unrestricted host default. `WidgetPackageManifestValidator` instead duplicated the original inline pattern and rejected the same declaration. The fixtures did not introduce the wildcard.

The native validator now calls that existing policy. The policy implementation, host matcher, package permission checks, push URL matcher, host-generated manifest, original execution limits, frozen legacy implementation, and both Apple test bodies are unchanged. This is an explicit Hanlin call-site adaptation; bare-wildcard support is not claimed to be byte-identical upstream behavior. The original ScriptMetadata Git blob `37a4fb37cbb73a43da3e505e675c185068476ea9` and upstream identity remain in the source manifest, with `byteIdentical: false` and the exact adapted local hash.

The existing authoring semantic generator includes the called helper in its fingerprint and its unchanged native source in schema provenance. The public JavaScript semantic mapping mirrors the same syntax rule, so native and authoring validation agree. The existing refresh path retains local adaptations for unchanged upstream and uses a three-way merge or explicit conflict on advances. No new generator or refresh policy was introduced.

## Verification performed

| Check | Result | Boundary |
| --- | --- | --- |
| New host syntax regression before fix | 0/1 pass; failed on `*` with `SCRIPTWIDGET_INVALID_NETWORK_DOMAIN` | Actual public validator using the retained exported TypeScript parser |
| Affected schema/provenance, host syntax, and semantic drift tests | 3/3 pass | Both changed-validator and changed-helper drift reject stale mapping |
| Exact installed Swift helper and matcher | 4 valid declarations accepted, 9 malformed declarations rejected, 7 matching cases pass | Functions extracted byte-for-byte and executed with Linux Foundation; not Apple runtime acceptance |
| Changed native source | Syntax parse pass | No native module linking or Apple test execution after this fix |
| Generated schema | Regenerated; checked by affected test | Manifest shapes/types unchanged; only authority/hash metadata changes |
| Retained source identities | Seven relevant files byte-identical to base | Includes both Apple test files, host session, actual network provider/matcher, original runtime, refresh script, and generated type declarations |
| Independent source review | No blocker reported by entrypoints | Read-only review; no duplicate tests or CI |

The test command is recorded verbatim in `manifest-policy-green.command.json`. It selects only the three affected cases in `Scripts/MiniApps/Tests/scriptwidget-manifest.test.mjs`. The parser comes read-only from the frozen SDK kit and reports TypeScript 6.0.3. This is a focused check of the changed repository mapping, not a claim that a newly staged shipping SDK or full authoring CLI was rebuilt here. Node reports 24.22.0; Swift reports 6.4.3 on Linux aarch64.

## Native evidence and remaining acceptance

Initial run: `45360272675`, job `138328276796`, source `74ba980dbb91f3a38d4531f043801f5e742c283a`.

The full original job log is retained losslessly as `native-45360272675-job-138328276796.log.gz`; decompressed bytes: 164349; original SHA256: `57ae57e89b98e3993a8b6b4b41cf5a38420efe3b718131f21d95e0b4216c70ae`. `initial-native-failure.json` contains exact line-numbered build/test/error rows verified against those bytes. The original dispatch, run metadata, and retrieval receipt are copied without alteration from root's retained evidence. This agent did not contact or dispatch CI.

Root must rerun the same selected Apple cases after integration:

- `HanlinDualWidgetEnginesTests/scriptWidgetUsesOriginalElementLimitsWithoutExtraMaterialQuotas`
- `HanlinDualWidgetEnginesTests/rootFragmentsPreserveOriginalElementAllowances`

**After-fix Apple acceptance remains NOT_RUN in this receipt.** Initial native failures remain preserved. The separate original-cap provenance and deadline/root-normalization proof in `../scriptwidget-original-limit-parity-20261124/receipt.json`, and the independent SDK-only authoring experiment, are frozen and unmodified.

`source-provenance.json` records exact before/after source hashes and unchanged inputs. `receipt.json` records results and all evidence hashes; `SHA256SUMS` covers the receipt as well. Raw red output is compressed losslessly to retain diagnostic whitespace.
