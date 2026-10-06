#!/usr/bin/env bash
set -euo pipefail

[[ -f PROJECT_BOARD.md ]] || { echo "Missing PROJECT_BOARD.md" >&2; exit 1; }

found=0
for instructions in AGENTS.md CLAUDE.md GEMINI.md CODEX.md .github/copilot-instructions.md; do
  if [[ -f "$instructions" ]] && grep -Fq 'PROJECT_BOARD.md' "$instructions"; then
    found=1
    break
  fi
done

if [[ "$found" -ne 1 ]]; then
  echo "No authoritative agent instruction file references PROJECT_BOARD.md" >&2
  exit 1
fi

echo "Project board validation passed"
