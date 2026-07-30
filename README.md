# sensitive-data-guard

Helps stop customer-specific sensitive information (secrets, internal infra details,
PII) from ending up in git commits, docs, or AI chat tools (Claude Code, Cursor).

## What it installs

1. **A Claude Code / Cursor skill** (`sensitive-data-guard`) — on-demand and
   automatically-triggered semantic review of diffs, docs, and pasted text for things
   a regex can't reliably catch (a customer's company name in prose, for example).
2. **A machine-wide git `pre-commit` hook** — mechanically detects, in staged changes:
   - private key material
   - AWS access keys
   - JWT-shaped tokens
   - generic credential assignments (`api_key = "..."`, `password: ...`, etc.)
   - JFrog-style API keys / access tokens
   - public (non-RFC1918) IPv4 addresses
   - email addresses outside an allowlist (`@jfrog.com`, `example.com`, `test.com`)

   ...and **redacts each match in place** with a generic placeholder, re-stages the
   file, and blocks that commit attempt so you can review the redaction before
   committing again.

Nothing here calls home or uploads anything — it's a local git hook plus a skill file
that runs inside your own Claude Code / Cursor session.

## Install

```
git clone <this-repo-url>
cd sensitive-data-guard
./install.sh
```

Re-run `./install.sh` any time to pick up updates (e.g. after a `git pull`).

## Uninstall

```
./uninstall.sh
```

## How the hook behaves

- Applies to **every repo** on your machine, via `git config --global core.hooksPath`.
- Chains to any repo-local `.git/hooks/pre-commit` first, so it won't break tools like
  the Python `pre-commit` framework that install their own hook file directly.
- On a match, it prints the category + a masked preview (first few characters + `***`)
  — never the raw secret value — then **redacts the match in place** in the working
  tree file, re-stages it (`git add`), and blocks the commit so you can review the
  redaction (`git diff --cached`) before committing again. The retry passes cleanly:
  placeholders are chosen so they don't match the detection patterns anymore.
- Placeholders: private keys → `<REDACTED_PRIVATE_KEY_MATERIAL>`, AWS keys →
  `<REDACTED_AWS_ACCESS_KEY>`, JWTs → `<REDACTED_JWT>`, JFrog keys/tokens →
  `<REDACTED_JFROG_API_KEY>` / `<REDACTED_JFROG_ACCESS_TOKEN>`, generic credential
  values → `REDACTED` (key name kept), public IPs → `203.0.113.10` (RFC 5737
  documentation range), emails → `user@example.com`.
- Caveat: redaction rewrites the whole current working-tree copy of a flagged file.
  If you'd only staged part of it (`git add -p`), the rest of your unstaged edits to
  that file get staged too — check `git status` before your next commit.
- Intentional bypass for false positives: `git commit --no-verify`.

## If you already have a global git hooks setup

`install.sh` won't silently override an existing `core.hooksPath` — it'll tell you
what it found and leave your config alone. Options at that point:

- merge `hooks/pre-commit` from this repo into your existing hooks setup, or
- re-run `./install.sh --force` to point `core.hooksPath` here instead (this hook
  still chains to any repo-local `.git/hooks/pre-commit`, just not to hooks living at
  your previous global `core.hooksPath`)

## Customizing

- **Allowlisted email domains** — edit the `case` blocks in `hooks/pre-commit` (there
  are two: one in the scan step, one in the `need_email` redaction's `m{...}` pattern).
- **More secret patterns** — add a `need_<x>` flag, a detection line in `scan_line()`
  (`grep -Eq '<regex>' <<<"$content" && { report "<label>" "$content"; need_<x>=1; }`),
  and a matching redaction line in `redact_file()`. Pick a placeholder that doesn't
  match your own detection regex, so redacted files don't get re-flagged forever.
- **Hook install location** — `GIT_HOOKS_DIR=/some/path ./install.sh`

## Team distribution

Point teammates at this repo and have them run `./install.sh`. Everything it touches
(`~/.claude/skills/sensitive-data-guard`, `~/.cursor/.../sensitive-data-guard`,
`~/.git-hooks/pre-commit`, and the `core.hooksPath` git config) is local to their own
machine.
