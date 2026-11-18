# Original Profile sheet test navigation — 2026-11-18

Source review of MainTabView and HanlinWorkspaceActions confirms that the approved Profile entry is now a native sheet with hanlin-profile-done. Its stable launch identifier hanlin-settings-tab remains available in the original workspace toolbar. Chat and Library are the only primary tabs.

Two old test navigation helpers could attempt to tap a primary tab behind the still-present sheet. They now use the real existing Done control, assert its usability and actual dismissal, and then perform the original primary navigation. Agent settings navigation also requires the actual stable settings list instead of discarding its navigation wait result.

This changes test interaction to the authorized product navigation. It does not add a product shortcut, inject navigation state, relax draft/history/receipt assertions or fake a provider/tool result. These affected original methods are included in the pending native UI acceptance plan; source review and Swift parsing are not reported as runtime proof.
