#!/usr/bin/env bash
# Installs the sensitive-data-guard Claude Code / Cursor skill and its companion
# machine-wide git pre-commit hook. Safe to re-run (idempotent).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="sensitive-data-guard"
GIT_HOOKS_DIR="${GIT_HOOKS_DIR:-$HOME/.git-hooks}"
FORCE=0
YES=0
CURSOR_RULE_TARGET=""
CURSOR_RULE_SWEEP_ROOT=""

args=("$@")
i=0
while [ "$i" -lt "${#args[@]}" ]; do
  arg="${args[$i]}"
  case "$arg" in
    --force) FORCE=1 ;;
    --yes) YES=1 ;;
    --cursor-rule)
      i=$((i+1))
      CURSOR_RULE_TARGET="${args[$i]:-}"
      ;;
    --cursor-rule-sweep)
      i=$((i+1))
      CURSOR_RULE_SWEEP_ROOT="${args[$i]:-}"
      ;;
    -h|--help)
      echo "Usage: $0 [--force] [--cursor-rule <repo-path>] [--cursor-rule-sweep <root>] [--yes]"
      echo ""
      echo "  --force                    point git's global core.hooksPath at $GIT_HOOKS_DIR"
      echo "                             even if it's already set to something else"
      echo "  --cursor-rule <dir>        also copy the Cursor rule into <dir>/.cursor/rules/"
      echo "                             (one repo — see NOTE below for true global scope)"
      echo "  --cursor-rule-sweep <root> find every git repo under <root> and copy the rule"
      echo "                             into each; prints the list and asks before writing"
      echo "                             anything unless --yes is also passed"
      echo "  --yes                      skip the sweep confirmation prompt"
      echo ""
      echo "Env vars:"
      echo "  GIT_HOOKS_DIR   where to install the hook (default: \$HOME/.git-hooks)"
      echo ""
      echo "NOTE: Cursor's actual global 'User Rules' live in its own Settings UI backed by"
      echo "internal state (verified: not in settings.json, not a discoverable key in its"
      echo "globalStorage state.vscdb, no CLI flag for it) — there's no file this script can"
      echo "safely write to for that. For true global scope, open Cursor -> Settings -> Rules"
      echo "and paste in the contents of:"
      echo "  $SCRIPT_DIR/cursor-rule/sensitive-data-guard.mdc"
      echo "--cursor-rule-sweep is the closest safe automation: per-project files across"
      echo "every repo under a root, instead of editing Cursor's global state."
      exit 0
      ;;
  esac
  i=$((i+1))
done

# find_git_repos ROOT — prints one repo root per line (the parent of each .git dir found),
# skipping directories that are either huge/irrelevant on macOS (Library, caches) or
# would just waste time being descended into (dependency dirs, .git internals).
find_git_repos() {
  local root="$1"
  find "$root" \( \
      -path "*/Library" -o -path "*/.Trash" -o -path "*/node_modules" \
      -o -path "*/.cache" -o -path "*/.npm" -o -path "*/.cargo" -o -path "*/.rustup" \
      -o -path "*/.nvm" -o -path "*/vendor" -o -path "*/.git/*" \
    \) -prune -o -type d -name ".git" -print 2>/dev/null \
    | while IFS= read -r gitdir; do dirname "$gitdir"; done
}

# Single canonical copy under ~/.agent/skills, symlinked out to every tool below — so
# there's one place to update instead of N full copies drifting apart.
AGENT_SKILLS_DIR="$HOME/.agent/skills"
echo "==> Installing canonical skill copy"
mkdir -p "$AGENT_SKILLS_DIR"
rm -rf "${AGENT_SKILLS_DIR:?}/$SKILL_NAME"
cp -R "$SCRIPT_DIR/skill" "$AGENT_SKILLS_DIR/$SKILL_NAME"
echo "    -> $AGENT_SKILLS_DIR/$SKILL_NAME"

# link_skill TARGET_DIR TOOL_LABEL — symlinks TARGET_DIR/$SKILL_NAME to the canonical
# copy, replacing whatever was there before (an old full copy, or a stale symlink).
link_skill() {
  local target_dir="$1" tool_label="$2" link_path
  mkdir -p "$target_dir"
  link_path="$target_dir/$SKILL_NAME"
  if [ -e "$link_path" ] || [ -L "$link_path" ]; then
    rm -rf "$link_path"
  fi
  ln -s "$AGENT_SKILLS_DIR/$SKILL_NAME" "$link_path"
  echo "==> Linked for $tool_label"
  echo "    -> $link_path -> $AGENT_SKILLS_DIR/$SKILL_NAME"
}

link_skill "$HOME/.claude/skills" "Claude Code"

CURSOR_SKILLS_DIR=""
if [ -d "$HOME/.cursor/skills-cursor" ]; then
  CURSOR_SKILLS_DIR="$HOME/.cursor/skills-cursor"
elif [ -d "$HOME/.cursor" ]; then
  CURSOR_SKILLS_DIR="$HOME/.cursor/skills"
fi

if [ -n "$CURSOR_SKILLS_DIR" ]; then
  link_skill "$CURSOR_SKILLS_DIR" "Cursor"
else
  echo "==> Cursor not detected (no ~/.cursor), skipping Cursor skill link"
fi

if [ -d "$HOME/.gemini" ]; then
  echo "==> Gemini detected — linking into ~/.gemini/skills as a best-effort guess."
  echo "    (Gemini CLI's skill-discovery convention isn't confirmed by this script —"
  echo "    verify it's actually picked up; if not, this symlink is harmless to remove.)"
  link_skill "$HOME/.gemini/skills" "Gemini (best-effort)"
else
  echo "==> Gemini not detected (no ~/.gemini), skipping"
fi

echo ""
echo "To wire up another agent tool, symlink its skills directory to:"
echo "  $AGENT_SKILLS_DIR/$SKILL_NAME"

if [ -n "$CURSOR_RULE_TARGET" ]; then
  if [ -d "$CURSOR_RULE_TARGET" ]; then
    mkdir -p "$CURSOR_RULE_TARGET/.cursor/rules"
    cp "$SCRIPT_DIR/cursor-rule/sensitive-data-guard.mdc" "$CURSOR_RULE_TARGET/.cursor/rules/sensitive-data-guard.mdc"
    echo "==> Installed Cursor project rule (this repo only)"
    echo "    -> $CURSOR_RULE_TARGET/.cursor/rules/sensitive-data-guard.mdc"
  else
    echo "==> --cursor-rule target not found, skipping: $CURSOR_RULE_TARGET" >&2
  fi
fi

if [ -n "$CURSOR_RULE_SWEEP_ROOT" ]; then
  echo "==> Scanning for git repos under $CURSOR_RULE_SWEEP_ROOT (this may take a moment)..."
  sweep_repos="$(find_git_repos "$CURSOR_RULE_SWEEP_ROOT")"
  sweep_count=0
  if [ -n "$sweep_repos" ]; then
    sweep_count="$(printf '%s\n' "$sweep_repos" | grep -c .)"
  fi
  echo "==> Found $sweep_count git repo(s):"
  printf '%s\n' "$sweep_repos" | sed 's/^/    /'

  proceed=0
  if [ "$sweep_count" -eq 0 ]; then
    proceed=0
  elif [ "$YES" -eq 1 ]; then
    proceed=1
  elif [ -r /dev/tty ]; then
    printf '%s' "Add the Cursor rule to all $sweep_count repo(s) above? [y/N] " > /dev/tty
    read -r sweep_confirm < /dev/tty || sweep_confirm=""
    case "$sweep_confirm" in [Yy]*) proceed=1 ;; esac
  else
    echo "==> No terminal to confirm on — re-run with --yes to apply without prompting."
  fi

  if [ "$proceed" -eq 1 ]; then
    while IFS= read -r repo; do
      [ -z "$repo" ] && continue
      mkdir -p "$repo/.cursor/rules"
      cp "$SCRIPT_DIR/cursor-rule/sensitive-data-guard.mdc" "$repo/.cursor/rules/sensitive-data-guard.mdc"
    done <<<"$sweep_repos"
    echo "==> Installed the Cursor rule in $sweep_count repo(s)"
  elif [ "$sweep_count" -gt 0 ]; then
    echo "==> Not applied — nothing written."
  fi
fi

echo ""
echo "==> Cursor rule: for TRUE global scope (every project), Cursor's 'User Rules'"
echo "    live in its own Settings UI — verified there's no safe file/CLI hook for this"
echo "    script to write to (checked settings.json, globalStorage state.vscdb, and the"
echo "    cursor CLI's flags). Open Cursor -> Settings -> Rules and paste in:"
echo "      $SCRIPT_DIR/cursor-rule/sensitive-data-guard.mdc"
echo "    For one repo instead: --cursor-rule <path>"
echo "    For every repo under a directory: --cursor-rule-sweep <root> [--yes]"

echo "==> Installing git pre-commit hook"
mkdir -p "$GIT_HOOKS_DIR"
cp "$SCRIPT_DIR/hooks/pre-commit" "$GIT_HOOKS_DIR/pre-commit"
chmod +x "$GIT_HOOKS_DIR/pre-commit"
echo "    -> $GIT_HOOKS_DIR/pre-commit"

CUSTOMER_LIST_FILE="$HOME/.claude/sensitive-data-guard-customers.txt"
if [ ! -e "$CUSTOMER_LIST_FILE" ]; then
  echo "==> Creating customer denylist (empty — populate it yourself)"
  mkdir -p "$HOME/.claude"
  cat > "$CUSTOMER_LIST_FILE" <<'EOF'
# sensitive-data-guard customer denylist — one name per line, blank lines and
# #-comments ignored. Exact/case-insensitive substring match only (no semantic
# understanding) — the pre-commit hook redacts any staged line containing one
# of these names. Add every spelling/casing variant you actually use, e.g.:
#
# Acme Corp
# Acme Corporation
EOF
  echo "    -> $CUSTOMER_LIST_FILE (edit it to add your customer names)"
else
  echo "==> Customer denylist already exists, leaving it as-is"
  echo "    -> $CUSTOMER_LIST_FILE"
fi

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
