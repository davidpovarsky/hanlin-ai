# Required Widget metadata in the ownership test fixture

The first native execution on ed4a6207 passed both retained import regressions and failed all eight newly added ownership controls before their intended checks. Each control reported DecodingError.keyNotFound for actions.

HanlinWidgetPackageMetadata has four nonoptional Codable properties: abiVersion, sourceFormat, actions, and families. The shared synthetic fixture provided three. Its Swift initializer's default empty actions array does not make the synthesized JSON decoder accept an absent field.

This test-only correction supplies "actions": [] in mixedPackage(). Removing that one field restores the entire previous file byte-for-byte. All eight test bodies, every assertion and issue call, both retained import tests and their exact archives, production code, and the 396 SDK inputs are unchanged.

## Qualification

The retained native attempt remains **2 PASS / 8 FAIL**, exit 1. It does not qualify the eight behaviors. This source seal performs only exact-byte and source-contract verification; no Swift, native, or portable test was rerun. The same ten-method native selection is required after integration.

The complete immutable native packet is retained as retained-import-ed4a6207-two-pass-eight-fixture-fail. Its manifest and original log hashes are recorded in qualification.json. The earlier two-FAIL native baseline is also preserved separately. No result is relabelled.

source.patch.gz is a lossless gzip of the exact Git patch. All created files and directories use the established task owner.
