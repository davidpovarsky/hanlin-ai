# Paired-product OS setup diagnosis — 2026-11-18

The two attempts at 00a932d63db76549dff0a228a6b75711fcad8a22 both built the original AI and MiniApps products successfully. Strict codesign verification and the actual Mach-O entitlements passed for both original App Groups. Neither run reached a test assertion.

- Run 44243200117: AI install exceeded its 180-second allowance (199.69 seconds including termination). The screenshot request also timed out.
- Run 44243208006: bootstatus took 142.08 seconds, AI install succeeded in 176.55 seconds, and the subsequent shared-container lookup exceeded 60 seconds. The captured SpringBoard screenshot shows the installed AI icon, with no foreground permission dialog. MiniApps had not yet been installed.
- The root OS service causing the stall is not established by these empty command logs. It is not evidence of a failed UI assertion, missing source entitlement, or permission from the owner.

The runner now boots its dedicated simulator before compilation so first-boot services can settle during the build. It installs both original products, starts each original bootstrap once, and resolves the real OS-provided App Group before terminating that warm-up process and starting XCUITest. The single install attempt has a bounded 300-second allowance grounded in the measured 176.55-second success; the OS query allows 180 seconds. No automatic reruns, sleeps, synthesized group directory, manufactured grant, signature stripping, or changed assertion is introduced.

Failure artifacts now include device state, installed applications, process names (without arguments), memory state and a screenshot. Exact command timings and hashes remain recorded. Both products must resolve to the same existing OS directory. The combined product_and_share scope still requires all eight actual native tests, zero failures and zero skipped tests.

This is an infrastructure correction pending native execution, not a phase acceptance or release decision.
