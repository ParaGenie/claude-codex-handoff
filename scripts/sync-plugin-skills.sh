#!/usr/bin/env bash
# Sync skill files from repo root into .claude-plugin/skills/codex-handoff/
# so the plugin and bare-skill install paths stay in lock-step.
#
# Why: the bare-skill install (git clone repo ~/.claude/skills/codex-handoff)
# expects SKILL.md at the repo root. The plugin install (via marketplace)
# expects SKILL.md at .claude-plugin/skills/codex-handoff/SKILL.md. We
# maintain ONE source of truth (the root) and mirror to the plugin dir.
#
# Run this whenever you edit any of the 5 skill files at the repo root.

set -euo pipefail

cd "$(dirname "$0")/.."

DEST=".claude-plugin/skills/codex-handoff"
FILES=(SKILL.md spec-template.md rescue-prompt.md review-prompt.md CLAUDE.md.template)

mkdir -p "$DEST"

changed=0
for f in "${FILES[@]}"; do
  if ! cmp -s "$f" "$DEST/$f" 2>/dev/null; then
    cp "$f" "$DEST/$f"
    echo "✓ synced $f -> $DEST/$f"
    changed=$((changed + 1))
  fi
done

if [ "$changed" -eq 0 ]; then
  echo "✅ already in sync"
else
  echo ""
  echo "Synced $changed file(s). Remember to commit both:"
  echo "  git add ${FILES[*]/#/} $DEST"
fi
