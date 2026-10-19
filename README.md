## Setup

1. Download Docker Desktop (if you don’t have installed) using the official website, install and launch.
2. Fork this Github project to you Github account. Clone the forked repo to your device.
3. Open your Command Prompt or Terminal and navigate to the project folder.
4. Create your local `.env` and export it in that terminal, as described in [Credentials](#credentials) below. Do this **before** starting Docker: the database is created with the user, password, database name, and port from your `.env`.
5. In the same terminal, run `docker compose up`.
6. Connect to the db via a preferred tool (e.g. DataGrip, Dbeaver etc) using the credentials from your `.env`.
7. Install dbt-core and dbt-postgres using pip (if you don’t have) on your preferred environment.
8. Install the dbt packages with `dbt deps`, then build and test the project in two steps, from a terminal where the `.env` is exported:
   ```
   dbt run    # builds every model
   dbt test   # runs every test
   ```
   Use `dbt run` then `dbt test`, **not** `dbt build`: `dbt build` skips every downstream model when a test fails, and this project has tests that fail on purpose (see [Known data issues](#known-data-issues)). The results land in three schemas: `stg_pipedrive` (staging views), `int_pipedrive` (intermediate tables) and `pipedrive_analytics` (the public marts, including the report `rep_sales_funnel_monthly`).

## Credentials

> ⚠️ **Never write credentials directly in `profiles.yml`, and never push your `.env` file to the repository.**

`profiles.yml` is committed to git, so it contains no secrets — every connection value is read from an environment variable with `{{ env_var('...') }}`. `docker-compose.yml` reads the same variables, so the database Docker creates and the connection dbt uses always match:

| Variable | Used for |
|----------|----------|
| `DBT_TYPE` | Adapter type (e.g. `postgres`) |
| `DBT_HOST` | Database host |
| `DBT_PORT` | Database port |
| `DBT_USER` | Database user |
| `DBT_PASSWORD` | Database password |
| `DBT_DATABASE` | Database name |
| `DBT_SCHEMA` | Default target schema |
| `DBT_THREADS` | Number of threads dbt runs with |

To set them up:

1. Copy the template to a local `.env` file at the repo root:
   ```
   cp .dotenv/example_env.txt .env
   ```
2. Replace each `*****` in `.env` with your own value. Write `KEY=value` without spaces around `=`, so the shell can load it.
3. From the project folder, export the variables into your terminal session:
   ```
   set -a; source .env; set +a
   ```
   Do this in every new terminal before running `docker compose up` or any dbt command.
4. Start the database with `docker compose up`, then check the connection with `dbt debug`.

If you change the user, password, or database name after the database was first created, run `docker compose down` and then `docker compose up` again: Postgres only applies these values when it initializes a new database.

`.env` and `.env.*` are listed in `.gitignore`, so git will not pick them up. Before every commit, run `git status` and make sure no `.env` file (or any other file containing a password, key, or token) is staged.

## Project Overview

### Layers

| Layer | Schema | Materialization | Models |
|---|---|---|---|
| Sources | `public` | raw tables | 6 Pipedrive tables (`deal_changes`, `activity`, `activity_types`, `fields`, `stages`, `users`), declared with schema, key and value contract tests in [_pipedrive__sources.yml](models/staging/pipedrive/_pipedrive__sources.yml) |
| Staging | `stg_pipedrive` | views | one `stg_` model per source table: renamed, typed, cleaned; no business meaning |
| Intermediate | `int_pipedrive` | tables (event models incremental, see below) | business entities and rules: deal events (`int_deal_changes_filtered_to_creations`, `_stage_changes`, `_owner_changes`, `_losses`), `int_deals` (one row per deal), activities, and the funnel (`int_funnel_steps_mapped`, `int_deal_funnel_steps_unioned`) |
| Marts | `pipedrive_analytics` | tables, enforced contracts | 6 dimensions (`dim_deals`, `dim_stages`, `dim_users`, `dim_lost_reasons`, `dim_activity_types`, `dim_funnel_steps`), 5 facts (`fct_deal_stage_changes`, `fct_deal_losses`, `fct_deal_events`, `fct_activities`, `fct_deal_funnel_steps`) and 1 report |

Every model has its own YAML file with a description (purpose, grain, logic, edge cases, refresh) and tests; column descriptions are doc blocks in the `_docs.md` files. Browse them in the dbt docs (see [dbt Documentation and Observability](#dbt-documentation-and-observability)).

### Reports

| Report | Grain | Answers |
|---|---|---|
| [rep_sales_funnel_monthly](models/marts/rep_sales_funnel_monthly.sql) | month × funnel step | **the brief's report**: how many deals reached each funnel step per month; columns `month`, `kpi_name`, `funnel_step`, `deals_count` |

It is declared as an exposure in [_marts__exposures.yml](models/marts/_marts__exposures.yml).

### How the funnel is defined

The rules live in one place, [int_deal_funnel_steps_unioned](models/intermediate/funnel/int_deal_funnel_steps_unioned.sql); its YAML documents each decision with the data behind it.

- **Stage steps 1–9**: a deal reaches step N at its first entry into stage N **or any later stage** (a deal that skipped a stage still counts in it).
- **Call steps 2.1 Sales Call 1 and 3.1 Sales Call 2**: a deal reaches the step at its first **done** activity of that type (`meeting`, `sc_2`), dated by the activity's due date (the only activity date in this export).
- **Excluded**: 5 deal IDs that each hold two separate deals (an ID collision in the data); they stay in every other model, flagged `has_multiple_creations`.
- A month counts the deals that reached a step in that month; for conversion, use the cohort report.

### Known data issues

These tests **fail on purpose**: they flag real issues in the source data, and the project uses no thresholds, so a known issue fails like a new one. Each is explained in its model's description.

| Test | Failing rows | Issue |
|---|---|---|
| source `activity.deal_id` → `deal_changes` | 4,571 | activities and deals barely share deal IDs (only 8 of 4,579 activity rows link to a deal) |
| `stg_pipedrive__activities.deal_id` → `stg_pipedrive__deal_changes` | 4,571 | the same issue, in staging |
| source `activity.activity_id` unique | 11 | 11 activity IDs are reused on two deals |
| `int_deals`: `not has_multiple_creations` | 5 | 5 deal IDs each hold two deals |

Any other failing test is a new problem.

## Incremental Models

Some intermediate models load incrementally: after the first run, each run only processes recent rows instead of rebuilding the whole table.

| Model | Strategy | Lookback column | Window | Deduplication |
|---|---|---|---|---|
| `int_users` | `merge` on `user_id` | `modified_at` | 2 days, 8 on Mondays | `merge` updates existing users; a `post_hook` deletes users removed upstream |
| `int_deal_changes_filtered_to_creations` | `append` | `changed_at` | 2 days, 8 on Mondays | `not exists` on (`deal_id`, `changed_at`), backed by a unique index; a `post_hook` deletes creations removed upstream |
| `int_deal_changes_filtered_to_stages` | `append` | `changed_at` | 2 days, 8 on Mondays | `not exists` on (`deal_id`, `changed_at`), backed by a unique index; a `post_hook` deletes stage changes removed upstream |
| `int_deal_changes_filtered_to_owners` | `append` | `changed_at` | 2 days, 8 on Mondays | `not exists` on (`deal_id`, `changed_at`), backed by a unique index; a `post_hook` deletes owner changes removed upstream |
| `int_deal_changes_filtered_to_losses` | `append` | `changed_at` | 2 days, 8 on Mondays | `not exists` on (`deal_id`, `changed_at`), backed by a unique index; a `post_hook` deletes losses removed upstream |

**Why the delete hooks.** Deal events never change once recorded, but they can disappear from the source: a deal deleted in Pipedrive (first marked as deleted, then "after 30 days, the deal will be permanently deleted", [API reference](https://developers.pipedrive.com/docs/api/v1/Deals)), erased for GDPR, or merged into another deal (the merged deal "will be removed from your Pipedrive account", [Pipedrive tutorial](https://developers.pipedrive.com/tutorials/merging-deals-pipedrive-api)). Incremental loads only add or update rows, so without a hook these tables would keep reporting deals that no longer exist. Each hook runs after every load and deletes the rows whose key no longer exists upstream. It compares the whole table, so its cost grows with the table. A guard skips the delete when the source has no rows for the model's key at all (a failed or unfinished raw reload), so an empty source can't wipe a table.

### The lookback macro

Every lookback window is written with one macro, [`incremental_lookback_filter`](macros/incremental_lookback.sql) (documented in [macros/incremental_lookback.yml](macros/incremental_lookback.yml)). Use it in every new incremental model instead of writing the interval by hand:

```sql
{% if is_incremental() %}
    and {{ incremental_lookback_filter('changed_at', default_days=2, weekly_days=8) }}
{% endif %}
```

It renders:

```sql
changed_at >= (select coalesce(max(changed_at), '-infinity'::timestamp) from <this table>) - interval '2 days'
```

- **One column, two roles.** The column is filtered in the model's input and read back as `max(column)` from the model's own table (the watermark). Both sides compare the same clock, so **the model must keep that column in its output**.
- **Window size**, decided by `lookback_days()` in this order:
  1. the `lookback_days` var, if given (see backfills below);
  2. `weekly_days` when the run starts on `weekly_weekday` (default Monday), so a weekly run re-checks the whole past week;
  3. otherwise `default_days`.
- **Empty table.** `coalesce(..., '-infinity')` makes an existing but empty table load everything instead of nothing.

When you write a new incremental model:

- **Deduplicate.** A lookback re-reads rows that are already loaded. Use `merge` / `delete+insert` on a `unique_key`, or `append` with a `not exists` anti-join on the grain (as in `int_deal_changes_filtered_to_creations`). A plain `append` with a lookback inserts duplicates.
- **Filter on a raw column, in the import CTE** (e.g. `changed_at`, not a column computed in staging). The predicate is then pushed through the staging view to the source table.
- **Tag it** `daily` + `incremental` and document the window in the model's description (see [.claude/rules/dbt-documentation-testing.md](.claude/rules/dbt-documentation-testing.md)).

### Running and backfilling

```
.venv/bin/dbt run --select tag:incremental                                   # all incremental models, normal window
.venv/bin/dbt run --select int_deal_changes_filtered_to_creations --vars '{lookback_days: 30}'   # one-off backfill of one model, 30-day window
.venv/bin/dbt run --select int_deal_changes_filtered_to_creations --full-refresh                 # rebuild from scratch (needed after a column change)
```

- `--vars '{lookback_days: N}'` applies to **every** incremental model in the run. Use `--select` to backfill only one.
- "Monday" is the run's start time in **UTC** (dbt's `run_started_at`). If the scheduler skips a Monday, that week gets no 8-day re-check; backfill it with `lookback_days`.
- Rows that arrive later than the window are only picked up by a wider `lookback_days` or a `--full-refresh`.
- `on_schema_change: fail` is set on every incremental model. After adding or removing a column, run the model once with `--full-refresh`.

## dbt Documentation and Observability

Two self-contained HTML pages, one for reading the project and one for following up on failing tests:

| Page | File | What it shows |
|---|---|---|
| dbt documentation | [target/static_index.html](target/static_index.html) | Models, sources, column docs, tests, and lineage |
| Elementary observability | [edr_target/elementary_report.html](edr_target/elementary_report.html) | Test results with failing-row samples, run history, and lineage |

These pages are built from your own database, so they aren't committed and have no shared URL. Generate them locally (the links above work once the files exist), then open them in a browser. No server is needed.

**1. One-time setup** (skip any step you've already done):

```
.venv/bin/python -m pip install 'elementary-data[postgres]==0.20.1'   # Elementary CLI; same version as in packages.yml
.venv/bin/dbt deps                                                    # installs the Elementary dbt package
```

Then create `.edr/profiles.yml` (Elementary's connection profile; see below).

**2. Generate the pages** from a terminal at the repo root:

```
set -a; source .dotenv/.dev.env; set +a        # export your credentials

.venv/bin/dbt run                              # builds every model
.venv/bin/dbt test                             # runs every test; Elementary logs the results
.venv/bin/dbt docs generate --static           # writes target/static_index.html
.venv/bin/edr report --profiles-dir .edr       # writes edr_target/elementary_report.html
```

Run `dbt run` and `dbt test` separately, not `dbt build`: `dbt build` skips the models downstream of a failing test, and the [known data issues](#known-data-issues) fail on purpose. `dbt test` exits with an error because of them; that is expected, and the report shows each failure with its failing rows.

**3. Open them:**

```
open target/static_index.html
open edr_target/elementary_report.html
```

(`open` is macOS; on Linux use `xdg-open`, on Windows `start`.) Re-run step 2 whenever you want fresh results.

**Elementary profile.** `.edr/profiles.yml` is git-ignored, so create it on a fresh clone with this content (no secrets; it reads the same `DBT_*` variables):

```yaml
elementary:
  target: default
  outputs:
    default:
      type: "{{ env_var('DBT_TYPE') }}"
      host: "{{ env_var('DBT_HOST') }}"
      port: "{{ env_var('DBT_PORT') | as_number }}"
      user: "{{ env_var('DBT_USER') }}"
      password: "{{ env_var('DBT_PASSWORD') }}"
      dbname: "{{ env_var('DBT_DATABASE') }}"
      schema: "{{ env_var('DBT_SCHEMA') }}_elementary"
      threads: "{{ env_var('DBT_THREADS') | as_number }}"
```

## Claude Code Setup

### Global permissions (`~/.claude/settings.json`)

Open the user-level Claude Code settings with:

```
vi ~/.claude/settings.json
```

and make sure it contains the following permissions. They allow the dbt MCP `parse` tool, require confirmation before running Python/pip, and block reading or leaking `.env` secrets, dumping environment variables, and destructive delete commands.

```json
{
  "permissions": {
    "allow": [
      "mcp__dbt__parse"
    ],
    "ask": [
      "Bash(python)",
      "Bash(python *)",
      "Bash(python3)",
      "Bash(python3 *)",
      "Bash(pip *)",
      "Bash(pip3 *)"
    ],
    "deny": [
      "Read(*/.env)",
      "Edit(*/.env)",
      "Write(*/.env)",
      "Bash(cat .env)",
      "Bash(grep .env)",
      "Bash(head .env)",
      "Bash(tail .env)",
      "Bash(less .env)",
      "Bash(sed .env)",
      "Bash(awk .env)",
      "Bash(cp .env)",
      "Bash(mv .env)",
      "Bash(source .env)",
      "Bash(env)",
      "Bash(env *)",
      "Bash(printenv)",
      "Bash(printenv *)",
      "Bash(set)",
      "Bash(export)",
      "Bash(rm *)",
      "Bash(rmdir *)",
      "Bash(unlink *)",
      "Bash(find * -delete*)",
      "Bash(git clean *)"
    ]
  }
}
```

### dbt MCP server

The [dbt MCP server](https://github.com/dbt-labs/dbt-mcp) lets Claude Code run dbt commands (`parse`, `compile`, `run`, `test`, `build`, `show`, …) and inspect models and lineage directly in this project. It is configured in `.mcp.json` at the repo root and runs fully locally — no dbt Cloud account is needed.

#### Prerequisites

1. **dbt in a project virtual environment** — the server runs dbt from `.venv/bin/dbt`. Create it from the project folder (dbt needs Python 3.9 or newer):
   ```
   python3 -m venv .venv
   .venv/bin/python -m pip install dbt-core dbt-postgres
   ```
2. **uv** — the server is started with `uvx`, which also downloads the Python version dbt-mcp needs (3.12+), independent of your system Python. Install it with the official installer:
   ```
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```
   This installs `uv` and `uvx` into `~/.local/bin`. Open a new terminal (or run `source $HOME/.local/bin/env`) and check with `uvx --version`.
   > On older macOS versions (e.g. Intel Macs on Big Sur), prefer this installer over `brew install uv` — Homebrew has no prebuilt packages there and builds LLVM and Rust from source, which takes hours.
3. **Credentials in `.dotenv/.dev.env`** — the server loads the `DBT_*` variables from this file when it starts (see [Credentials](#credentials)). Create it from the template and fill in your values:
   ```
   cp .dotenv/example_env.txt .dotenv/.dev.env
   ```
   `.dotenv/*.env` is in `.gitignore`, so this file is never committed.
4. **The database is running** — `docker compose up` (see [Setup](#setup)).

#### How it is configured

`.mcp.json` registers a server named `dbt`:

```json
{
  "mcpServers": {
    "dbt": {
      "command": "bash",
      "args": [
        "-c",
        "set -a; source .dotenv/.dev.env; set +a; exec \"$HOME/.local/bin/uvx\" dbt-mcp"
      ],
      "env": {
        "DBT_PROJECT_DIR": ".",
        "DBT_PROFILES_DIR": ".",
        "DBT_PATH": ".venv/bin/dbt",
        "DISABLE_SEMANTIC_LAYER": "true",
        "DISABLE_DISCOVERY": "true",
        "DISABLE_ADMIN_API": "true",
        "DISABLE_SQL": "true",
        "DISABLE_LSP": "true"
      }
    }
  }
}
```

- The `bash -c` wrapper exports the variables from `.dotenv/.dev.env` and then starts `dbt-mcp`, so **no credentials are written in `.mcp.json`**.
- `DBT_PROJECT_DIR`, `DBT_PROFILES_DIR`, and `DBT_PATH` point the server at this project, its env-based `profiles.yml`, and the `.venv` dbt.
- The `DISABLE_*` flags turn off the features that need a dbt Cloud account (Semantic Layer, Discovery, Admin API, remote SQL, LSP). Note that dbt-mcp also uses the name `DBT_HOST` for a dbt Cloud host; with these features disabled, the database `DBT_HOST` from the env file is only used by dbt itself.

#### Enable and verify

1. Restart Claude Code (or reload the VS Code window) from the project folder — `.mcp.json` is read at startup.
2. Approve the project MCP server `dbt` when prompted.
3. Run `/mcp` in Claude Code and check that `dbt` is listed as connected, with tools such as `parse`, `compile`, `run`, `test`, `build`, `show`, `list`, `get_node_details_dev`, and `get_lineage_dev`.
4. Ask Claude to parse the project. `parse` runs without a prompt (it is allowed in the global settings above); other dbt tools ask for permission the first time.

#### Troubleshooting

- **Server fails to start / `uvx: No such file or directory`** — `uv` is not installed in `~/.local/bin`; repeat prerequisite 2.
- **`Env var required but not provided: 'DBT_...'`** — `.dotenv/.dev.env` is missing, misses a variable, or uses spaces around `=`. Every line must be `KEY=value`.
- **Connection errors from `parse`/`run`** — the database is not running, or the env file values do not match the database Docker created (see the note on `docker compose down` in [Credentials](#credentials)).
- **Server not listed in `/mcp`** — start Claude Code from the project folder so it finds `.mcp.json`.

### Project files

- `.mcp.json` — dbt MCP server configuration (see [dbt MCP server](#dbt-mcp-server)).
- `.claude/settings.json` — project-level deny rules shared with everyone who clones the repo: the same denials as the global settings above, plus blocking reads of `.env`, `.env.*`, and `*.pem` files at any depth.
- `.claude/rules/commit-dbt-changes.md` — commit workflow: branch check, secret hygiene, layer-ordered commits (sources → staging → intermediate → marts), and PR summaries.
- `.claude/rules/dbt-documentation-testing.md` — documentation and testing standards: one YAML per model, required description content, doc blocks for every column, source data contracts, mart contracts, no test thresholds.
- `.claude/rules/challenge-modeling-requests.md` — every modeling request is checked against best practice first; a conflict is shown with profiling numbers, and the user decides.
- `.claude/skills/` — step-by-step procedures, one per task: `onboard-raw-source`, `build-staging-model`, `build-intermediate-model`, `build-mart-model`, `write-eda-analysis` (EDAs in `analyses/`), and `verify-api-assumptions` (checks the project's assumptions about Pipedrive against Pipedrive's own documentation, its developer forum and Stack Overflow only, quoted with links).
- `.claude/tasks/sales-funnel.md` — the project's working memory: goal, current state of every model, data findings, and every decision with its date and reason.
- `.claude/tasks/api-assumptions.md` — the `verify-api-assumptions` report: what Pipedrive's documentation confirms about each assumption.
- `analyses/` — the exploratory data analysis: 14 saved profiling queries, one question each, behind every data finding the models rely on (source overview, staging grains, activity linkage, stage skips, the funnel, durations, the 5 shared deal IDs …). Each starts with its question, run command, dated result and conclusion; run one with `dbt show --select <name>`. Written with the `write-eda-analysis` skill.

## Project
1. Remove the test model once you make sure it works
2. Dive deep into the Pipedrive CRM source data to gain a thorough understanding of all its details. (You may also research the Pipedrive CRM tool terms).
3. Define DBT sources and build the necessary layers organizing the data flow for optimal relevance and maintainability.
4. Build a reporting model (rep_sales_funnel_monthly) with monthly intervals, incorporating the following funnel steps (KPIs):  
  &nbsp;&nbsp;&nbsp;Step 1: Lead Generation  
  &nbsp;&nbsp;&nbsp;Step 2: Qualified Lead  
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Step 2.1: Sales Call 1  
  &nbsp;&nbsp;&nbsp;Step 3: Needs Assessment  
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Step 3.1: Sales Call 2  
  &nbsp;&nbsp;&nbsp;Step 4: Proposal/Quote Preparation  
  &nbsp;&nbsp;&nbsp;Step 5: Negotiation  
  &nbsp;&nbsp;&nbsp;Step 6: Closing  
  &nbsp;&nbsp;&nbsp;Step 7: Implementation/Onboarding  
  &nbsp;&nbsp;&nbsp;Step 8: Follow-up/Customer Success  
  &nbsp;&nbsp;&nbsp;Step 9: Renewal/Expansion
5. Column names of the reporting model: `month`, `kpi_name`, `funnel_step`, `deals_count`
6. “Git commit” all the changes and create a PR to your forked repo (not the original one). Send your repo link to us.