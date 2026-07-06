## Response language

Respond in **Japanese by default**, unless the user instructs otherwise.

Match the target repo's existing style for: code comments, commit messages, PR
title/description, issue title/body, code identifiers/variable names (English
repo → English, Japanese repo → Japanese).

Opt-out: to respond in English for one repo, add `Respond in English.` to that
repo's `./CLAUDE.md` (project memory overrides user memory). For all sessions,
export `SKIP_USER_MEMORY=1` in the CCoW Setup script before running install.sh.

---

# ippoan / ohishi-exp org baseline (common working rules)

These are the **default rules common to every ippoan / ohishi-exp repo**.
install.sh installs this file into `~/.claude/CLAUDE.md` every session, so they
apply no matter which repos are attached. A repo's `CLAUDE.md` (project memory)
overrides user memory, so put repo-specific exceptions there.

A repo's `CLAUDE.md` should carry **only** its identity, conditional pointers to
its `<repo>-map` skill / docs, and its own short invariants — do NOT restate
these common rules.

## Work lifecycle: issue → PR → push → fin ★strict

Do every task in this order; never skip a step.

1. **issue** — open (or identify) an issue before starting. Branch off it:
   `<issue-number>-<type>-<short-description>` (`type ∈ feat|fix|refactor|infra`).
   Do not start implementing on a bare `claude/...` branch with no issue. Write
   plans/designs as repo files (`docs/plan-<topic>.md`), reviewed via PR — not
   verbally in chat or the issue body.
2. **PR** — when implementation/plan is ready, open a PR. Link the issue with
   `Refs #N` (never `Closes/Fixes/Resolves`, see below). Whether you may open it:
   see "Confirm before opening a PR".
3. **push** — commit and push the branch. In the same turn as opening the PR,
   call `mcp__github__subscribe_pr_activity` to watch CI. Do not `sleep`/poll.
4. **fin** — CI green → (auto-)merge to `main`. Do not auto-close the issue; it
   is closed manually at release time via ci-dashboard.

## Don't assume — read plan/issue/source first, confirm contradictions ★strict

Do not act on guesses. Before touching anything, actually open and read the
**plan/design doc, the target issue, and the relevant source**.

- Read in order: parent issue/plan → this issue's body + acceptance criteria →
  the actual source (handler/config/workflow/spec) → prior conclusions in the
  conversation. Do not assert before reading through.
- If you find a contradiction, ask the user (`AskUserQuestion`) — don't fill the
  gap with your own interpretation.
- Don't relitigate settled decisions; find and follow the prior conclusion.
- Describe how a mechanism/term actually works from primary sources, not from
  paraphrase.
- Any production-affecting / destructive / irreversible action: if even one
  premise is unverified, confirm with the user before running it.

## lib-first — search for an existing impl before rewriting ★strict

Before writing any util/helper/cross-cutting logic (JWT verify, timing-safe
compare, base64url, fetch wrapper, CORS, coverage script, …), check for an
existing impl in the org (audit: ippoan/claude-md#76).

- Check: (1) the `ippoan-lib-catalog` skill (capability → canonical lib),
  (2) cross-repo search `grep -rn "<term>" /home/user/*/src` or ad-hoc ctags.
- If a lib has it, consume it (`@ippoan/mcp-cf-workers`, `@ippoan/auth-client`,
  `@ippoan/egov-shinsei-sdk`, ci-workflows reusables, rust-alc-api `alc-*`
  crates, …). If it's missing something, add it to the lib and publish — don't
  fork locally.
- Rule of two: the moment the same logic is needed in a 2nd repo, propose
  extracting a lib to the user. Never make a 3rd copy.
- If you must copy, declare `SOURCE-MIRROR: <repo>:<path>` within the first 5
  lines of the file. Never write a "keep this in sync by hand" comment — that's
  the signal to extract a lib.

## Branches / worktree

- Work on a short-lived branch off `main` (`<issue-number>-<type>-<short-desc>`;
  if you started on `claude/<topic>-<sha>`, open an issue and rename).
- Use `git worktree` to isolate parallel work on a different crate/package.
- **Never push to `main` directly.** Open a PR; CI-green → auto-merge workflow merges.
- `git push --force` / `git commit --amend` / `git rebase -i` are blocked by
  claude-hooks `git-safe-push.sh`.

## GitHub automation

- **Never call `mcp__github__enable_pr_auto_merge` unless the user explicitly
  asks.** Don't reflex-enable. On repos with incomplete required status checks,
  GitHub judges it "satisfied now" and merges **before CI finishes** (real harm:
  ippoan/secrets-inventory-gcp#21, ippoan/ci-dashboard#89). Repos with an
  `auto-merge.yml` enable it themselves after CI green. Instead: after opening a
  PR, `subscribe_pr_activity`, wait for green, let the user decide.
- **Commit/PR keywords**: ❌ `Closes/Fixes/Resolves #N` (auto-close breaks the
  release-time close check) → ✅ `Refs #N` / `Related to #N` / `Part of #N`.
- **Confirm before opening a PR**: once you've committed + pushed, do NOT open a
  PR on your own — ask the user first. Exception: the user explicitly said
  "open the PR too" / "PR it when done" in the same conversation.
- **After opening a PR**: in the same turn call `subscribe_pr_activity`, then end
  the turn (webhooks wake you; no `sleep`/`gh run watch`/polling).
- **Release**: tags are cut via `workflow_dispatch` (`tag-release.yml`). Local
  `git tag v*` is blocked by claude-hooks `tag-release-userprompt-guard.sh`.

## Secrets ★strict

- **Never put a secret value (API key / token / private key) into LLM context,
  plain env, or a tool-call param.** Use the `secret-inject` skill; the value
  flows only shell→curl(--data-binary)→worker→Secret Manager. Passing a value to
  the `create_secret`/`rotate_secret` MCP tool is also forbidden (it lands in chat).
- **Never `echo` a secret into GCP/CF.** `echo "$v" | gcloud secrets versions
  add …` appends a trailing `\n` that silently breaks downstream string compares
  (real harm: ippoan/auth-worker#208). Use `printf '%s' "$v" | … --data-file=-`.
- Never commit secrets/keys (`.env`, `*.pem`, `*.key`); never `git add -f` them.
- Cloud Run: pass secrets via **secretKeyRef** (Secret Manager), not plain env `value:`.

## Never do

- Never push to `main` directly / never force-push / amend / rebase -i (hooks block).
- Never run `gh pr merge` locally — leave it to auto-merge.
- Never hardcode values in render.sh / workflows (Secret Manager + secretKeyRef).
- Never add branches for an unverified platform before the MVP target is green.
- Never change a wire-protocol constant (`PROTOCOL_VERSION` etc.) breaking
  backward compat without bumping it.
- Never disable/skip a test just to make CI green — fix the root cause.
