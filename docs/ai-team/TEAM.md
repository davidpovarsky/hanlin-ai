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

## 2. חובת האצלה מעשית לצוות הסוכנים (Mandatory Subagent Delegation)

בכל משימת עבודה מהותית, חלה חובת האצלה תפעולית מחייבת:
1. **הסוכן הראשי פועל כמתאם בלבד (Orchestrator):** הסוכן הראשי קורא Asana, קובע סדר עבודה, מפעיל סוכני משנה מותאמים, מקבל תוצאות ומנהל מסירות. **חל איסור מוחלט על הסוכן הראשי לבצע בעצמו עבודת פיתוח, ארכיטקטורה או QA מהותית כדי 'לחסוך' האצלה.**
2. **האצלה מעשית באמצעות `invoke_subagent`:** יש להפעיל סוכנים מותאמים בשמותיהם (`eitan`, `noam`, `maya`, `roni`, `tomer`, `yael`, `dana`) באמצעות `invoke_subagent` (או להגדירם תחילה באמצעות `define_subagent` במידת הצורך).
3. **בחירה ממוקדת:** אין להפעיל את כל 7 הסוכנים בכל משימה; יש לבחור רק את הסוכנים הנדרשים לפי אופי העבודה.
4. **שער אימות חובה של רוני:** כל משימת פיתוח מהותית תועבר ל**רוני (roni)** לאימות עצמאי לפני סגירתה. משימות שחרור יכללו את **תומר (tomer)** ו**רוני (roni)**, וכן את **דנה (dana)** כשיש השלכות אבטחה ופרטיות.
5. **איסור ייחוס פיקטיבי:** חל איסור מוחלט לדווח שפעולה בוצעה על ידי סוכן (כגון `[נועם]` או `[רוני]`) אם לא בוצעה קריאת האצלה אמיתית אליו.
6. **שקיפות בדיווח כשל:** אם הפעלת סוכן נכשלת או אינה נתמכת, יש לדווח על כך במפורש ולא לטשטש זאת על ידי התחזות לסוכן.
7. **תיעוד מדויק ב-Asana:** כל עדכון יתעד במדויק מי הופעל, מה ביצע ומה אומת.

## 3. Asana and GitHub Coordination

- **GitHub:** Current Git commit and code are technical truth.
- **Asana:** Hub for tasks, acceptance tracking, and team handoffs.
- **Policy:** Follow `docs/ai-team/ASANA_POLICY.md`. Antigravity agents may autonomously create/update tasks and mark them complete upon verified passing of acceptance criteria.
- **Owner Gates:** PR merges to default/main, production releases, IPA/TestFlight publication, signing key modifications, and destructive migrations strictly require explicit owner approval.

## 4. Work Handoffs

Each substantive task transition must record:
- Asana Task ID
- Repository and branch
- Commit SHA
- Acting role and next reviewer
- Real subagent invocation record (conversation ID / execution evidence)
- Scope and excluded changes
- Concrete verification evidence (tests, CI runs, logs)
- Blockers or risks

Follow `docs/ai-team/TASK_HANDOFF_TEMPLATE.md` for handoff formatting.

## 5. Verification Standards

- Roni independently verifies every implementation before completion.
- Distinguish strictly between: `EXECUTED_PASS`, `REUSED_VERIFIED_PASS`, `FAILED`, `NOT_RUN`, and `BLOCKED`.
- Simulator or build-only success does NOT satisfy physical hardware requirements.
- Never report fake or assumed passes.

## 6. Platform Mapping

- **Antigravity:** Loads root `AGENTS.md`, `GEMINI.md`, `.agents/rules/*.md`, `.agents/agents/*.md`, `.agents/roles/*.md`, and `.agents/skills/*/SKILL.md`.
- **Codex:** Reads root `AGENTS.md`, `.codex/agents/*.toml`, and shared `docs/ai-team/*.md`.
- Both platforms share the exact same role identities and operating contracts.
