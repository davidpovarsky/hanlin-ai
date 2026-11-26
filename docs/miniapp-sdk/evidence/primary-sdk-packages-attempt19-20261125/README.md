# Original SDK19 examples and intentional repair input

The existing native producer commands completed on consumer 62dfff9aebd0a272486c7770d4f77ba603d535ab using unchanged SDK19 produced at a2c8a1b1be746461272ba77254603304567c309d. The original 11-file packet is retained externally and bound by untouched receipt 1b282a1226b4234cea6628582c1a06604649084e4fb8406b213d8152d81a3895. All 11 files / 4,189,867 bytes were independently read and hashed on Oracle.

The three positive original CLI builds report strict checking, success and zero diagnostics. Expo uses the actual compiler API 6.0.3 with dependency declaration checking enabled; NativeScript uses original compiler 5.9.3 and its existing skipLibCheck=true policy. This does not claim NativeScript dependency declarations were checked. Every declared compiled member hash and all 50 positive project source hashes agree with the archive and exact consumer Git source. All 97 inner archive members were read with CRC checking.

| Original filename | Bytes | SHA256 |
| --- | ---: | --- |
| ModularTextSearch.hanlinExpo | 2203953 | 40ade14cf7ebcaa96d0f7bf71757d92a243236f682227c9683ebf06bc8255f6f |
| SDKOnlyDepartureBudget.hanlinExpo | 1956567 | dda4e3b1536426156d2695209736186f4d804895f0a04fb3741bbe24c5a4df1f |
| SDKOnlyTableShare.hanlinNativeScript | 12933 | 4d817ba5dd1c84fce5c0ae4b3d281929520dfaebbbe1dd41465d1ebe6305c4b3 |
| MiniAppTypeError.hanlinNativeScript | 4399 | 9a2a14be4ad24565bad66a98fc53522229de903acfb8a41b3df18006e81b51c9 |

The negative package intentionally changes source/index.ts after the actual valid build. Its actual source hash a0150df126fe244e9d1b49fee0fe10a11756569e8e82cfe4381584e30f79dcaa matches the original negative-validation proof, while the recorded valid source hash is 9ca13f866936891fd664e0001e366632c94fe2f069308ae6cca0cc09149a6101. The original report retains TS2322 at index.ts line 1, column 14 and MINIAPP_SOURCE_CHANGED. This is a source-bearing repair input, not a valid package claimed to import unchanged.

The observed current application container A977193C-753D-454C-97BE-544917CAE71C differs from original staging container 4AB09E58-6099-47DC-B2F2-2D0AF4B6B8D8 after XCTest installation. The producer receipt records both and binds the current source-bearing input to the original archive identity. No container path was guessed or silently substituted.

## Exact transport

Hanlin-MiniApp-Examples-and-Repair-2026-11-25.zip contains precisely the four original archives with their unchanged bytes/names and artifact manifest.json. It is 4,184,536 bytes / SHA256 149cd5ce63e41d4a78c346a1936aee367ca8d7aefa151bc22ff4595126537904. Six transport chunks are each at most 786,432 bytes and are listed in transport-manifest.json. Readback compared every inner original archive byte-for-byte. The deliverable bytes remain externally retained; Git contains their exact identities rather than another binary copy.

## Boundary

No compiler, generator, product edit, Mac query or native test was performed for this reconciliation or transport. The preserved producer reports' native-result fields remain unchanged. Current runtime acceptance, actual repair completion, OS notification delivery and physical-device proof require their own observed results; these archives are not signed native iPad host builds.
