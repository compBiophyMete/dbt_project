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

### Project files

- `.claude/settings.json` — project-level deny rules shared with everyone who clones the repo: the same denials as the global settings above, plus blocking reads of `.env`, `.env.*`, and `*.pem` files at any depth.
- `.claude/rules/commit-dbt-changes.md` — commit workflow: branch check, secret hygiene, layer-ordered commits (sources → staging → intermediate → marts), and PR summaries.
