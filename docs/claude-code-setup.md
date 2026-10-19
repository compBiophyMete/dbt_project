# Claude Code setup

How to set up Claude Code (permissions and the dbt MCP server) for this repository. See the [README](../README.md#how-the-repo-works-human-directed-agent-executed) for how the agent works with the rules and skills.

## Global permissions (`~/.claude/settings.json`)

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

## dbt MCP server

The [dbt MCP server](https://github.com/dbt-labs/dbt-mcp) lets Claude Code run dbt commands (`parse`, `compile`, `run`, `test`, `build`, `show`, …) and inspect models and lineage directly in this project. It is configured in `.mcp.json` at the repo root and runs fully locally — no dbt Cloud account is needed.

### Prerequisites

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
3. **Credentials in `.dotenv/.dev.env`** — the server loads the `DBT_*` variables from this file when it starts (see [Credentials](../README.md#configure-credentials)). Create it from the template and fill in your values:
   ```
   cp .dotenv/example_env.txt .dotenv/.dev.env
   ```
   `.dotenv/*.env` is in `.gitignore`, so this file is never committed.
4. **The database is running** — `docker compose up` (see [Setup](../README.md#quickstart)).

### How it is configured

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

### Enable and verify

1. Restart Claude Code (or reload the VS Code window) from the project folder — `.mcp.json` is read at startup.
2. Approve the project MCP server `dbt` when prompted.
3. Run `/mcp` in Claude Code and check that `dbt` is listed as connected, with tools such as `parse`, `compile`, `run`, `test`, `build`, `show`, `list`, `get_node_details_dev`, and `get_lineage_dev`.
4. Ask Claude to parse the project. `parse` runs without a prompt (it is allowed in the global settings above); other dbt tools ask for permission the first time.

### Troubleshooting

- **Server fails to start / `uvx: No such file or directory`** — `uv` is not installed in `~/.local/bin`; repeat prerequisite 2.
- **`Env var required but not provided: 'DBT_...'`** — `.dotenv/.dev.env` is missing, misses a variable, or uses spaces around `=`. Every line must be `KEY=value`.
- **Connection errors from `parse`/`run`** — the database is not running, or the env file values do not match the database Docker created (see the note on `docker compose down` in [Credentials](../README.md#configure-credentials)).
- **Server not listed in `/mcp`** — start Claude Code from the project folder so it finds `.mcp.json`.
