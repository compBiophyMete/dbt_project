---
paths:
  - "models/**/*.yml"
  - "models/**/*.sql"
  - "seeds/**/*.yml"
---

# dbt Model Documentation and Testing Standards

## Model Documentation Requirements

### YAML File Structure

- **One YAML file per model**: Each model (`<model_name>.sql`) must have its own corresponding YAML file (`<model_name>.yml`) placed in the same directory. The YAML file should contain:
  - `version: 2` header
  - A single `models:` block with one entry for that model only
  - Model description, config, meta, tests, and column documentation
- **Seed tables**: Apply the same logic as mentioned above for models
- **Exposures in separate files**: If you need to define `exposures:` (or other non-model metadata), create **one exposures-only YAML per folder** (e.g., `<folder>/_<folder>__exposures.yml`). Keep this file in the same folder as the related models so every directory has its dedicated exposures file and each model YAML stays single-model only
- **Do not create grouped model YAMLs**: Avoid creating `_something__models.yml` files that contain multiple models. Each model should have its own standalone YAML file

Example structure:

```
models/
  staging/
    pipedrive/
      _pipedrive__sources.yml     # Source definitions
      _pipedrive__docs.md         # Column doc blocks
      stg_pipedrive__deals.sql    # stg_<source>__<entity>s (dbt naming convention), built as stg_pipedrive.stg_pipedrive__deals
      stg_pipedrive__deals.yml    # Single model documentation
  intermediate/
    deals/                        # business-area folder (dbt guide: by business concern, not source)
      _intermediate_deals__docs.md
      int_deal_changes_filtered_to_stages.sql   # int_<entity>s_<verb>s
      int_deal_changes_filtered_to_stages.yml
  marts/
    rep_sales_funnel_monthly.sql
    rep_sales_funnel_monthly.yml
    _marts__exposures.yml         # Exposures (if needed)
```

### Description Standards

Every dbt model description must include:

1. **Purpose and Context**: What business problem does this model solve?
2. **Row Granularity**: Always explicitly state what one row represents
   - ✅ "One row per deal"
   - ✅ "One row per month per funnel step (KPI)"
3. **Transformations and business logic**: Transformations (renames, casts, cleaning, standardizing formats) and business logic (rules that decide meaning, calculations, aggregations) applied. **Staging models have no business logic**, so in staging this section is headed **Transformations** only and covers renames, casts, value mappings, typed columns and deduplication ([dbt's staging guide](https://docs.getdbt.com/best-practices/how-we-structure/2-staging): renaming, type casting, basic computations, categorizing). Rules that decide what values mean live in intermediate; a staging description at most points to the `int_` model that applies them. Intermediate and mart models keep the full heading
4. **Edge Cases**: Document complex scenarios (deals skipping or revisiting stages, deals changing stage multiple times in a month, null handling)
5. **Refresh Schedule**: How often the model is updated and any freshness considerations

**Keep descriptions concise**: one short paragraph or one bullet per point, in the five sections above and nothing else. State each rule once, in plain words. Leave out what the reader can see elsewhere: test descriptions (the YAML's tests show them), implementation mechanics (macros, indexes, predicate pushdown, guards), quoted reasoning behind a decision (task file), and facts already in a doc block (timezones, API field names). Each wrapped bullet of a folded `>` block goes on one line, or the indented continuation keeps a stray line break.

**No counts or profiling results in documentation**: the data is dynamic, so a number written into a description goes stale without anything noticing. This applies to every source, staging, intermediate and mart description, column doc block, test comment and exposure:

- Don't write row counts, value counts, shares, medians, date ranges of the data, example IDs taken from the data, or "profiled <date>" / "today" claims.
- Describe the finding in words (what it is, why it matters, how the model handles it): "some activity IDs are reused on a second deal", not "11 IDs appear twice".
- In model descriptions, point to the analysis that holds the numbers: `Evidence: analyses/profile_<subject>.sql` (source descriptions carry no evidence links). The dated result lives there only (see the `write-eda-analysis` skill), and a reviewer reruns it to get the current numbers.
- Still allowed: business definitions and domains enforced by tests (stage IDs 1–9, the funnel steps of the brief, accepted values), configuration (lookback windows), format examples (`2024-03-01`), and quoted vendor documentation.
- **No decision codes and no decision log**: never write task-file decision IDs (`D1`, `D3` …), "user's decision, <date>", "revised <date>", "added <date> at the user's request" or version notes in any YAML description or doc block. State the rule itself in words ("a skipped stage still counts"); its history and date live in the task file and git.

**Where descriptions live**: model, seed, source, and source-table descriptions are written **inline in the YAML** (use a `>` block for multi-line text), never as a `{{ doc() }}` reference. A table's description is read once and belongs next to the table's config and tests; only column descriptions go in `_docs.md` doc blocks (see Column Documentation Strategy).

### Exposure Documentation Standards

Every exposure must include:

1. **Purpose and context**: A clear explanation of the business purpose of the dashboard or artifact and the problem it solves.
2. **Data contract**: Must explicitly include:
   - The name of the mart model driving the dashboard
   - What one row represents, e.g.:
     - ✅ "One row per deal"
     - ✅ "One row per month per funnel step (KPI)"
3. **Refresh schedule**: Update frequency + any freshness constraints or considerations.

### Column Documentation Strategy

- **Every column description must be a `{{ doc() }}` reference** (`description: "{{ doc('<key>') }}"`) to a doc block in a `_docs.md` file. No inline text for column descriptions, in models, seeds, or sources
  - **Check existing doc keys first**: If a column is already documented elsewhere, reuse the same `{{ doc('existing_key') }}` macro and docstring key
  - **Create new doc entries**: If no existing documentation is found, add the doc entry to the closest `_docs.md` file relative to your model
  - **Key naming**: columns that mean the same thing across tables/models share one key named after the column (e.g. `deal_id`); table- or model-specific columns use `<table_or_model>__<column>` (e.g. `activity__done`)
- **Transformed columns and model-specific context** still get their own doc block (e.g. `rep_sales_funnel_monthly__deals_count`) rather than an inline description
- **Doc blocks are neutral**: say what the value is (type, unit, format, what null means) and, for a derived column, the one-line definition of how it is computed. No key roles ("primary key", "referencing …"; tests and constraints show them), no business rules or their reasoning, no edge cases or data findings (those belong in the model description), no claims about the current data. Allowed extras: a short join warning on a non-unique column, and API v1/v2 field names with their link
- **Match model column order**: document columns in the same order as they appear in the model for easier cross-checking
- **Include units and formats** where applicable (e.g., "duration in days", "percentage as decimal")

## Testing Strategy

### When to Test

- **Skip tests** for untransformed upstream columns already tested in upstream models
- **Always test** transformed columns: joins, calculations, aggregations, business logic
- **Use generic tests** (`unique`, `not_null`, `relationships`) over singular tests when possible
- **Consider performance** — avoid expensive tests on large models

### Essential Test Types

- **Primary keys**: `unique` + `not_null`
- **Foreign keys**: `relationships` tests
- **Business rules**: `accepted_values`, range checks, custom business logic tests
- **Data quality**: every source table with a load or change timestamp gets a source freshness check (a planned date such as `activity.due_to` doesn't count) (`config: loaded_at_field` + `freshness`), even on a static load, so the project is ready for a live feed. Thresholds follow the load schedule: daily → warn after 1 day, error after 2 days; hourly → warn after 1 hour, error after 2 hours. A table without a timestamp gets the check on `_loaded_at` once the loader adds it

### Source YAML Testing Rule

- **Applies to source definitions**: For source files (`sources.yml` / `*_sources.yml`), the test scope depends on how the source table is loaded:
  - **Ongoing loads** (the table keeps receiving new rows, and has a timestamp that reflects when a row arrived or changed): validate over the **most recent 30 days** using a test-level `where` config, e.g. `where: "<timestamp_col> >= current_date - interval '30 days'"`.
  - **Static or one-time loads** (historical snapshots, seed-like reference tables, or tables without a load/change timestamp): test the **full table** — no `where` filter. A recency filter on static data selects zero rows and makes every test pass without checking anything.
- **Use case**: The 30-day window is the default baseline for ongoing sources unless a table-specific SLA requires a different period.
- **Documentation expectation**: In each source table's description, state which scope applies — "last 30 days on `<timestamp_col>`" or "full table (static load)" — and the freshness check (column and thresholds, or that it waits for `_loaded_at`). The source description carries the overall **Freshness assumption** (assumed load schedule, active and pending checks). If unsure whether a source is loaded on an ongoing basis, ask the user. Full pattern: the `onboard-raw-source` skill.

### Source Data Contract Tests

dbt's `contract: enforced` only works on models, not sources: a contract is enforced when dbt builds a table, and dbt never builds a source. dbt's guidance is to test assumptions about source data at the source. So every source table must have an explicit **data contract** expressed as tests, so upstream schema or semantic changes fail loudly at the source instead of silently breaking downstream models.

**`data_type` alone checks nothing.** On a source column, `data_type` is documentation only — dbt never compares it with the warehouse, and dbt core has no built-in test that does. Checking columns and types at the source needs a custom test; this project uses the one Elementary ships: `elementary.schema_changes_from_baseline`.

Every source table must define:

1. **Schema contract**: what columns exist and their types
   - Declare **every column** in the table, each with a description and a `data_type`
   - Add `elementary.schema_changes_from_baseline` at table level with `fail_on_added: true` and `enforce_types: true`. It compares the declared columns and types with the warehouse and fails on any added column, removed column, or type change. `enforce_types: true` makes a missing `data_type` a compile error
   - **Write `data_type` as `information_schema.columns.data_type` reports it — without size or precision**: `integer`, `character varying`, `timestamp without time zone`, `boolean`, `jsonb`. Elementary reads the warehouse type without size, so `character varying(50)` fails against a `varchar(50)` column
   - Known limit: size or precision changes (e.g. `varchar(50)` → `varchar(255)`) are not detected
   - The test only queries the warehouse during `dbt test` / `dbt build` (other commands compile it to an empty query)
2. **Key contract**: the grain of the table
   - `unique` + `not_null` on the primary key (or `dbt_utils.unique_combination_of_columns` for composite keys)
   - `relationships` tests for foreign keys to other source tables (e.g. `deal_changes.deal_id` → `deals.deal_id`)
3. **Value contract**: what the values mean
   - `not_null` on columns that downstream logic depends on
   - `accepted_values` on enumerations (e.g. stage IDs, `changed_field_key`)
   - Range/format checks where relevant (e.g. timestamps not in the future, non-negative amounts)

**Scope**: the schema contract test reads table metadata, so it always covers the whole table — never give it a `where` config. Key and value contract tests follow the scope above: the 30-day `where` window for ongoing loads, the full table for static loads.

**Severity**: schema and key contract tests use `severity: error`. Value contract tests may use `warn` when the source is known to be noisy; document why in the test or column description.

**No thresholds**: never set `warn_if` / `error_if` on any test, in any layer. If something is wrong, the test fails, even for a known, documented issue. Explain that it fails on purpose, why, and which analysis to rerun (no counts: see "No counts or profiling results in documentation"), so the failure is explained but still visible. Write it in the model description's **Edge cases** only, never on the test. **Sources report no data quality at all**: a source table description holds only purpose, grain, load / test scope and freshness, with no findings or evidence queries (pattern in the `onboard-raw-source` skill); a known source failure is explained in the staging model that handles the table. Shared column doc blocks may keep a short join warning (e.g. "Not unique … never join on it"), because staging reuses them. A failing test gets no `description` and no inline comment.

**Package dependency**: Elementary (in `packages.yml`) is required for the schema contract. `dbt_utils` (composite keys) and `dbt_expectations` (use the maintained `metaplane/dbt_expectations`) are optional extras. If a source needs an optional package that isn't in `packages.yml`, ask the user before adding it and running `dbt deps`. If a source needs them and they are not in `packages.yml`, ask the user before adding them and running `dbt deps`.

**YAML syntax (dbt ≥ 1.10.8)**: declare tests under `data_tests:` (not `tests:`), and put every generic-test input under `arguments:`. Only framework settings (`severity`, `where`, …) go under `config:`. Top-level arguments raise `MissingArgumentsPropertyInGenericTestDeprecation`.

Example (this project's static Pipedrive load — full-table scope, no `where` filter):

```yaml
version: 2

sources:
  - name: pipedrive
    database: postgres
    schema: public
    description: Raw Pipedrive CRM tables loaded once from CSV via init.sql.
    tables:
      - name: deal_changes
        description: >
          Change log of deal fields.


          **Grain**: one row per deal, change time and changed field (`deal_id`, `change_time`,
          `changed_field_key`). `init.sql` declares no key; a test checks that the combination is unique.


          **Load / test scope**: static load from `raw_data/deal_changes.csv`. Contract tests cover the full
          table.


          **Freshness**: none expected today, because the data is a static load. For a live feed the
          check is ready on `change_time`: warning after 1 day, error after 2 days.
        config:
          tags: ["pipedrive"]
          loaded_at_field: change_time
          freshness:
            warn_after: {count: 1, period: day}
            error_after: {count: 2, period: day}
        data_tests:
          - elementary.schema_changes_from_baseline:
              arguments:
                fail_on_added: true
                enforce_types: true
        columns:
          - name: deal_id
            data_type: integer
            data_tests:
              - not_null
          - name: change_time
            data_type: timestamp without time zone
            data_tests:
              - not_null
          - name: changed_field_key
            data_type: character varying
            data_tests:
              - not_null
              - accepted_values:
                  arguments:
                    values: ["add_time", "stage_id", "user_id", "lost_reason"]
          - name: new_value
            data_type: character varying

      - name: activity
        description: >
          Sales activities (calls, meetings, follow-ups) linked to deals and assigned to users.


          **Grain**: one row per activity per deal (`activity_id`, `deal_id`). `init.sql` declares no key; a
          test checks that the pair is unique.


          **Load / test scope**: static load from `raw_data/activity.csv`. Contract tests cover the full
          table.


          **Freshness**: none today; `due_to` is a planned date, not a load time, so the check waits for a
          `_loaded_at` column (see the `onboard-raw-source` skill for the wording).
        data_tests:
          - elementary.schema_changes_from_baseline:
              arguments:
                fail_on_added: true
                enforce_types: true
        columns:
          - name: activity_id
            data_type: integer
            data_tests:
              - unique
              - not_null
          - name: type
            data_type: character varying
            data_tests:
              - relationships:
                  arguments:
                    to: source('pipedrive', 'activity_types')
                    field: type
          - name: assigned_to_user
            data_type: integer
            data_tests:
              - relationships:
                  arguments:
                    to: source('pipedrive', 'users')
                    field: id
          - name: deal_id
            data_type: integer
          - name: done
            data_type: boolean
          - name: due_to
            data_type: timestamp without time zone
```

For an ongoing source, add the window to each key/value test instead, e.g.:

```yaml
              - not_null:
                  config:
                    where: "change_time >= current_date - interval '30 days'"
```

### Model Contracts (Marts)

A contract is an API guarantee to the consumers of a model: its columns and their types. dbt recommends contracts for "public" models relied on downstream — dashboards, reports, other teams. In this project that means **every mart model** (`rep_*`, `fct_*`, `dim_*`): each must set `contract: enforced: true` and declare a `data_type` on **every** column. Without `data_type` values the contract has nothing to check.

Contracts check the *shape* of a model; tests check its *content*. Data quality stays with tests.

**What dbt enforces** (this project materializes models as `table` on Postgres):

1. **Preflight check**: before building, dbt runs the model's SQL with no rows returned and compares the output column names, types, and count with the YAML. Any mismatch fails the model before a table is created.
2. **DDL**: dbt creates the table with the declared types and constraints (`create table (... integer not null ...)`), then inserts the data. Postgres enforces every constraint type (`not_null`, `unique`, `primary_key`, `foreign_key`, `check`); a violating row fails the insert, and the model fails.

**Why it matters**: a mart's shape is what a dashboard or reviewer depends on. An enforced contract turns an accidental change, such as a renamed, dropped, or retyped column, into a build failure instead of a broken dashboard. Once a contract exists, removing a column or changing its type is a breaking change; agree it with the consumers first.

**How to write it:**

- **Write exact Postgres types with size/precision**, e.g. `character varying(50)`, `numeric(38, 2)`. (This differs from sources, where Elementary needs types without size.) The preflight ignores size and precision, but the DDL uses the declared type, so a value longer than 50 characters fails the insert. Write `numeric` with an explicit scale; plain `numeric` can coerce away decimals.
- **Constraints vs. tests**: a constraint violation fails the whole build, while a test reports failing rows, can be set to `warn`, and shows failing-row samples in Elementary. Use a `not_null` constraint for guarantees that must hold, such as the primary key. Use tests for checks that should be reported and followed up.
- **Materialization**: `table` and `incremental` (with `on_schema_change: append_new_columns` or `fail`) enforce types and constraints. A `view` checks only names and types, with no constraints. `ephemeral` doesn't support contracts.
- **Timing**: add the contract once the model's shape is agreed. Contracts add maintenance and make changes harder, which is the point for a stable consumer-facing model.

**Staging and intermediate models**: contracts are optional. Source schema changes are caught at the source by `schema_changes_from_baseline`. Staging models should still list columns explicitly; never use `select *`.

Example (`rep_sales_funnel_monthly.yml`):

```yaml
version: 2

models:
  - name: rep_sales_funnel_monthly
    description: >
      One row per month per funnel step (KPI). Monthly deal counts for each step of the Pipedrive sales funnel.
    config:
      contract:
        enforced: true
    columns:
      - name: month
        data_type: date
        constraints:
          - type: not_null
      - name: kpi_name
        data_type: character varying(100)
        constraints:
          - type: not_null
      - name: funnel_step
        data_type: character varying(10)
        constraints:
          - type: not_null
      - name: deals_count
        data_type: integer
        constraints:
          - type: not_null
```

## Additional Best Practices

### Model Organization

- **Project tag (mandatory)**: every model and every source table carries the tag of the project it belongs to (this repo: `pipedrive`), so a whole project can be run, tested or checked for freshness with `--select tag:<project>`. Set it **in both places**: once in `dbt_project.yml` (`models: <dbt project>: +tags` and `sources: <dbt project>: +tags`), and again in every resource's own YAML, so a reader sees it in the file: `config: tags: ["pipedrive"]` on each model, and on each source table (under its `config:`). When `tags` already lists other tags (`daily`, `incremental`), the project tag comes first in that list. dbt tags "are additive across project hierarchy" ([dbt docs](https://docs.getdbt.com/reference/resource-configs/tags)), so the repeat changes no selection and model-level tags stack on top. When a second project or source system is added, move the tag down to that project's folders (e.g. `staging/<system>`) so each project gets its own
- **Follow naming conventions**: `stg_<source>__<entity>s` for staging (dbt's convention, e.g. `stg_pipedrive__activities`), `int_` for intermediate, and `fct_` / `dim_` / `rep_` for marts (e.g., `rep_sales_funnel_monthly`)
- **Respect the layer flow**: sources → staging → intermediate → marts. Staging selects only from sources; marts never select directly from sources
- **Use consistent materialization strategies** based on model purpose and size
- **Document model dependencies** clearly in descriptions

### Performance and Maintenance

- **Test strategically** — focus on business-critical transformations
- **Document incremental model config** for all incremental models with proper unique keys
- **Monitor test performance** and adjust frequency for expensive tests
- **Keep documentation up-to-date** with model changes

### Incremental Models and the `incremental` Tag

Use this whenever authoring or reviewing incremental models.

#### Lookback buffer strategy

| Strategy | SQL pattern | Late-arriving data | Needs `tag: incremental`? |
|----------|-------------|--------------------|---------------------------|
| **Lookback buffer** | Inside `{% if is_incremental() %}`, a sliding window such as `updated_at >= (select max(updated_at) from {{ this }}) - interval 'N days'`, or OR-ed lookbacks on multiple timestamps. In this project, write it with the `incremental_lookback_filter` macro (see the README's "Incremental Models" section) | Reprocesses the last **N days** on each run | **Yes** |

#### When `tag: incremental` is required

Add `incremental` to **`config.tags`** (never under `meta.tags`) when the model SQL implements a **lookback buffer** for late-arriving data, including:

- Sliding windows (e.g. `event_time >= current_date - interval '7 days'`)
- OR-combined lookbacks on multiple change timestamps (`add_time`, `update_time`, etc.) intended to catch late updates

The tag lets all buffered incrementals be run together, e.g. for a deeper backfill:

```bash
dbt run --select tag:incremental
```

#### When `tag: incremental` is not required

Do **not** add the tag for non-incremental materializations (`table`, `view`, `ephemeral`). Adding the tag alone does **not** create a buffer — the SQL must contain the lookback logic.

#### YAML requirements for buffered incrementals

1. **`config.tags`**: include `incremental` plus a schedule tag (`hourly`, `daily`, or `12h`).
2. **Refresh schedule** (in model description): document the run cadence and the lookback window.
3. **Edge cases**: note which timestamp drives the buffer and what happens to rows outside the window.

Example:

```yaml
config:
  materialized: incremental
  unique_key: deal_id
  tags:
    - daily
    - incremental
```

```
**Refresh Schedule**: Daily (3-day lookback on `update_time`). Rows updated outside the window are only picked up by a `--full-refresh`.
```

## Pre-Deployment Checklist

- [ ] Every model and seed has its own single-model YAML file in the same directory
- [ ] Model description includes row granularity and business purpose
- [ ] Edge cases documented where applicable
- [ ] No counts, profiling results, data date ranges or "today" claims in any description, doc block or test comment; findings point to their `analyses/` file
- [ ] Every test that fails on purpose is explained in the model description, not on the test; source table descriptions hold only purpose, grain, load / test scope and freshness
- [ ] Model/seed/source/table descriptions are inline in the YAML, not `{{ doc() }}` references
- [ ] Every column description is a `{{ doc() }}` reference to a `_docs.md` doc block (shared keys reused)
- [ ] Tests only on transformed/critical columns
- [ ] Documentation column order matches model column order
- [ ] Source tests scoped to the last 30 days for ongoing loads (recency timestamp documented), or to the full table for static loads
- [ ] Every source table declares every column with a `data_type` without size (`character varying`, not `character varying(50)`), and has `elementary.schema_changes_from_baseline` (`fail_on_added: true`, `enforce_types: true`) plus key (`unique` / `not_null` / `relationships`) and value (`accepted_values`, ranges) tests
- [ ] Tests declared under `data_tests:` with generic-test inputs under `arguments:`
- [ ] Every mart model (`rep_` / `fct_` / `dim_`) has `contract: enforced: true` with an exact Postgres `data_type` (with size/precision) on every column
- [ ] Staging models list columns explicitly (no `select *`)
- [ ] Materialization strategy appropriate for model size/usage
- [ ] Incremental models with a lookback buffer have `tag: incremental` in `config.tags`
- [ ] Schedule tags (`hourly` / `daily` / `12h`) are in `config.tags`, not `meta.tags`
- [ ] Model / source table carries its project tag (`pipedrive`) in `dbt_project.yml` **and** in its own YAML `config: tags` (check with `dbt ls --select tag:pipedrive`)
- [ ] Model is named with the correct layer prefix (`stg_` / `int_` / `fct_` / `dim_` / `rep_`) and lives in the matching folder
