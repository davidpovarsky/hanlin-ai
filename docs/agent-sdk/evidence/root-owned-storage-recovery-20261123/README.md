# Authorized root-owned duplicate extraction cleanup

On 2026-11-23 at 21:55:35 UTC, `/root/release_hosts` removed exactly the three root-owned duplicate selections explicitly authorized by `/root`. They were the selections inventoried in commit `39d79e96fa1d59f7b021f5692944b86e1a308daf`. This is temporary-storage recovery; no SDK source, test, runtime, or release acceptance is claimed.

The final preflight checked each preserved original ZIP size, SHA256 and CRC; the original authentication receipt hash; exact file membership of each selected extraction; byte identity of each file to its original ZIP member; regular files with one hard link; and no symbolic links. `lsof` found no open handles to any selected path. File identities were checked again immediately before removal. Every original ZIP and authentication receipt was rehashed after removal and retained unchanged.

| Removed duplicate selection under the central worktree | Allocated bytes removed |
| --- | ---: |
| `build/sdk-native-sendability-retry-20261123/compiler-failure/original-xcodebuild-simulator.log` | 10,600,448 |
| `build/sdk-native-expanded-20261123/native-export-evidence` | 9,809,920 |
| `build/sdk-native-unified-recovery-20261123/failure-readback/original-artifact` | 11,927,552 |
| **Total** | **32,337,920** |

Filesystem available space immediately before removal was 1,282,441,216 bytes and immediately after was 1,314,779,136 bytes, an observed increase of 32,337,920 bytes. Other authorized owners may modify the shared filesystem concurrently; these are observations, not a reservation of future space.

`preflight.json` records every exact path, member, hash, inode identity and open-file query. `receipt.json` records the completed removals, preserved originals and space observations. Original ZIPs, original acquisition/API receipts, sole native job logs, the receipt-bound schema probe executable, active inputs, and other owners' files were not removed. No additional deletion was performed.
