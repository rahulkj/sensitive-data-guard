#!/usr/bin/env bash
# Removes the sensitive-data-guard skill installs and git hook installed by install.sh.
set -euo pipefail

SKILL_NAME="sensitive-data-guard"
GIT_HOOKS_DIR="${GIT_HOOKS_DIR:-$HOME/.git-hooks}"

echo "==> Removing skill links and canonical copy"
# rm -rf on a symlink removes just the link, not whatever it points to — safe to run
# on all of these whether they're old-style full copies or new-style symlinks.
rm -rf "${HOME:?}/.claude/skills/$SKILL_NAME"
[ -e "$HOME/.cursor/skills-cursor/$SKILL_NAME" ] && rm -rf "${HOME:?}/.cursor/skills-cursor/$SKILL_NAME"
[ -e "$HOME/.cursor/skills/$SKILL_NAME" ] && rm -rf "${HOME:?}/.cursor/skills/$SKILL_NAME"
[ -e "$HOME/.gemini/skills/$SKILL_NAME" ] && rm -rf "${HOME:?}/.gemini/skills/$SKILL_NAME"
rm -rf "${HOME:?}/.agent/skills/$SKILL_NAME"

echo "==> Leaving your customer denylist alone (it's your data, not this tool's):"
echo "    $HOME/.claude/sensitive-data-guard-customers.txt"
echo "==> Note: any per-repo Cursor rules installed via 'install.sh --cursor-rule <path>'"
echo "    (.cursor/rules/sensitive-data-guard.mdc in whichever repos you targeted) aren't"
echo "    tracked here — remove those files manually if you want them gone too."

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
