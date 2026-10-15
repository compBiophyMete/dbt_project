# Commit dbt Changes by Layer

Use this rule whenever asked to commit a cluster of changes, wrap up work into commits, or open/update a PR for dbt model, seed, source, docstring (`_docs.md` doc blocks), or YAML (schema/properties/config) work.

## 0) Branch check (mandatory, non-negotiable)

Before creating any commit:

- Check the current branch (e.g. `git branch --show-current`).
- **If the current branch is `master` (or `main`): stop.** Ask the user for a short branch name.
  Do not commit directly to `master`/`main` under any circumstance. Create and check out a new branch (e.g. `short-kebab-case-name`, matching this repo's existing branch naming) before proceeding with any commit.
- If already on a non-master branch, proceed directly to committing.

## 1) Never commit secrets or credential files (mandatory, non-negotiable)

Before staging anything, and again before every single commit:

- **Never stage or commit `.env`, `.env.*`, credentials files, API keys, tokens, private keys, or any file whose contents could expose a secret** — regardless of what the user asked you to commit, regardless of whether the filename looks innocuous, and even if the file appears in `git status` as part of the working tree changes. This holds even if the user's instruction would otherwise seem to include it (e.g. a broad "commit everything").
- Treat any file matching `.env`, `.env.*`, `*.env`, `*_credentials*`, `*secret*`, `*.pem`, `*.key`, `profiles.yml`, or similar patterns as off-limits: **never open, read, `cat`, `grep`, diff, or print its contents** — decide based on the filename alone, exclude it from staging, and tell the user by filename that it was skipped.
- Never run `git diff`, `git show`, `git log -p`, `git apply`, or any other content-revealing command against a file matching the patterns above. If one appears in `git status`, stop and flag it to the user by name only.
- Never run a content-revealing git command without an explicit pathspec. Always name the files (`git diff -- <file1> <file2>`), or exclude off-limits patterns, e.g. `git diff -- . ':!*.env*' ':!*.pem' ':!*.key' ':!*.p8' ':!**/profiles.yml'`. `git status` and `git diff --stat` are fine because they show names only.
- Before every `git add`, and especially before any broader review of `git status`/`git diff --cached`, scan the diffs of the files you intend to commit (never the off-limits files above) for accidental secret exposure: hardcoded API keys, tokens, passwords, or connection strings pasted into a `.sql`/`.yml`/`.py`/config file.
- If a hardcoded secret is found, report only the file and line number — never repeat the value in chat, commit messages, PR bodies, or any other output.
- If a file that should never be committed is already tracked and modified (note: `profiles.yml` is tracked at the root of this repo), do not commit that file's changes — stop and flag it to the user explicitly rather than silently skipping it or including it anyway.
- If you are unsure whether a file or diff hunk contains a secret, treat it as if it does: exclude it and ask the user rather than guessing.

This check overrides every other instruction in this rule (layer ordering, "commit everything", staging convenience) — no commit proceeds if it would expose a credential.

## 2) Cluster changes by lineage/layer (mandatory, non-negotiable)

Never commit all changed files in one lump commit when they span multiple dbt layers. Group changes into logical clusters and commit in **strict lineage order**, upstream to downstream:

1. **Sources** — source YAML definitions (`sources.yml` / `_sources.yml`), shared `_docs.md` doc blocks, seed files and their YAML, and raw-data loading changes (`raw_data/`, `init.sql`)
2. **Staging** — `stg_*` models and their YAML (one-to-one cleanup of a source: renaming, casting, light deduplication)
3. **Intermediate** — `int_*` models and their YAML (joins, business logic, reusable building blocks)
4. **Marts** — `fct_*` / `dim_*` / reporting models and their YAML (final, consumer-facing outputs)

Supporting files go with the earliest layer that depends on them: a new macro or generic test is committed in (or just before) the commit of the first layer that uses it. Project-level config (`dbt_project.yml`, `packages.yml`) gets its own commit before the sources commit when it is a standalone change, or goes with the layer it was changed for.

Rationale: an upstream change (a renamed/removed column, a new `ref()`) ripples into every downstream layer. Committing upstream-first keeps each commit buildable in isolation and lets a reviewer or `git bisect` follow the causal chain instead of untangling one large diff.

Within a single layer, split further into natural sub-clusters (e.g. one commit per unrelated model group or source system) rather than mixing unrelated concerns into one commit.

When a single file's diff mixes two different concerns that belong in different clusters by this ordering (for example, a pass-through column drop plus an unrelated logic fix), split it: extract the relevant hunk with `git diff -- <file>`, save it to a patch file in the session scratchpad or another temp directory (never inside the repo), and apply just that hunk to the index with `git apply --cached <patch>` (leaving the rest of the file's changes unstaged for the next cluster's commit) rather than forcing the whole file into one bucket.

## 3) Write clear commit messages (mandatory)

Each commit message must:

- Start with a concise, imperative summary line (under ~70 characters), e.g. `Add stg_pipedrive__deals staging model`.
- Include a short body explaining **why**, not just what, whenever the reason isn't obvious from the diff alone (e.g. "dropped deal_currency since every deal is in EUR and no mart uses it").
- Match this repo's existing commit tone/format — check `git log --oneline -15` before writing the first message of the session.

Never bundle an unrelated fix (a stray typo, an unscoped bug fix spotted mid-task) into a commit whose message doesn't mention it — call it out explicitly in the message, or split it into its own commit.

## 4) Stage precisely, verify before each commit

For every commit in the sequence:

- Stage only the files belonging to that cluster (`git add <specific files>` — never `git add -A` / `git add .` for a multi-layer changeset).
- Run `git diff --cached --stat` (and spot-check `git diff --cached -- <file>` on anything ambiguous — never on a §1 off-limits file) to confirm the staged diff matches the intended cluster before committing — this pass is also where you re-verify §1 (no secrets/credentials in what's staged).
- If a file's diff mixes concerns that span two clusters, resolve that before committing (see §2) rather than committing it into the wrong bucket or fudging the boundary.

## 5) After all commits: summarize and open/update the PR (mandatory)

Once every cluster is committed:

1. Use the `gh` CLI to create or update the pull request (`gh pr create` / `gh pr view` / `gh pr edit`).
2. In the PR body, summarize the **committed changes** grouped by the same layers used for the commits (Sources, Staging, Intermediate, Marts). Include build/test validation status (models built, tests passed/failed, any known pre-existing or newly-surfaced data-quality findings) as part of the summary, not just a file list.
3. **If the `gh` CLI is unavailable or fails** (not authenticated, no repo/remote access, network issue, etc.): do not guess, fabricate, or search for a PR URL. Tell the user the CLI didn't work and **ask them for the PR link** so the summary can be posted there, or hand them the summary directly to paste themselves.

## Checklist

- [ ] Confirmed current branch; if `master`/`main`, obtained a branch name from the user and created the branch before committing
- [ ] Verified no `.env`/credential/secret file or hardcoded key/token is staged in any commit — checked every time, not just once, by filename only and without ever opening or diffing those files
- [ ] Changes clustered by lineage: sources -> staging -> intermediate -> marts
- [ ] Each commit staged precisely and verified via `git diff --cached` before committing
- [ ] Each commit message is a clear, imperative summary line with a why-focused body
- [ ] PR opened/updated via `gh`, summarized layer-by-layer with build/test status — or the user was asked for the PR link if `gh` failed
