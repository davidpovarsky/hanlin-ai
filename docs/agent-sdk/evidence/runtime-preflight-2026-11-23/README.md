# RuntimeCore preflight: actual source membership instead of textual spelling

Original run45112778130 at e33247fbaca62e76227e99fe0bd8c7a3d1716f2c failed in preflight, before SDK native export, dependency resolution or app compilation. Original logs and artifact digests are retained; this is not a successful native producer.

The original guard searched for the unquoted substring Downstream/RuntimeCore/Node/Host/node_modules,. The SDK project updater preserved that exclusion, but wrote the valid OpenStep spelling "Downstream/RuntimeCore/Node/Host/node_modules" , instead. The exact original producer project fails the old textual guard and passes the new source-aware validation.

The replacement uses the existing original project parser. It finds the unique AI_Hanlin target, its registered synchronized AI_HLY group and that group's target-specific membership exceptions. It accepts an actual exclusion of node_modules or its ancestor. A comment, another target's exception, an unregistered group, a sibling path or one child of node_modules cannot qualify. All original runtime pins, binary architecture, ZIP, resource and manifest checks remain unchanged.

Four focused methods / eight cases passed once. The exact producer project was independently passed through the command-line validator. Shell syntax passed. No native runtime was rebuilt, no previous product tests were repeated and no new CI was dispatched.

The aggregate SDK declares an explicit source whitelist: no Node/Host source path is selected, and the prepared RuntimeHostResources.zip remains a copied resource. This is source selection, not a separate exclude array. The original Apple run's Host packaging already completed153 tests:152 passed,0failed,1skipped, with archive a2641a191aa0aca4350fd8e272c79a83eaa4f85314e1cd77dc0aaa463ef2c39a. Those results retain their original source and are not relabeled as a new run.

The successful early FoundationModels declarations artifact was extracted on Oracle, digest-verified and handed to the presentation owner. It records only reading the installed Xcode27.2/SDK27.2 public interface; model availability and model execution were not tested.
