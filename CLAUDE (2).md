## Cost and token budget — mandatory

API usage is paid per token. Minimize model calls aggressively.

### Agent behavior

- Do not poll background jobs repeatedly.
- When a long-running build, CI run, download, or acceptance test has started:
  - start it once;
  - record its process/run ID;
  - do not repeatedly inspect logs while it is healthy;
  - wait for completion or inspect only after failure/completion.
- Never use repeated "sleep -> check -> reason -> check again" agent loops.

### Context discipline

- Never reread the whole repository.
- Never reread files already inspected unless they changed.
- Prefer `rg`, `git diff`, `git show`, targeted `sed` ranges, and failed-log excerpts.
- Do not ingest entire GitHub Actions logs.
- Do not summarize files merely to keep yourself oriented.
- Keep working notes concise.

### Build/test discipline

- Do not run expensive validation speculatively.
- Identify the root cause before rerunning CI.
- Run the narrowest relevant test first.
- Do not rerun passing expensive tests unless affected code changed.
- Never rerun full corpus acceptance unless indexing semantics changed.
- Never start heavy acceptance while fast CI is red.

### Background jobs

For long-running operations:
1. Start the operation.
2. Tell the user exactly what command/run was started and its ID.
3. Stop active agent work while it runs.
4. Do not monitor it continuously.
5. Resume investigation only when the user asks or when completion/failure is available without repeated polling.

### Scope

- Implement only the requested task.
- Do not proactively investigate unrelated improvements.
- Do not perform optional refactors.
- Do not continue with "while I'm here" work.
- Once the requested Definition of Done is satisfied, stop.

### Reporting

- Do not provide a live diary.
- Do not repeatedly restate prior context.
- Report only:
  - a newly discovered blocker,
  - a decision requiring the user,
  - a failed validation and its root cause,
  - final results.

### Model usage

- Use Sonnet by default.
- Do not switch to Opus unless explicitly authorized by the user.