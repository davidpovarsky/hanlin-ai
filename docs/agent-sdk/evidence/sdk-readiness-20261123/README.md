# SDK source and host readiness — 2026-11-23

This audit binds immutable source f1f6d745b178b28fe26fe94434aae4e0f5bf4a7c. It does not relabel compilation or native tests.

The actual root manifest contains 44 public products, 108 distinct top-level targets, and all 507 tracked original application Swift files except its thin executable entry. The 18 original child manifests match the generated inventory. The public application, conversation, Composer and agent entry points call the original implementation; their exact source hashes and call sites are retained.

The three real installed consumers still pin 32da9e314e22bbf22391fcf8902302acfbb281e2. Every selected original byte and file mode matches that pin: Maktabah 545, Lorvex 535, Anytype 547. Their selected source change at the candidate is only the shared localization catalog: all 1,118 existing entries are unchanged, and nine added keys have no literal uses in their selected Swift. Child manifests, dependency graph and existing generated-profile receipts remain unchanged. These facts bound reuse of existing acceptance; they are not fresh Apple acceptance.

Final immutable source adoption and actual installer/check runs remain pending until the native producer and final source are fixed. Native publication remains blocked on completed successful producer 45218713371; all 11 original preparation inputs match its exact source 7f6a960e. Failed 45177292887 remains ineligible.

Historic native evidence retains its actual source: Maktabah 45125110974 (Host 48 plus one real no-send iPad route), Lorvex 45148401438 (one actual Composer route), and Anytype 45181802668 (UI route, observer acceptance separate). Current Anytype observer work is owned elsewhere on consumer 988f4519 and is not rerun here. Maktabah live-provider acceptance remains blocked: a fresh Actions secret-name metadata lookup found OTZARIA_LIVE_GEMINI_API_KEY absent; no value was read.
