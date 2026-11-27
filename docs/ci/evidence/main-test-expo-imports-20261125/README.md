# Restore the native unit target's Expo import context

## Reproduced failure

The original Main403 build-for-testing stopped in AI_HLYTests with native exit 65.
The retained producer is 403076f1da0c61752e7950911cd9edffd9ad8d3b, terminal receipt
59606bb85639eb7fe657dcaa572ada2143062b3cb8c8d6f4263243e6e1fcc490 and build log
f77fe3ffaecf30c69da26d0c9e93888d03e6d984cc657d9e7483ad27f0504d7d.

The actual AI_HLYTests swiftc command at log line 4613 has no Expo artifact include or
framework search paths and no explicit-module-build option. The generated
Config.xcconfig sets SWIFT_ENABLE_EXPLICIT_MODULES=NO. By comparison the original
AI_Hanlin package compilation uses explicit modules.

The first missing headers are ReactCommon/CallInvoker.h, RCTDeprecation/RCTDeprecation.h,
yoga/Yoga.h and yoga/YGConfig.h. A bounded read-only inspection verified all four
as regular files under the current ReactModularHeaders directory. The authentic
source package already supplies the corresponding import paths. Recreating
headers or downloading native artifacts is not justified by this failure.
The later ExpoModulesCore Swift interface compiler-version diagnostic follows
those Objective-C module failures; it does not independently establish a toolchain
incompatibility.

## Source correction

The canonical project generator now applies its existing ExpoWidgets producer
import contract to AI_HLYTests as well as the original widget host. It retains
the producer's C++ mode, definitions and complete paired -Xcc flags, translating
only repository absolute paths to $(SRCROOT), and enables explicit modules for
the native consumer.

Only AI_HLYTests Debug and Release project objects change, and only
OTHER_SWIFT_FLAGS and SWIFT_ENABLE_EXPLICIT_MODULES differ. App and test bodies,
fixtures, assertions, deployment settings, native bytes, package products and
source ownership are unchanged. Existing widget settings are byte-for-byte
unchanged.

## Executed portable verification

The extended existing source-contract regression first failed for both missing
AI_HLYTests configurations on the baseline. After canonical generation, the
same test passed and checked all six Debug/Release configurations across
AI_HLYTests, HanlinScriptingWidgets and HanlinMiniAppsWidgets.

Commands:

- python3 Scripts/SDK/update_project.py
- python3 -m unittest discover -s Scripts/SDK/tests -p test_widget_cxx_imports.py -v
- python3 Scripts/SDK/update_project.py --check
- git diff --check

The existing source-graph validator passed with 514 application sources, the
single AI_HLY.swift executable entry point and HanlinApplication as the sole
application product linked by the app and its unit target. Parsed project-object
comparison proves the narrow two-configuration delta.

The original portable run logs, exact source-file hashes and actual native
compiler/header observation are retained in the adjacent JSON files. A reporting
wrapper initially misread the graph validator's successful dictionary return as
an error; that reporting assumption was corrected without rerunning the passed
checks or changing their source.

## Remaining native obligation

Apple compilation and runtime acceptance of this correction are NOT_RUN in this
donor. Root owns the next original build and all nine original cases. The compiler
settings changed, so the earlier four unit passes remain genuine producer
evidence but the prior unchanged-compiler reuse qualification does not cover this
candidate. No build, UI, physical-device or TestFlight success is inferred here.
