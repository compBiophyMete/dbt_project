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
      stg_pipedrive__deals.sql
      stg_pipedrive__deals.yml    # Single model documentation
  intermediate/
    int_deal_stage_changes.sql
    int_deal_stage_changes.yml
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
3. **Business Logic**: Key transformations, calculations, or aggregations applied
4. **Edge Cases**: Document complex scenarios (deals skipping or revisiting stages, deals changing stage multiple times in a month, null handling)
5. **Refresh Schedule**: How often the model is updated and any freshness considerations

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
- **Data quality**: freshness tests for critical staging models — remind the user and ask for input on whether it is a critical model

### Source YAML Testing Rule

- **Applies to source definitions**: For source files (`sources.yml` / `*_sources.yml`), the test scope depends on how the source table is loaded:
  - **Ongoing loads** (the table keeps receiving new rows, and has a timestamp that reflects when a row arrived or changed): validate over the **most recent 30 days** using a test-level `where` config, e.g. `where: "<timestamp_col> >= current_date - interval '30 days'"`.
  - **Static or one-time loads** (historical snapshots, seed-like reference tables, or tables without a load/change timestamp): test the **full table** — no `where` filter. A recency filter on static data selects zero rows and makes every test pass without checking anything.
- **Use case**: The 30-day window is the default baseline for ongoing sources unless a table-specific SLA requires a different period.
- **Documentation expectation**: In each source table's description, state which scope applies — "last 30 days on `<timestamp_col>`" or "full table (static load)". If unsure whether a source is loaded on an ongoing basis, ask the user.

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

**Package dependency**: Elementary (in `packages.yml`) is required for the schema contract. `dbt_utils` (composite keys) and `dbt_expectations` (use the maintained `metaplane/dbt_expectations`) are optional extras. If a source needs an optional package that isn't in `packages.yml`, ask the user before adding it and running `dbt deps`. If a source needs them and they are not in `packages.yml`, ask the user before adding them and running `dbt deps`.

**YAML syntax (dbt ≥ 1.10.8)**: declare tests under `data_tests:` (not `tests:`), and put every generic-test input under `arguments:`. Only framework settings (`severity`, `where`, …) go under `config:`. Top-level arguments raise `MissingArgumentsPropertyInGenericTestDeprecation`.

Example (this project's static Pipedrive load — full-table scope, no `where` filter):

```yaml
version: 2

sources:
  - name: postgres_public
    database: postgres
    schema: public
    description: Raw Pipedrive CRM tables loaded once from CSV via init.sql.
    tables:
      - name: deal_changes
        description: >
          One row per change to a deal field. Contract tests cover the full table (static load).
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
          One row per sales activity on a deal. Contract tests cover the full table (static load).
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
                    to: source('postgres_public', 'activity_types')
                    field: type
          - name: assigned_to_user
            data_type: integer
            data_tests:
              - relationships:
                  arguments:
                    to: source('postgres_public', 'users')
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

- **Follow naming conventions**: `stg_` for staging, `int_` for intermediate, and `fct_` / `dim_` / `rep_` for marts (e.g., `rep_sales_funnel_monthly`)
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
| **Lookback buffer** | Inside `{% if is_incremental() %}`, a sliding window such as `updated_at >= (select max(updated_at) from {{ this }}) - interval 'N days'`, or OR-ed lookbacks on multiple timestamps | Reprocesses the last **N days** on each run | **Yes** |

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
- [ ] Model is named with the correct layer prefix (`stg_` / `int_` / `fct_` / `dim_` / `rep_`) and lives in the matching folder
