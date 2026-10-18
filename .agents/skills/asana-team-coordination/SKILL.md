---
name: asana-team-coordination
description: "Task coordination, evidence-based status updates, and verified completion across Asana projects."
---

# Asana Team Coordination Skill

## Purpose
Enables persistent named roles (Eitan, Noam, Maya, Roni, Tomer, Yael, Dana) to coordinate project management actions directly and truthfully in Asana, following `docs/ai-team/ASANA_POLICY.md`.

## Lifecycle & Procedures
1. **Task Start / Claim**:
   - Read the existing task, notes, comments, and linked PR.
   - Record logical role prefix and execution mode non-destructively: `[<Role> | <Specialty>] [MAIN_SESSION]` or `[<Role> | <Specialty>] [SUBAGENT]`.
   - Do not wipe existing descriptions or numbering (P0/P1, F/R IDs).

2. **Status Transitions**:
   - Supported explicit statuses: `BACKLOG`, `READY`, `IN_PROGRESS`, `READY_FOR_QA`, `VERIFIED`, `BLOCKED`, `AWAITING_OWNER_APPROVAL`, `DONE`.
   - Update notes or comment on significant phase changes.

3. **Cross-Role Handoff**:
   - Post one structured, human-readable comment:
     `[<Role> | <Action> -> <NextRole> | <NextAction>] <STATUS>; Mode: MAIN_SESSION | SUBAGENT; <PR / Branch / SHA>; Subagent: <conversation-id or NONE>; tests: <summary>; known risks: <risks>; next steps: <instructions>`

4. **Task Completion Criteria (`completed=true`)**:
   - Only set `completed=true` when that exact task's defined acceptance criteria have been verified with concrete evidence.
   - Evidence must include: repository, branch, exact commit SHA, executed tests/run IDs, logs/screenshots, execution mode (`[MAIN_SESSION]` or `[SUBAGENT]`), and verification scope.
   - **Hardware Rule**: Tasks requiring physical iPad hardware must remain open (`BLOCKED_DEVICE`) until verified on physical hardware. Simulator or build-only passes are not hardware acceptance.
   - **Owner Gates**: Releases, main branch merges, signing keys, and destructive migrations still require explicit owner approval.

5. **Operational Discipline**:
   - No continuous background polling. Read/write on-demand at task start, handoff, and completion.
   - Handle rate limits (HTTP 429) with bounded backoff.
   - Never log secrets or embed credentials in repository files.
