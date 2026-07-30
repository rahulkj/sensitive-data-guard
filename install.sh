#!/usr/bin/env bash
# Installs the sensitive-data-guard Claude Code / Cursor skill and its companion
# machine-wide git pre-commit hook. Safe to re-run (idempotent).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="sensitive-data-guard"
GIT_HOOKS_DIR="${GIT_HOOKS_DIR:-$HOME/.git-hooks}"
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help)
      echo "Usage: $0 [--force]"
      echo ""
      echo "  --force   point git's global core.hooksPath at $GIT_HOOKS_DIR even if"
      echo "            it's already set to something else"
      echo ""
      echo "Env vars:"
      echo "  GIT_HOOKS_DIR   where to install the hook (default: \$HOME/.git-hooks)"
      exit 0
      ;;
  esac
done

echo "==> Installing Claude Code skill"
mkdir -p "$HOME/.claude/skills"
rm -rf "${HOME:?}/.claude/skills/$SKILL_NAME"
cp -R "$SCRIPT_DIR/skill" "$HOME/.claude/skills/$SKILL_NAME"
echo "    -> $HOME/.claude/skills/$SKILL_NAME"

CURSOR_SKILLS_DIR=""
if [ -d "$HOME/.cursor/skills-cursor" ]; then
  CURSOR_SKILLS_DIR="$HOME/.cursor/skills-cursor"
elif [ -d "$HOME/.cursor" ]; then
  CURSOR_SKILLS_DIR="$HOME/.cursor/skills"
fi

if [ -n "$CURSOR_SKILLS_DIR" ]; then
  echo "==> Installing Cursor skill"
  mkdir -p "$CURSOR_SKILLS_DIR"
  rm -rf "${CURSOR_SKILLS_DIR:?}/$SKILL_NAME"
  cp -R "$SCRIPT_DIR/skill" "$CURSOR_SKILLS_DIR/$SKILL_NAME"
  echo "    -> $CURSOR_SKILLS_DIR/$SKILL_NAME"
else
  echo "==> Cursor not detected (no ~/.cursor), skipping Cursor skill install"
fi

echo "==> Installing git pre-commit hook"
mkdir -p "$GIT_HOOKS_DIR"
cp "$SCRIPT_DIR/hooks/pre-commit" "$GIT_HOOKS_DIR/pre-commit"
chmod +x "$GIT_HOOKS_DIR/pre-commit"
echo "    -> $GIT_HOOKS_DIR/pre-commit"

existing_hooks_path="$(git config --global core.hooksPath || true)"

if [ -z "$existing_hooks_path" ]; then
  git config --global core.hooksPath "$GIT_HOOKS_DIR"
  echo "==> Set 'git config --global core.hooksPath' to $GIT_HOOKS_DIR"
elif [ "$existing_hooks_path" = "$GIT_HOOKS_DIR" ]; then
  echo "==> core.hooksPath already points here, nothing to change"
elif [ "$FORCE" -eq 1 ]; then
  echo "==> Overriding existing core.hooksPath ($existing_hooks_path) with $GIT_HOOKS_DIR (--force)"
  git config --global core.hooksPath "$GIT_HOOKS_DIR"
else
  echo ""
  echo "==> NOT changing your git config — core.hooksPath is already set to:"
  echo "        $existing_hooks_path"
  echo "    The hook was installed at $GIT_HOOKS_DIR/pre-commit, but git won't run it"
  echo "    machine-wide until core.hooksPath points there. Either:"
  echo "      - merge $GIT_HOOKS_DIR/pre-commit into your existing hooks at"
  echo "        $existing_hooks_path, or"
  echo "      - re-run this script with --force to switch core.hooksPath to"
  echo "        $GIT_HOOKS_DIR (it still chains to any repo-local"
  echo "        .git/hooks/pre-commit, but won't chain to hooks living in"
  echo "        $existing_hooks_path)"
fi

echo ""
echo "Done. Sanity check: in any repo, 'git add' a file containing"
echo "  AKIAABCDEFGHIJKLMNOP"
echo "and try to commit it — it should be blocked."
