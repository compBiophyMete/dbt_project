## Setup

1. Download Docker Desktop (if you don’t have installed) using the official website, install and launch.
2. Fork this Github project to you Github account. Clone the forked repo to your device.
3. Open your Command Prompt or Terminal and navigate to the project folder.
4. Create your local `.env` and export it in that terminal, as described in [Credentials](#credentials) below. Do this **before** starting Docker: the database is created with the user, password, database name, and port from your `.env`.
5. In the same terminal, run `docker compose up`.
6. Connect to the db via a preferred tool (e.g. DataGrip, Dbeaver etc) using the credentials from your `.env`.
7. Install dbt-core and dbt-postgres using pip (if you don’t have) on your preferred environment.
8. Now you can run `dbt run` with the test model and check public_pipedrive_analytics schema to see the dbt result (with one test model). Run dbt from a terminal where the `.env` is exported.

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

.venv/bin/dbt build                            # runs models + tests; Elementary logs the results
.venv/bin/dbt docs generate --static           # writes target/static_index.html
.venv/bin/edr report --profiles-dir .edr       # writes edr_target/elementary_report.html
```

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