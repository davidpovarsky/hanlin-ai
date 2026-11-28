# Approved source-preservation transition

Source commit: e0c801a5012c2f79c95944d674b26baa61d79152. Base: c9908a25ebeda3562170f16d2cf852ec4fd788b1.

## Result and scope

This change explicitly admits the already-reviewed467cfcab APIManager system-instruction ordering repair under the original source-preservation guard. It keeps the immutable V2 contract and every original protected-source assertion. It does not retroactively pass the original failing method or establish native behavior acceptance.

The real source9a failure read226115 bytes with SHA256fa423e890c1447a77dd8c978bc3124e9385d12098b04aec472303562d312be25, exactly the approved current source. V2 still describes225611 bytes with SHA2561e65885f3fa5aa398cf6a315cd365705986f092de9838692eb305ce87dc78b12. All18 other protected files match. The original two issues and partial-run evidence remain bound in source-preservation.json; no whole-run terminal outcome is inferred.

## What changed

A separate1491-byte JSON amendment binds V2, one exact path/preimage/current tuple, approved commit467cfcab and the original reviewed patch. Its whole SHA256 is75c2332849daa13718451e8bdf6695901fe9e0af8176fbb70669d07523da2e8b. The existing test helper validates every amendment byte and authority field before replacing only that expected row. It cannot create expectations from source under test or accept arbitrary historical/current alternatives.

The amendment is copied verbatim through the original declared source-fixture producer. The unchanged canonical project function declares its one extra exact sandbox output,40→41. The existing affected-validation owner routes this contract to the original native source guard.

Both original Swift test bodies remain byte-identical. An exact inverse recovers the complete original test file. All364 original assertion lines,19 protected-source checks, seven identifier owners, three delegations, ChatandFile and V3.3 reference checks, selectors and deadlines remain. The original V2 file is still SHA256169e270d596fa000ce9cb043fa55f765cda62fd6043df49eb3bad8e2e160e6e3.

One additive native method checks that wrong preimage, wrong path, extra entry and byte mutation are rejected by the actual validator. Native compilation and all three OriginalSourceNonRegressionTests method outcomes remain NOT_RUN for this amendment.

## Executed validation

The original10 fixture-delivery controls plus one added actual-router control passed once:11 tests,0 failures,0 skips,0.258 seconds. Complete raw output is retained losslessly. This validates portable delivery, exact sandbox output coverage and routing; it is not Swift/native validation.

The initial generation attempt failed during import because the sparse checkout lacked unchanged ProductSplit dependencies. That result is retained. After their exact base Git sources were materialized, the original narrow function executed successfully. The source-fixture producer and project-generator implementations are unchanged; no full project generation or native command ran.

Root's independent review is retained verbatim. It verified the frozen26-member packet, applied the seven-file patch to actual base Git objects, checked its inverse, and bound the approved467 source transition. Source/SDK impact is static0/396 with unchanged production and package bytes; no new SDK/native PASS is claimed.

## Publication integrity

The source commit's seven files were re-read from actual committed Git objects and matched the reviewed hashes. The compact proof manifest lists only delivered payloads. The lossless patch and portable log gzip files are explicitly staged, and every proof payload must be re-read from the proof commit before handoff.

Original native source-guard execution and affected behavior acceptance remain required.
