# Expo Widgets C++ consumer configuration

Main native run11 failed while emitting HanlinScriptingWidgets: the original
ExpoWidgets module was compiled with C++ interoperability, but its direct
consumer was not. The original producer manifest is byte-identical to the
failed run and is unchanged by this correction.

The source package now configures both the direct consumer and public
HanlinWidgetUI re-export with the producer's actual C++/Clang import contract.
They keep Swift6; the original producer's Swift5 setting is not copied.
The existing unified package generator preserves the two target settings.

The project generator reads the original producer's evaluated import flags and
configures the original widget executable. Its existing MiniApps extension
cloning path carries those settings to the independent widget executable.
Only OTHER_SWIFT_FLAGS and SWIFT_OBJC_INTEROP_MODE change in four configurations.

The focused real-manifest/project regression records the missing settings
before the fix and passes after it, including original flag parity and project
regeneration idempotence. This is configuration evidence, not an Apple build.
Root retains the complete authenticated native failure and owns the next run.

Authoritative build setup:
https://www.swift.org/documentation/cxx-interop/project-build-setup/
