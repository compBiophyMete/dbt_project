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
      _pipedrive__docs.md         # Shared doc blocks
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

- **Use `{{ doc() }}` macros for common columns** — maintain centralized documentation in `_docs.md` files
  - **Check existing doc keys first**: If a column is already documented elsewhere, reuse the same `{{ doc('existing_key') }}` macro and docstring key
  - **Create new doc entries**: If no existing documentation is found, add the doc entry to the closest `_docs.md` file relative to your model
- **Write custom descriptions** for transformed columns or model-specific context
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

dbt's `contract: enforced` only works on models, not sources. Every source table must still have an explicit **data contract** expressed as tests, so upstream schema or semantic changes fail loudly at the source instead of silently breaking staging and downstream models.

Every source table must define:

1. **Schema contract**: what columns exist and their types
   - Declare **every column** the project uses, each with a `data_type` (Postgres types, e.g. `integer`, `text`, `timestamp`) and a description
   - Test the column set with `dbt_expectations.expect_table_columns_to_match_set` (or `expect_table_columns_to_contain_set` if the source may legitimately add columns)
   - Test the types of the columns the project relies on with `dbt_expectations.expect_column_values_to_be_of_type`
2. **Key contract**: the grain of the table
   - `unique` + `not_null` on the primary key (or `dbt_utils.unique_combination_of_columns` for composite keys)
   - `relationships` tests for foreign keys to other source tables (e.g. `deal_changes.deal_id` → `deals.deal_id`)
3. **Value contract**: what the values mean
   - `not_null` on columns that downstream logic depends on
   - `accepted_values` on enumerations (e.g. stage IDs, `changed_field_key`)
   - Range/format checks where relevant (e.g. timestamps not in the future, non-negative amounts)

**Scope**: schema-contract tests check table metadata and always run on the whole table. Key and value contract tests follow the scope above: the 30-day `where` window for ongoing loads, the full table for static loads.

**Severity**: schema and key contract tests use `severity: error`. Value contract tests may use `warn` when the source is known to be noisy; document why in the test or column description.

**Staging boundary**: the `stg_` model directly on top of each source should set `contract: enforced: true` with `data_type` on every column, so the cleaned interface the rest of the project depends on is enforced at build time.

**Package dependency (optional)**: the column-set and column-type checks come from the `dbt_expectations` package (and composite keys from `dbt_utils`). They are optional — built-in dbt tests plus the enforced staging contract cover most needs. If a source needs them and they are not in `packages.yml`, ask the user before adding them and running `dbt deps`.

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
        tests:
          - dbt_expectations.expect_table_columns_to_match_set:   # optional package
              column_list: ["deal_id", "change_time", "changed_field_key", "new_value"]
        columns:
          - name: deal_id
            data_type: integer
            tests:
              - not_null
          - name: change_time
            data_type: timestamp
            tests:
              - not_null
          - name: changed_field_key
            data_type: text
            tests:
              - not_null
              - accepted_values:
                  values: ["add_time", "stage_id", "user_id", "lost_reason"]
          - name: new_value
            data_type: text

      - name: activity
        description: >
          One row per sales activity on a deal. Contract tests cover the full table (static load).
        columns:
          - name: activity_id
            data_type: integer
            tests:
              - unique
              - not_null
          - name: type
            data_type: text
            tests:
              - relationships:
                  to: source('postgres_public', 'activity_types')
                  field: type
          - name: assigned_to_user
            data_type: integer
            tests:
              - relationships:
                  to: source('postgres_public', 'users')
                  field: id
```

For an ongoing source, add the window to each key/value test instead, e.g.:

```yaml
              - not_null:
                  config:
                    where: "change_time >= current_date - interval '30 days'"
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
- [ ] Common columns use centralized `{{ doc() }}` references
- [ ] Tests only on transformed/critical columns
- [ ] Documentation column order matches model column order
- [ ] Source tests scoped to the last 30 days for ongoing loads (recency timestamp documented), or to the full table for static loads
- [ ] Every source table has a data contract: schema (columns + `data_type`), key (`unique` / `not_null` / `relationships`), and value (`accepted_values`, ranges) tests
- [ ] `stg_` models directly on sources have `contract: enforced: true` with `data_type` on every column
- [ ] Materialization strategy appropriate for model size/usage
- [ ] Incremental models with a lookback buffer have `tag: incremental` in `config.tags`
- [ ] Schedule tags (`hourly` / `daily` / `12h`) are in `config.tags`, not `meta.tags`
- [ ] Model is named with the correct layer prefix (`stg_` / `int_` / `fct_` / `dim_` / `rep_`) and lives in the matching folder
