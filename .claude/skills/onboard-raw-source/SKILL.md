---
name: onboard-raw-source
description: Onboard raw tables (the CSVs in raw_data/ loaded into Postgres via init.sql + load_data.sh) as a dbt source — every column declared exactly as it exists in the warehouse, with data-contract tests and docs per .claude/rules/dbt-documentation-testing.md. Use when asked to onboard, register, declare, or add raw data / a raw table / a CSV as a dbt source, or to "add sources.yml" for raw tables.
argument-hint: "[table names — default: every table in raw_data/]"
---

# Onboard raw data as a dbt source

Goal: declare raw tables as a dbt **source** that mirrors the warehouse **exactly as it is**, with a full data contract (schema, key, value tests) and documentation. The source is a faithful description of the raw data — never a transformation of it.

Standards for descriptions, doc blocks, test scope, and contracts live in [.claude/rules/dbt-documentation-testing.md](../../rules/dbt-documentation-testing.md). Read it first; this skill is the procedure that applies it to sources. If the two ever disagree, the rule wins.

## Non-negotiables

1. **Preserve the source as is.**
   - Do not edit `raw_data/*.csv`, `init.sql`, `load_data.sh`, or the warehouse tables. Onboarding is read-only against raw data.
   - No renaming, casting, aliasing, filtering, or dedup in the source definition. That is the staging layer's job (`stg_` models).
   - Column names are the names **as stored in Postgres** (from `information_schema`), not the CSV headers. Unquoted identifiers in `init.sql` are folded to lowercase (e.g. CSV header `FIELD_KEY` → column `field_key`). Only set `quote: true` on a column if its stored name is actually case-sensitive or contains special characters.
   - `data_type` is the Postgres type exactly as `information_schema.columns.data_type` reports it — **without size or precision** (e.g. `integer`, `character varying`, `timestamp without time zone`, `jsonb`). Never guess it from CSV values or use a shorthand like `varchar`/`timestamp`. The schema contract test (step 5) compares these strings, and it fails on `character varying(50)` because it reads the warehouse type without size. Record the full type (e.g. "max 50 characters") in the column description instead.
2. **Every column is onboarded.** The YAML column list must equal the warehouse column list, in ordinal order. No column skipped because it "looks unused".
3. **Tests come from evidence.** Every key/value test is backed by a profiling query you ran. Never add a test you haven't checked against the data, and never silently drop a test because the data fails it (see step 5).
4. **Read-only on the database**: only `select` queries via `dbt show` (MCP `mcp__dbt__show`, or `dbt show --inline`).

## Procedure

### 1. Discover the scope

- Raw inputs: `raw_data/*.csv` (one CSV → one table of the same basename, loaded by `raw_data/load_data.sh` into the schema created by `init.sql`).
- If the user named tables, onboard only those; otherwise every CSV in `raw_data/`.
- Find existing source definitions: `grep -rn "sources:" models/` and check which tables are already declared. Extend an existing source definition rather than creating a duplicate — dbt fails on a source/table declared twice.
- **Mismatch check**: a CSV with no table in the warehouse (or a table with no CSV) means the load is out of sync. Stop and report it; do not onboard a table that doesn't exist, and don't fix `init.sql` without the user's go-ahead.

### 2. Introspect the warehouse (schema contract)

Run for the schema (default `public`):

```sql
select
    c.table_name,
    c.ordinal_position,
    c.column_name,
    c.data_type,                                              -- goes into the YAML data_type
    pg_catalog.format_type(a.atttypid, a.atttypmod) as full_type,  -- size/precision, for the description
    c.is_nullable,
    (select string_agg(kcu.column_name, ',' order by kcu.ordinal_position)
       from information_schema.table_constraints tc
       join information_schema.key_column_usage kcu
         on tc.constraint_name = kcu.constraint_name and tc.table_schema = kcu.table_schema
      where tc.table_schema = c.table_schema and tc.table_name = c.table_name
        and tc.constraint_type = 'PRIMARY KEY') as declared_pk
from information_schema.columns c
join pg_catalog.pg_attribute a
  on a.attrelid = (quote_ident(c.table_schema) || '.' || quote_ident(c.table_name))::regclass
 and a.attname = c.column_name
where c.table_schema = 'public'
  and c.table_name in (<tables>)
order by c.table_name, c.ordinal_position
```

Use `limit` large enough to return every row (e.g. 500); confirm the row count equals the total number of columns.

### 3. Profile each table (key + value contract evidence)

For each table, in as few queries as possible:

- **Row count** and, for every column: null count, distinct count.
- **Primary key**: use `declared_pk` if present; otherwise propose a candidate (an `*_id` / `id` column where `count(distinct) = count(*)` and no nulls). If no single column is unique, test candidate combinations (e.g. `deal_id, change_time, changed_field_key`) and say clearly if the table has **no reliable grain** — that's a finding, not something to paper over.
- **Foreign keys**: for columns that reference another raw table by name or meaning (`deal_id`, `*_user` → `users.id`, `type` → `activity_types.type`, `stage_id`, `changed_field_key` → `fields.field_key`), count orphans:
  ```sql
  select count(*) as orphans
  from public.<child> c
  left join public.<parent> p on c.<fk> = p.<pk>
  where c.<fk> is not null and p.<pk> is null
  ```
- **Enumerations**: for text/boolean columns with low cardinality (≲ 20 distinct values), list the values with counts → `accepted_values` candidates.
- **Ranges**: min/max on timestamps (flag future dates, epoch-like defaults) and numeric columns (flag negatives where meaningless).
- **Polymorphic columns** (e.g. `deal_changes.new_value`, whose meaning depends on `changed_field_key`): document the dependency; test per-key only if cheap and clearly valuable.

Show the user a compact profile table per source table before writing YAML.

### 4. Decide the test scope (static vs ongoing)

Per the rule's "Source YAML Testing Rule":

- Tables loaded by `raw_data/load_data.sh` from CSV are a **static, one-time load** → test the **full table**, no `where` filter, and **no `freshness` block** (it would always fail).
- If the user says a table is loaded on an ongoing basis, use the 30-day `where` window on its load/change timestamp, and ask whether it is critical enough for a `freshness` check.
- If unsure, ask. State the chosen scope in each table description.

### 5. Choose the tests

Map evidence → tests (see the rule's "Source Data Contract Tests"):

| Contract | Test | Severity |
|---|---|---|
| Schema | Table-level `elementary.schema_changes_from_baseline` with `fail_on_added: true`, `enforce_types: true` on **every** table | error |
| Key | `unique` + `not_null` on the PK (or `dbt_utils.unique_combination_of_columns`) | error |
| Key | `relationships` on each FK with a parent raw table | error |
| Value | `not_null` on columns downstream logic needs | error, or warn if known noisy |
| Value | `accepted_values` on enumerations | error, or warn if known noisy |

**When the data already fails a contract test** (duplicate PKs, orphan FKs, unexpected values): keep the test, report the finding with counts, and ask the user whether to keep it at `error` (build fails until fixed upstream) or `severity: warn` with the reason written in the column/test description. Never weaken a test silently.

**Schema contract**: on its own, `data_type` on a source is documentation only. dbt has no built-in check and `contract: enforced` isn't available on sources. `elementary.schema_changes_from_baseline` is what enforces "every column, exactly as is":
- `fail_on_added: true` fails on any warehouse column missing from the YAML. Without it, new columns are silently ignored.
- Removed columns and type changes always fail.
- `enforce_types: true` makes a column without `data_type` a compile error.
- It does **not** detect size or precision changes (`varchar(50)` → `varchar(255)`). Say so in the report.
- It reads metadata, so never give it a `where` config. It only queries the warehouse during `dbt test` / `dbt build`.

**Packages**: Elementary (already in `packages.yml`) is required for the schema contract. `dbt_utils` (composite keys) and `dbt_expectations` (use the maintained `metaplane/dbt_expectations`, not the archived `calogica` one) are optional. If an optional package isn't in `packages.yml` and a test needs it, ask before adding it and running `dbt deps`; otherwise use built-in tests only.

**YAML syntax (dbt ≥ 1.10.8)**: use `data_tests:` (not `tests:`), and put every generic-test input under `arguments:`. Only framework settings (`severity`, `where`, …) go under `config:`. Top-level arguments raise `MissingArgumentsPropertyInGenericTestDeprecation`.

```yaml
data_tests:
  - elementary.schema_changes_from_baseline:
      arguments:
        fail_on_added: true
        enforce_types: true
columns:
  - name: type
    data_type: character varying
    description: "Activity type key (max 50 characters). ..."
    data_tests:
      - not_null
      - accepted_values:
          arguments:
            values: ["call", "meeting", "follow_up"]   # illustrative — use the profiled values
      - relationships:
          arguments:
            to: source('postgres_public', 'activity_types')
            field: type
          config:
            severity: warn   # reason documented in the column description
```

### 6. Write the files

Location follows the rule's example structure, grouped by source system:

```
models/staging/<system>/
  _<system>__sources.yml   # source definition (all tables of this source)
  _<system>__docs.md       # doc blocks for the source and its columns
```

For this project `<system>` is `pipedrive` and the source keeps its existing name `postgres_public` (database `postgres`, schema `public`) so current `source('postgres_public', ...)` refs keep working. If a source file already exists elsewhere (e.g. `models/sources.yml`), propose moving it with `git mv` into the conventional location and merging, rather than leaving two definitions. Ask before moving.

**`_<system>__sources.yml`**

- `version: 2`; source-level `description` (system, load mechanism, refresh = static/ongoing).
- One entry per table, in alphabetical order. Table `description` includes:
  1. Purpose (what the business entity/event is)
  2. **Grain** — "One row per …" (or "No enforced grain: …" if profiling found none)
  3. Load + test scope — "Static load from `raw_data/<file>.csv`; contract tests cover the full table."
  4. Known data-quality findings from profiling (counts), if any
- Table-level `data_tests:` with `elementary.schema_changes_from_baseline` (plus any composite-key test).
- `columns`: every column in ordinal order, each with `name`, `data_type`, `description`, and `data_tests` where applicable.

**`_<system>__docs.md`**

- One `{% docs %}` block for the source and one per table (`<system>__<table>`), referenced from the YAML with `{{ doc('…') }}`.
- Columns that mean the same thing across tables share **one** key (e.g. `deal_id`, `user_id` for `users.id` / `activity.assigned_to_user`). Check existing `_docs.md` files for a key before creating one.
- Table-specific columns: key `<table>__<column>`.
- Column docs state units/formats (timezone of timestamps, boolean meaning, JSON shape) and any raw quirks (e.g. `active` is the string `'Yes'`/`'No'`, not a boolean). Describe what the raw value **is**, not how staging will clean it.

### 7. Validate

1. `dbt parse` — must be clean.
2. `dbt test --select "source:<source_name>"` (or `source:<source_name>.<table>` for a subset). The Elementary test needs Elementary's tables to exist; if `<target schema>_elementary` is missing, run `dbt run --select elementary` first.
3. Confirm with `dbt ls --select "source:<source_name>" --resource-type source` that every intended table is listed.
4. Report: tables onboarded, column count per table (must equal warehouse count), tests passed / warned / failed with counts, and every data-quality finding.

## Done when

- [ ] Every target table's YAML column list equals the warehouse columns (names, order, `data_type` without size), enforced by `elementary.schema_changes_from_baseline` passing on every table
- [ ] Tests use `data_tests:` with inputs under `arguments:`; `dbt parse` shows no test-syntax deprecation warnings
- [ ] No raw file, loader, or warehouse table modified
- [ ] Each table has a grain statement, test-scope statement, and a key + value contract backed by profiling evidence
- [ ] Shared columns use shared `{{ doc() }}` keys; doc blocks live in `_<system>__docs.md`
- [ ] Only one definition per source/table in the project; existing `source()` refs still resolve
- [ ] `dbt parse` clean; source tests run and results (including failures) reported to the user
- [ ] Optional packages only added with the user's approval

## Afterwards

- Commit only when asked, following [.claude/rules/commit-dbt-changes.md](../../rules/commit-dbt-changes.md) — source YAML + `_docs.md` go in the **Sources** commit.
