# Recovery of four owned temporary extractions

At 21:08:47 UTC on 23 November 2026, the release lane removed exactly the four reproducible extraction directories enumerated in `cleanup.json`, after explicit root authorization. Their earlier inventory is frozen in commit `e06deb943951ba517724bff38343adddd8ca30d4`.

Before removal, every extracted member was compared to the preserved authenticated ZIP and the original acquisition receipt. The file inventory had no additions or omissions; every byte/hash matched. The directories contained no active open files and no multiply linked files. After removal, each sole original ZIP and acquisition receipt was rehashed and confirmed intact. Git evidence and all other owners' files remain untouched.

The removed directories occupied 98,295,808 allocated bytes. Observed free space increased from 1,229,983,744 to 1,328,271,360 bytes, a gain of 98,287,616 bytes. The filesystem delta includes receipt overhead and may reflect concurrent activity; it is reported separately from the measured allocation of these four directories.

No native source, current build input, SDK installation, authenticated original ZIP, original acquisition manifest or committed evidence was removed. The decoded xcresult intermediates from the earlier AppIntents investigation were retained.

Each removed tree can be reconstructed locally by extracting its preserved `preservedOriginalZIP` to the recorded `extraction` path. No new network acquisition or test execution is required. The older evidence packets retain their original acquisition paths and hashes; those four extraction paths are now intentionally absent until reconstructed.
