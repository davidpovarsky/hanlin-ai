# Match the actual notification delegate async requirement

The actual SDK14 MiniApps consumer build rejected the authored foreground notification callback: the installed iOS 27 Swift 6/C++-interop protocol imports its async presentation result as Int. The OptionSet-returning method also generated a near-match warning for the optional requirement, so merely converting the forwarded value would not correct protocol conformance.

This patch changes only the async return type to Int and the nil fallback to zero. It forwards the prior delegate's actual raw result unchanged, preserving every presentation bit. Zero retains the existing no-foreground-presentation behavior when no previous delegate implements the method. Event admission, response/settings forwarding, actor boundaries and service-extension behavior are unchanged.

The sole native owner reported an actual warnings-as-errors signature check, including an explicit Objective-C selector check, passed in 6.732447667 seconds with exit 0 and zero diagnostic bytes. Its exact source identity and limits are recorded in native-proof-reference.json. This commit does not manufacture a raw test result; the immutable raw packet is a separate follow-up.

The shared delegate is an explicit one of the 234 SDK14 source inputs. Normal Host/SDK preparation must therefore refresh its fingerprint and generated provenance before the affected MiniApps and AI consumer builds. Original package/framework producers and notification queue tests have no source change from this two-line correction. The original paired cases and actual OS delivery remain pending.

source-binding.json contains the exact before/after source bytes and mode identities and the real SDK14 input row. The source author performed no compiler, generator, native query, test, or product packaging operation.
