---
name: sensitive-data-guard
description: Scan files, git diffs, or pasted text for customer-specific sensitive information (internal infra details, secrets/credentials, PII) before it's committed, pushed, pasted into chat, or written into a doc. Use when the user wants to check, scan, or sanitize something for sensitive/customer data, before a git commit/push/PR in any repo, before sharing a doc or transcript externally, or asks things like "is this safe to commit/share", "does this contain secrets", "check for customer info".
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
- Whenever asked to check, scan, or sanitize something, or "is this safe to share/commit".

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
- Public (non-RFC1918) IPv4 addresses — flag anything that isn't `10.*`, `172.16-31.*`,
  `192.168.*`, `127.*`, `0.0.0.0`.
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
| Email (non-allowlisted) | `user@example.com` |

For the semantic categories (a real customer/company name in prose, a customer-tied
hostname/tenant/cluster name, a personal name), there's no single obviously-correct
placeholder — pick something generic and consistent within the file (e.g. "Acme Corp",
"customer-a", "Customer Contact") and confirm the specific replacement text with the
user before editing, since the wrong generic name can be as confusing as the real one.

Skip redaction (report only) when a hit is a clear false positive — an already-example
value, a test fixture, a doc placeholder token — and say why you're leaving it alone.

If a real secret is already committed or pushed: flag that fixing the current diff
isn't enough — the credential also needs rotating, and (carefully, separately) history
needs scrubbing.

## Companion enforcement

A machine-wide git `pre-commit` hook, installed by this skill's companion
`sensitive-data-guard` repo's `install.sh` (wired via `git config --global
core.hooksPath`), runs the mechanical half of this automatically on every commit in
every repo on this machine: it redacts secrets, key material, public IPs, and
non-allowlisted emails in the staged diff using the same placeholder table above,
re-stages the redacted files, and blocks that commit attempt so the redaction can be
reviewed — the next `git commit` then goes through clean. It chains to any repo-local
`.git/hooks/pre-commit` first, so it won't break tools like the Python `pre-commit`
framework that install their own hook file directly.

This skill covers what the hook can't: semantic redaction of prose, docs, pasted
logs/transcripts, and anything you want checked before it's even staged.
