# Original selected-profile identity — 23 November 2026

This receipt compares SDK `d49a4fd4115b8335105d2991bf74ab4d7f6aad2d`, used by the current real Lorvex, Maktabah/Otzaria and Anytype consumers, with integrated SDK `199b8c996f56097faf76a881efaf788c8e7d27a2`. It is a source-equivalence observation, not a new native test execution or a claim that any pending host UI gate passed.

The canonical original generator at each commit was evaluated for each host's actual locked product selection. Both outputs are byte-identical to one another and to that host's installed `Package.swift`. The complete tracked entries below each selected original source/resource path were compared with `git ls-tree -r -z`, including path, mode and Git blob identity. No selected path, source, resource or mode changed. Every profile still has zero binary targets.

| Actual host | Public products selected | Original selected tracked entries | Generated manifest SHA-256 |
| --- | ---: | ---: | --- |
| Maktabah/Otzaria | 8 | 544 | `2d5cf939b5c8f43f30ee2be1e382e5f52e13a3f4cd9fc66709cb4ee96c2f23e4` |
| Lorvex | 7 | 534 | `29c126b9305e88bbcaed57512374e986f7225a0c87d332950f6ba3deda9bca26` |
| Anytype | 8 | 546 | `518f91d40d3433a88ab6255c252bc2c81fa1e2199dad0322b4136bb7f2d6f20c` |

Counts here cover the selected implementation/resource paths, excluding installer bootstrap manifests, Xcode project metadata and generated inventory. They therefore differ from the larger complete sparse-install inventories maintained by the hosts. The full SDK has an added optional MiniApps UI product and changed aggregate/generator metadata; those changes do not alter the generated profiles used by these three hosts.

The [machine receipt](HanlinSelectedProfileIdentity20261123.json) records each exact product list, all original source paths and the complete source-tree record digest. A later repin can retain the applicable source-bound results only after that later candidate still matches this input closure, and after preserving the host's actual source, external resolution and test/runtime inputs. New native outcomes must keep their original executing host and SDK commit. This comparison does not manufacture a fresh PASS or qualify unrelated full-application, MiniApps, native distribution, live-provider or physical-device behavior.
