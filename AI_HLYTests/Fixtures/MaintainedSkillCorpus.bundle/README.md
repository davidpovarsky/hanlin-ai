# Maintained Skill corpus

This corpus contains 23 independently named, maintained packages. It reuses the original pinned OpenClaw revision already used by Hanlin policy integration and three existing Hanlin product Skills. No generated fixture is renamed or counted as a maintained Skill.

## Source and license lock

- OpenClaw: https://github.com/openclaw/openclaw/tree/847611dcaa3bf0e2783335f961dd1fd0580e4d9f/skills (tag v2026.11.3): 20 complete selected Skill directories, 39 Skill files plus the original root MIT license. Every selected file was retrieved by its original Git blob and checked against the complete recursive tree; corpus.json records SHA-256, Git blob SHA-1, and length.
- Hanlin: https://github.com/davidpovarsky/hanlin-ai/tree/e0089cfb8c192530056aba39c7c8bbf945da75d3/Skills : the original yochai-study, torah-photo-study, and cairo-genizah-research directories, including the corrected Cairo error path. The original Hanlin MIT license is retained.
- openclaw/skill-creator/license.txt remains the unchanged Apache-2.0 notice shipped in that original package. Both repository MIT notices are under licenses/.
- Manifest SHA-256: d280d4c87a4068484ae5e046a667391d3c2b22026f630539efb81ff440995114. The Swift test pins this exact digest and checks every selected file against both hashes before import and after store reopen. Editing source content requires updating its actual upstream pin and reviewable lock.

## What the native tests prove

For each of the 23 named packages, the test creates a ZIP containing the original package bytes, uses the real SkillImporter, installs into an isolated SkillStore, registers its real catalog entry, verifies original bytes, and requests passive compatibility plans. Engine snapshots and the runtime-job reporter must remain unchanged during import and passive planning. These are original maintained packages; only their ZIP container is constructed for the test.

An explicit operation then applies the unchanged original OpenClaw policy. Packages whose actual native requirements are satisfied must load, expose their exact resource text, and reach the real SDK instruction-preparation path. Packages with unobserved/missing requirements remain unavailable. Disabling an available package removes its instructions, and same-process store reopen preserves the original files and enablement. This is persistent-store evidence, not a cold process or physical iPad claim.

The native test starts the original Python engine explicitly before checking python-debugpy, so python3 has an observed fact. apple-notes, apple-reminders, github, gog, himalaya, model-usage, notion, openai-whisper-api, tmux, and trello remain unavailable under the existing restricted native fact scope. Their native OS/command/environment results are recorded exactly; the test does not equate an iOS host with macOS or invent missing credentials. A primaryEnv field is not converted into a required environment variable.

For maintained scripts, explicit trusted AST inspection is recorded separately from passive compatibility. Analysis or instruction VERIFIED must not become an execution receipt. Optional modules, sibling modules, standard-library facts, host commands, and runtime resource paths remain visible limitations. The Cairo cases submit only an empty-argument request; if the current plan blocks execution, the witness says BLOCKED_BY_CURRENT_PLAN and requires no fabricated receipt. If the plan permits it, the actual original Python path must return usage, exit 1, empty stdout, and durable failure logs. No API request occurs on that argument path.

## Reading acceptance evidence

Require 23 MAINTAINED_SKILL_CORPUS witnesses with these exact names and manifest digest, plus the two MAINTAINED_CAIRO_INVALID_INPUT witnesses. Preserve each action readiness, issue and missing/unobserved fact. Green XCTest alone must not be reported as successful execution of 23 external workflows. Every witness explicitly leaves external_business_workflow and physical_ipad as NOT_RUN. The separate portable Cairo regression checks actual transport/JSON failures without contacting the service.

The 10 built-in system descriptors and generated parameter fixtures are not added to this maintained-package count. This corpus does not certify email delivery, calendar edits, Notion/Trello writes, API transcription, host-terminal control, image generation, or any remote account operation.
