# Main reconciliation — 2026-11-26

This merge reconciles the immutable two-wave integration baseline `7f6af7536db3d2aa9ecc9eb51ec82293fc5db3bc` with GitHub main `595e9953e39e2d704f82bd2de31d2d7b369e68c8`. Their merge base is `37feac32bef465a6cf6395a0a4666b1a2a6fb68e`.

## Resolution

| Conflicts | Resolution and reason |
|---|---|
| `AGENTS.md` | Retain standing owner authorization, native architecture and strict evidence reuse. Preserve applicable Swift style from main and explicitly record the owner's current built-in ChatGPT team request. |
| `CLAUDE.md`, `PROJECT_BOARD.md` | Keep the integration versions byte-for-byte. Main contains older architecture/build guidance and an empty board template; it does not add a newer product fact. |
| Team router, Asana skill, `GEMINI.md`, six `docs/ai-team` documents | Retain main's truthful MAIN_SESSION/SUBAGENT attribution, independent-verification distinction and actual acceptance/security requirements. Apply the existing authorization and real ChatGPT invocation identifiers; do not restart a historical external team or invent a conversation ID. |
| `build-ios26-unsigned-ipa.yml` | Keep the entire original integration workflow byte-for-byte, including all selected test gates and existing Live Activity hooks. Main's change only added refresh hooks to the older build. |
| `check-runtime-dependency-updates.yml` | Keep the entire original integration producer byte-for-byte. Preserve main's dispatcher as `dispatch-runtime-dependency-updates.yml`, manually triggered, with identical jobs, inputs and permissions. Its duplicate weekly trigger is removed; the original producer retains the sole weekly schedule. |

The 14 conflicts resolve to 21 intended policy, workflow and diagnostic-helper changes relative to the integration baseline. All ten files introduced only on main are preserved byte-for-byte: seven Lorvex workflows, the Live Activity bridge, the independent upstream proof consumer, and the team diagnostic helper. Existing default-branch files removed from the newer product are not reintroduced merely because they remain on older main.

Git history confirms main's two-tier policy dates to October 19, while the integration authorization was updated November 18–19. The current November 26 owner request explicitly authorizes built-in parallel agents and milestone updates. Source age is recorded to explain the semantic resolution; it is not used to discard valid evidence or security requirements.

## Verification

The retained machine receipt is `validation.json`. The audit compares Git blob identity and file mode for every tracked input outside the 21 exact allowed paths and this new evidence directory. **17,132 other inputs are byte-identical**, including all application/library/test code, fixtures, dependency pins, manifests, project files, generated SDK inputs and original CI producer/build workflows. Their deterministic manifest SHA-256 is `73aa8317624eb319fe5ecdc92369a7055ec36735fec1ae7c6066eaf1b74fa244`.

The audit also parsed all ten added workflow YAML files, checked embedded Python/shell syntax, parsed nine team YAML frontmatters and seven TOML definitions, verified 32 required team files and relative Markdown links, and checked the staged diff for whitespace errors. It verifies that the retained dispatcher has identical jobs, input schema and permissions to main, and that only the original producer carries the weekly trigger.

To reproduce the bounded source audit from the repository root, with PyYAML available:

```bash
python3 docs/integration/main-reconciliation-20261126/verify_resolution.py HEAD
```

No native build or test ran as part of this reconciliation. Product and native acceptance inputs are unchanged from the specified integration baseline. Subsequent product changes in the root integration branch retain their own native obligations and evidence; this merge does not certify them. No workflow was dispatched, no release performed, and no Asana completion claimed by this child agent.

Independent review of this reconciliation is handed to the coordinating agent. The Wave 2 agent was occupied by an actual native runtime defect and is not counted as a reviewer.
