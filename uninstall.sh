#!/usr/bin/env bash
# Removes the sensitive-data-guard skill installs and git hook installed by install.sh.
set -euo pipefail

SKILL_NAME="sensitive-data-guard"
GIT_HOOKS_DIR="${GIT_HOOKS_DIR:-$HOME/.git-hooks}"

echo "==> Removing skill installs"
rm -rf "${HOME:?}/.claude/skills/$SKILL_NAME"
[ -d "$HOME/.cursor/skills-cursor/$SKILL_NAME" ] && rm -rf "${HOME:?}/.cursor/skills-cursor/$SKILL_NAME"
[ -d "$HOME/.cursor/skills/$SKILL_NAME" ] && rm -rf "${HOME:?}/.cursor/skills/$SKILL_NAME"

existing_hooks_path="$(git config --global core.hooksPath || true)"
if [ "$existing_hooks_path" = "$GIT_HOOKS_DIR" ]; then
  git config --global --unset core.hooksPath
  echo "==> Unset git config --global core.hooksPath"
else
  echo "==> core.hooksPath is not set to $GIT_HOOKS_DIR, leaving your git config alone"
fi

rm -f "$GIT_HOOKS_DIR/pre-commit"
echo "==> Removed $GIT_HOOKS_DIR/pre-commit"
echo "Done."
