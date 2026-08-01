# sensitive-data-guard

Helps stop customer-specific sensitive information (secrets, internal infra details,
customer names, PII) from ending up in git commits, docs, exported repos, or AI chat
tools (Claude Code, Cursor, and anything else pointed at `~/.agent/skills`).

## What it installs

1. **An agent skill** (`sensitive-data-guard`) — on-demand and automatically-triggered
   semantic review of diffs, docs, and pasted text for things a regex can't reliably
   catch (a customer's company name in prose, for example). Also has an explicit
   **repo/folder anonymize mode**: ask it to scan-and-anonymize a whole repo or folder
   (before exporting/publishing it) and it edits every hit in place — mechanical and
   semantic — using a consistent name→placeholder mapping, then reports a summary.
   Installed once to a canonical `~/.agent/skills/sensitive-data-guard`, symlinked out
   to Claude Code, Cursor, and (best-effort) Gemini — see "How the skill is wired up".
2. **A machine-wide git `pre-commit` hook** — mechanically detects, in staged changes:
   - private key material
   - AWS access keys
   - JWT-shaped tokens
   - generic credential assignments (`api_key = "..."`, `password: ...`, suffixed names
     like `DB_PASSWORD_1=...`, hardcoded ternary fallbacks like `x ? x : "literal"`),
     while leaving HCL/Terraform code references alone (`data.x.y`, `var.x`, etc.)
   - JFrog-style API keys / access tokens
   - public **and** private IPv4 addresses (loopback/`0.0.0.0` excluded)
   - email addresses outside an allowlist (`@jfrog.com`, `example.com`, `test.com`)
   - customer/company names on your local denylist (`~/.claude/sensitive-data-guard-customers.txt`)

   On a match it lists everything found (with the key/field name, where detectable),
   then asks: fix it yourself, or let the hook redact in place? Either way the current
   commit is blocked so you can review before committing again. Files are scanned in
   parallel with a live progress bar; redaction/`git add` stays sequential.
3. **A Cursor rule** (`cursor-rule/sensitive-data-guard.mdc`) — a compact pointer to the
   same behavior, so Cursor keeps it in context automatically instead of relying on the
   skill being explicitly invoked. See "Cursor rule" below for global vs. per-project.

Nothing here calls home or uploads anything — it's a local git hook plus a skill file
that runs inside your own agent session.

## Install

```
git clone <this-repo-url>
cd sensitive-data-guard
./install.sh
```

Re-run `./install.sh` any time to pick up updates (e.g. after a `git pull`) — it's
idempotent and won't touch your customer denylist if it already exists.

## Uninstall

```
./uninstall.sh
```

## How the skill is wired up

`install.sh` copies `skill/` once to a canonical `~/.agent/skills/sensitive-data-guard`,
then symlinks that into each tool it finds:

- `~/.claude/skills/sensitive-data-guard` (always)
- `~/.cursor/skills-cursor/sensitive-data-guard` or `~/.cursor/skills/...` (if `~/.cursor` exists)
- `~/.gemini/skills/sensitive-data-guard` (if `~/.gemini` exists — best-effort; Gemini
  CLI's actual skill-discovery convention isn't confirmed by this script, verify it's
  picked up)

To wire up another tool, symlink its skills directory to
`~/.agent/skills/sensitive-data-guard` yourself.

## Cursor rule

`cursor-rule/sensitive-data-guard.mdc` is a short rule you can wire in two ways:

- **Global (recommended, but manual)**: Cursor's true global "User Rules" live in its
  own Settings UI, not a plain file this script can safely edit. Open Cursor → Settings
  → Rules and paste in the contents of `cursor-rule/sensitive-data-guard.mdc`.
- **Per-project (automatable)**: `./install.sh --cursor-rule <path-to-repo>` copies it
  into `<path-to-repo>/.cursor/rules/sensitive-data-guard.mdc`.

## Customer denylist

The hook and skill both check `~/.claude/sensitive-data-guard-customers.txt` (created
empty by `install.sh` on first run, never overwritten after that) — one customer/company
name per line, blank lines and `#`-comments ignored. Matching is exact/case-insensitive
substring only, no semantic understanding — it won't catch a name that isn't on the
list. There's no CRM/Salesforce feed wired up to seed it automatically; instead, the
skill's repo/folder anonymize mode discovers likely customer names from context (git
remote, README, config, docs) during real scans and proposes adding confirmed ones to
this file — so the list grows from actual usage over time. You can also just edit the
file directly.

## How the hook behaves

- Applies to **every repo** on your machine, via `git config --global core.hooksPath`.
- Chains to any repo-local `.git/hooks/pre-commit` first, so it won't break tools like
  the Python `pre-commit` framework that install their own hook file directly.
- Scans changed files in parallel (one process per file, capped at your CPU count or 8,
  whichever is smaller) with a live progress bar; single/few-file commits automatically
  skip the parallel path since there's nothing to gain there. Redaction/`git add` always
  runs sequentially — concurrent `git add` calls race on `.git/index.lock`.
- On a match, it prints the category + a masked preview (first few characters + `***`,
  plus the field/key name when it can extract one) — never the raw secret value — then
  asks interactively: fix it yourself (commit blocks immediately, nothing touched), or
  let the hook redact in place (rewrites the file, re-stages it, blocks the commit so
  you can review before committing again)? No TTY available (CI, some GUI clients)
  defaults safely to "fix it yourself".
- Placeholders: private keys → `<REDACTED_PRIVATE_KEY_MATERIAL>`, AWS keys →
  `<REDACTED_AWS_ACCESS_KEY>`, JWTs → `<REDACTED_JWT>`, JFrog keys/tokens →
  `<REDACTED_JFROG_API_KEY>` / `<REDACTED_JFROG_ACCESS_TOKEN>`, generic credential
  values → `REDACTED` (key name kept), public IPs → `203.0.113.10` (RFC 5737
  documentation range), private IPs → `10.0.0.1`, emails → `user@example.com`,
  denylisted customer names → `<REDACTED_CUSTOMER_NAME>`.
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
- **Customer names** — edit `~/.claude/sensitive-data-guard-customers.txt` directly, or
  let the skill propose additions after a repo/folder anonymize scan.
- **Hook install location** — `GIT_HOOKS_DIR=/some/path ./install.sh`

## Team distribution

Point teammates at this repo and have them run `./install.sh`. Everything it touches
(`~/.agent/skills/sensitive-data-guard` and its symlinks, `~/.git-hooks/pre-commit`,
`~/.claude/sensitive-data-guard-customers.txt`, and the `core.hooksPath` git config) is
local to their own machine — the customer denylist is per-machine and isn't synced or
shared by this repo.
