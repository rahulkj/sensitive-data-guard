---
name: sensitive-data-guard
description: Scan files, git diffs, repos, folders, or pasted text for customer-specific sensitive information (internal infra details, secrets/credentials, PII, customer names) before it's committed, pushed, pasted into chat, written into a doc, or exported into a new repo. Use when the user wants to check, scan, sanitize, or anonymize something for sensitive/customer data — before a git commit/push/PR in any repo, before sharing a doc or transcript externally, before exporting/publishing a repo or folder, or asks things like "is this safe to commit/share", "does this contain secrets", "check for customer info", "scan this repo and anonymize it".
---

# Sensitive Data Guard

Catch customer-specific sensitive information before it leaves this machine — into a
git commit, a doc, or a chat with an AI tool (Claude, Cursor, or otherwise).

## What counts as sensitive here

1. **Infra details** — internal/customer hostnames, public-facing IPs tied to a
   customer environment, kube cluster/context names, tenant subdomains, internal/VPN URLs.
2. **Secrets & credentials** — API tokens, JFrog access tokens/API keys, license keys,
   passwords, private key material, cloud provider keys, JWTs, `.env` values.
3. **PII** — customer employee names, emails, or phone numbers appearing in logs,
   support tickets, screenshots, or configs.

Not reliably catchable by regex: a customer's company name in prose. There's no fixed
pattern for that — when scanning, actually read file/doc content for it, don't just
grep. That's the part a plain hook can't do and this skill exists to cover.

## When to run this

- Before `git commit` / `git push` / opening a PR, in **any** repo, not just the current one.
- Before saving or sharing a doc, a pasted log/config, or a chat transcript.
- Before exporting or publishing a repo or folder — e.g. copying a working repo out to a
  new GitHub repo, zipping a project up, or writing findings into a doc/deck/PDF of any
  format — anything about to leave this machine as a deliverable.
- Whenever asked to check, scan, sanitize, or **anonymize** something, or "is this safe
  to share/commit", "scan this repo/folder [and anonymize it]".

Two modes, depending on what's asked:

1. **Check mode** (default: "is this safe to commit/share", "does this contain
   secrets") — scope is the staged diff / pointed-at file(s). Report findings; redact
   the mechanical categories automatically; confirm with the user before touching a
   semantic hit (see "Redacting" below).
2. **Repo/folder anonymize mode** — the user names a repo or folder and asks you to
   scan it (for anonymizing, exporting, or publishing). Scope is **every relevant file
   in that tree**, not just a diff. Anonymize everything you find — mechanical *and*
   semantic categories — directly with Edit, without pausing per-instance for
   confirmation; the ask to scan-and-anonymize the tree *is* the confirmation. Report a
   summary afterward (see "Repo/folder anonymize mode" below).

## How to scan

Scope, in order of preference: staged changes (`git diff --cached`) if there's a git
repo with staged content; otherwise `git diff` against the base branch; otherwise the
specific file(s) or pasted text pointed at.

Grep the scope for each category below. **Never print a matched secret value verbatim
in your response** — report `file:line`, the category, and a masked preview (first 3-4
chars + `***`) only. Echoing the full value into a chat transcript is itself a leak.

Secrets & credentials:
- Private key material: `-----BEGIN[ A-Z]*PRIVATE KEY-----`
- AWS access key: `AKIA[0-9A-Z]{16}`
- JWT-shaped token: `eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}`
- Generic credential assignment: `(?i)(api[_-]?key|secret|token|passwd|password|access[_-]?key)\s*[:=]\s*['"]?[A-Za-z0-9/+_.-]{12,}`
- JFrog-style keys: `AKCp[a-zA-Z0-9]{10,}` (encrypted password/API key), `cmVmdGtu[A-Za-z0-9]{10,}` (access-token base64 prefix)

Infra:
- Any IPv4 address, public or private — flag everything except loopback (`127.*`) and
  `0.0.0.0`, which are never customer-identifying. Public and private get different
  placeholders (see table below); both count as a hit.
- Hostnames/subdomains that look like a real (non-example/non-placeholder) customer
  tenant, e.g. under `*.jfrog.io`, or internal `*.svc.cluster.local` values tied to a
  specific customer's namespace/cluster name.

PII:
- Email addresses not on an allowlist domain (not `@jfrog.com`, not
  `example.com`/`test.com`/`localhost`).
- Phone-number-shaped strings.
- Personal names appearing near words like "customer", "contact", "attendee",
  "reported by" — judgment call, not a regex.

## Redacting — do this in place, don't just report

For the mechanical categories (secrets, key material, public IPs, non-allowlisted
emails), redact confirmed matches immediately using Edit, with the same placeholders
the companion git hook uses — so a file looks identical whichever tool touched it
first, and so a follow-up scan comes back clean instead of re-flagging its own output:

| Category | Placeholder |
|---|---|
| Private key block | `<REDACTED_PRIVATE_KEY_MATERIAL>` (replaces the whole `-----BEGIN...-----END-----` block) |
| AWS access key | `<REDACTED_AWS_ACCESS_KEY>` |
| JWT | `<REDACTED_JWT>` |
| Generic credential value (`api_key = "..."`, etc.) | keep the key name, replace only the value with `REDACTED` |
| JFrog API key (`AKCp...`) | `<REDACTED_JFROG_API_KEY>` |
| JFrog access token (`cmVmdGtu...`) | `<REDACTED_JFROG_ACCESS_TOKEN>` |
| Public IPv4 | `203.0.113.10` (RFC 5737 TEST-NET-3 documentation range — already excluded from re-detection, same as `198.51.100.*` and `192.0.2.*`) |
| Private IPv4 (`10.*`, `172.16-31.*`, `192.168.*`) | `10.0.0.1` (loopback `127.*`/`0.0.0.0` stay as-is — never customer-identifying) |
| Email (non-allowlisted) | `user@example.com` |
| Customer/company name (from `~/.claude/sensitive-data-guard-customers.txt`, if matched exactly) | `<REDACTED_CUSTOMER_NAME>` |

For semantic hits with no fixed placeholder — a customer/company name in prose not on
the denylist file above, a customer-tied hostname/tenant/cluster name, a personal
name — behavior depends on mode:

- **Check mode**: there's no single obviously-correct placeholder, so pick something
  generic and consistent within the file (e.g. "Acme Corp", "customer-a", "Customer
  Contact") and confirm the specific replacement text with the user before editing,
  since the wrong generic name can be as confusing as the real one.
- **Repo/folder anonymize mode**: don't stop to confirm — assign a consistent
  placeholder per distinct real-world entity the moment you first see it (see below)
  and keep editing. The user already authorized this by asking for the scan.

Skip redaction (report only) when a hit is a clear false positive — an already-example
value, a test fixture, a doc placeholder token — and say why you're leaving it alone.

If a real secret is already committed or pushed: flag that fixing the current diff
isn't enough — the credential also needs rotating, and (carefully, separately) history
needs scrubbing.

## Repo/folder anonymize mode

Triggered by an explicit ask to scan-and-anonymize a repo or folder (exporting it,
publishing it, handing it off) — not the default check-before-commit flow.

1. **Scope**: every text file under the given path. Skip `.git/`, binaries, and
   dependency/build directories (`node_modules`, `vendor`, `dist`, `build`, `.venv`,
   lock files) — same spirit as the git hook's exclusions. Use `git ls-files` if it's a
   repo (respects `.gitignore` for you); otherwise walk the directory.
2. **Discover likely customer names from context** — there's no Salesforce/CRM feed
   wired up here, so infer candidates the way you'd read the repo as a human would,
   before/alongside grepping for them:
   - `git remote -v` (org/repo name often *is* the customer)
   - repo/folder directory name itself
   - README, docs, and top-level comments — titles, "for `<customer>`"-style phrasing
   - package metadata (`package.json`, `pyproject.toml`, `Cargo.toml`, `Chart.yaml`)
     name/description/author fields
   - Terraform/K8s variable defaults, `.tfvars`, Helm `values.yaml` — a hardcoded
     namespace, tenant, or cluster name is often the customer's name in disguise
   - `~/.claude/sensitive-data-guard-customers.txt` (the git hook's static denylist) —
     always check these first regardless of what you find in context
   Treat anything from this pass as a *candidate*, not a confirmed hit — corroborate
   against how it's actually used in the files before treating it as sensitive (a repo
   literally named after a public open-source project isn't a customer).
3. **Detect** every category from "What counts as sensitive here" above across the
   whole scope, using both the discovered candidates and the denylist — mechanical
   (regex) *and* semantic (actually read prose, docs, comments for company/personal
   names and customer-tied infra names — this is exactly the part the git hook can't do).
4. **Maintain one name→placeholder mapping for the whole run**, not per-file, so the
   same customer is anonymized identically everywhere: first distinct company name seen
   → "Customer A", second → "Customer B", etc. (or reuse an existing generic label if
   the file already has an obvious convention). Same idea for personal names →
   "Contact 1", "Contact 2", etc. Reuse the fixed placeholders from the table above for
   the mechanical categories.
5. **Edit in place** as you go — don't batch everything into one pass at the end, and
   don't stop for per-instance confirmation. Skip only clear false positives (test
   fixtures, doc placeholders) and note why.
6. **Report a summary when done**: file count touched, a category breakdown, and the
   name→placeholder mapping used (so the user can sanity-check "Customer A" was really
   the company they think it was). Never print an unredacted matched value in that
   summary — masked preview only, same rule as check mode.
7. **Propose denylist additions** — for any confirmed customer name from this run that
   *isn't* already in `~/.claude/sensitive-data-guard-customers.txt`, list them together
   and ask once (not per-name) whether to add them. If yes, append them (one name per
   line, keep the file's comment header) so the machine-wide git hook catches that name
   automatically in every future repo, not just this scan. This is how the list actually
   gets "seeded" over time — through real scans, since there's no CRM feed doing it
   automatically — so don't skip this step.

## Companion enforcement

A machine-wide git `pre-commit` hook, installed by this skill's companion
`sensitive-data-guard` repo's `install.sh` (wired via `git config --global
core.hooksPath`), runs the mechanical half of this automatically on every commit in
every repo on this machine: it flags/redacts secrets, key material, public *and*
private IPs, non-allowlisted emails, and exact denylisted customer names (from
`~/.claude/sensitive-data-guard-customers.txt`) in the staged diff, using the same
placeholder table above, then either blocks the commit for you to fix manually or
redacts-and-re-blocks-for-review, depending on which you pick when it asks. It chains
to any repo-local `.git/hooks/pre-commit` first, so it won't break tools like the
Python `pre-commit` framework that install their own hook file directly.

This skill covers what the hook can't: semantic redaction of prose, docs, pasted
logs/transcripts, and anything you want checked before it's even staged — plus the
whole-repo/folder anonymize mode above, which the hook (staged-diff only) can't do.
