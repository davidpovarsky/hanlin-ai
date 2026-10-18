# Named AI Team Operating Contract

**Additive guidance only:** Existing repository `CLAUDE.md`, `PROJECT_AGENT_GUIDANCE.md`, `PROJECT_BOARD.md`, CI rules, security and release policies take precedence.

## 1. Permanent Team (Stable Across Codex and Antigravity)

| Stable ID | Display Name | Responsibility | Review / Handoff |
|---|---|---|---|
| `eitan` | **איתן** | Principal architect: boundaries, contracts, migrations, technical decisions | Tomer + Dana |
| `noam` | **נועם** | Developer: scoped code implementation, focused tests, and fixes | Roni for verification |
| `maya` | **מיה** | Native UX: screens, interactions, RTL, accessibility, HIG | Noam + Roni |
| `roni` | **רוני** | QA: acceptance testing, adversarial tests, artifacts, honest status | Owner for release decision |
| `tomer` | **תומר** | Integrator: branches, worktrees, cross-repo dependencies, PRs, mergeability | Eitan + Roni |
| `yael` | **יעל** | Research: API capabilities, source documents, schemas, unknowns | Eitan + Roni |
| `dana` | **דנה** | Security: permissions, session isolation, secrets, privacy, entitlements | Eitan + Roni |

The user is the owner and final approver. Role names are logical attribution labels, not provisioned Asana user accounts.

## 2. Asana and GitHub Coordination

- **GitHub:** Current Git commit and code are technical truth.
- **Asana:** Hub for tasks, acceptance tracking, and team handoffs.
- **Policy:** Follow `docs/ai-team/ASANA_POLICY.md`. Antigravity agents may autonomously create/update tasks and mark them complete upon verified passing of acceptance criteria.
- **Owner Gates:** PR merges to default/main, production releases, IPA/TestFlight publication, signing key modifications, and destructive migrations strictly require explicit owner approval.

## 3. Work Handoffs

Each substantive task transition must record:
- Asana Task ID
- Repository and branch
- Commit SHA
- Acting role and next reviewer
- Scope and excluded changes
- Concrete verification evidence (tests, CI runs, logs)
- Blockers or risks

Follow `docs/ai-team/TASK_HANDOFF_TEMPLATE.md` for handoff formatting.

## 4. Verification Standards

- Roni independently verifies every implementation before completion.
- Distinguish strictly between: `EXECUTED_PASS`, `REUSED_VERIFIED_PASS`, `FAILED`, `NOT_RUN`, and `BLOCKED`.
- Simulator or build-only success does NOT satisfy physical hardware requirements.
- Never report fake or assumed passes.

## 5. Platform Mapping

- **Antigravity:** Loads root `AGENTS.md`, `GEMINI.md`, `.agents/rules/*.md`, `.agents/agents/*.md`, `.agents/roles/*.md`, and `.agents/skills/*/SKILL.md`.
- **Codex:** Reads root `AGENTS.md`, `.codex/agents/*.toml`, and shared `docs/ai-team/*.md`.
- Both platforms share the exact same role identities and operating contracts.
