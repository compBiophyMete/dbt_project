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

## Challenge the request first

Follow [.claude/rules/challenge-modeling-requests.md](../../rules/challenge-modeling-requests.md): check the request against best practice, prove a conflict with profiling numbers, propose the alternative, and let the user decide. Warning signs when onboarding a source:

| Warning sign | Why it's wrong | Best-practice alternative |
|---|---|---|
| **Declaring only some columns**, or types from memory | the schema contract can't catch added, removed or retyped columns | declare every column with its warehouse `data_type` |
| **Transforming or filtering in the source definition** | sources describe the raw table as it is | clean in staging |
| **A 30-day test window on a static load** | it selects nothing, so every test passes without checking anything | full-table scope for static loads |

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

- Tables loaded by `raw_data/load_data.sh` from CSV are a **static, one-time load** → test the **full table**, no `where` filter. They still get a **freshness check** on a timestamp column (or a commented one waiting for `_loaded_at`), so the project is ready for a live feed; on the static data it reports error, as expected. See step 6.
- If the user says a table is loaded on an ongoing basis, use the 30-day `where` window on its load/change timestamp, and ask whether it loads daily or hourly to pick the freshness thresholds.
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

**When the data already fails a contract test** (duplicate PKs, orphan FKs, unexpected values): keep the test, report the finding to the user with counts (in chat, and in an `analyses/` file via the `write-eda-analysis` skill), and ask whether to keep it at `error` (build fails until fixed upstream) or `severity: warn`. Either way, don't document it in the source: no table-description section, no test description or comment (see the standard table-description pattern in step 6). The staging model that handles the table explains it in its Edge cases. Never weaken a test silently.

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
    description: "{{ doc('activity_type') }}"   # column descriptions are always doc blocks
    data_tests:
      - not_null
      - accepted_values:
          arguments:
            values: ["call", "meeting", "follow_up"]   # illustrative — use the profiled values
      - relationships:
          arguments:
            to: source('pipedrive', 'activity_types')
            field: type
          config:
            severity: warn   # explained in the staging model's Edge cases, not in the source
```

### 6. Write the files

Location follows the rule's example structure, grouped by source system:

```
models/staging/<system>/
  _<system>__sources.yml   # source definition (all tables of this source)
  _<system>__docs.md       # doc blocks for the columns only
```

For this project `<system>` is `pipedrive`, and the source is named after the system too: `pipedrive` (database `{{ target.database }}` so CI can build in a per-PR clone database, schema `public`), referenced as `source('pipedrive', ...)`. The source name must match its staging folder; dbt-project-evaluator checks this in CI. If a source file already exists elsewhere (e.g. `models/sources.yml`), propose moving it with `git mv` into the conventional location and merging, rather than leaving two definitions. Ask before moving.

**`_<system>__sources.yml`**

Reference: `models/staging/pipedrive/_pipedrive__sources.yml`. Copy its structure exactly.

- `version: 2`, then one source with `name`, `database`, `schema` and an inline `description` (`>` block) of two sections, separated by two blank lines:
  1. **Load mechanism** (no heading): the system, how the tables are loaded (`raw_data/load_data.sh`, created by `init.sql`), whether anything reloads them, and so the test scope (full table for a static load).
  2. **`**Freshness assumption**`**: that no freshness is expected while the load is static but the project is ready for a live feed (`dbt source freshness`); the schedule-based thresholds (daily → warn 1 day / error 2 days, hourly → warn 1 hour / error 2 hours); the **assumed schedule** (daily today); which tables have an active check and on which column; which wait for `_loaded_at`; and that active checks report error on the static data, as expected. Update this section whenever a table's check changes.
- One entry per table, in alphabetical order, with its keys in this order: `name`, `description`, `config`, `data_tests` (table level), `columns`. Every table has a `config:` that starts with `tags: ["pipedrive"]` (the project tag, rule "Project tag"), followed by the freshness settings, or their commented `# TODO` lines.
- Table-level `data_tests:`: `elementary.schema_changes_from_baseline` first, then a composite-key test with the comment `# the grain: (…)` if the grain spans several columns, then any cross-column test. A short inline comment may explain **what a test checks** (e.g. `# each type must sit next to its name`), never that it fails on purpose.

**Standard table-description pattern.** A source table description says only what the table is and how it's loaded: **no data-quality findings, no evidence queries, no links to `analyses/`**. Findings belong in the staging model that handles them (its **Edge cases**) and in `analyses/`. Written for technical and non-technical readers alike. Sections in this order, separated by **two blank lines** (inside a folded `>` block, one blank line doesn't start a new paragraph in dbt docs):

1. **Purpose** (no heading): one sentence saying what the business entity or event is. For a table that stands in for a missing one, say so (e.g. `deal_changes`: "The source has no deals table, so …").
2. **`**Grain**`**: "one row per … (`col`, `col`)", then either "`init.sql` declares `<col>` as the key" or "`init.sql` declares no key; a test checks that the … is unique". Name an alternate unique column and what references it ("`type` is also unique, and it is the column that `activity.type` points to"). No explanation of why another key fails: that is a finding.
3. **`**Load / test scope**`**: "static load from `raw_data/<file>.csv`. Contract tests cover the full table." (or the 30-day window on `<timestamp_col>` for an ongoing load).
4. **`**Freshness**`**: every table gets one of two wordings:
   - **Table with a load or change timestamp** (active check; a planned date such as `activity.due_to` doesn't count): "none expected today, because the data is a static load. For a live feed the check is ready on `<col>`: warning when the latest <col meaning> is more than 1 day old, error after 2 days." Then one sentence on what the column measures, and if it isn't a load timestamp, the trade-off and "switch to one (e.g. `_loaded_at`) once the loader adds it". End with "On the static data the check reports error, as expected." Add the `config:` block below the description.
   - **Table without a load timestamp**: "none today. The table has no load timestamp, and the data is a static load. Once the loader adds `_loaded_at`, a freshness check on it is added with thresholds that follow the load schedule: daily load → warning after 1 day, error after 2 days; hourly load → warning after 1 hour, error after 2 hours." Under `config:`, after the tag, add the freshness lines commented out below a `# TODO`. Never point `loaded_at_field` at a column that doesn't exist yet.

Freshness config lives under the table's `config:` (top-level `loaded_at_field` / `freshness` is deprecated in dbt 1.10). **Thresholds follow the load schedule**: daily → `warn_after: {count: 1, period: day}`, `error_after: {count: 2, period: day}`; hourly → `{count: 1, period: hour}` / `{count: 2, period: hour}`.

Nothing else in a table description: no counts, no "Data quality" or topic sections, no Evidence line. (Shared column doc blocks are the exception: a short join warning such as "Not unique … never join on it" stays, since staging reuses the block.) A test that fails on purpose is not explained in the source and gets no test `description` or comment; the staging model's Edge cases explain it.

Table with a load or change timestamp:

```yaml
      - name: deal_changes
        description: >
          Change log of deal fields: each row records that a deal field (`changed_field_key`) was set to
          `new_value` at `change_time`. The source has no deals table, so deal creation (`add_time`), stage
          moves (`stage_id`), owner changes (`user_id`) and lost reasons (`lost_reason`) all come from this
          table.


          **Grain**: one row per deal, change time and changed field (`deal_id`, `change_time`,
          `changed_field_key`). `init.sql` declares no key; a test checks that the combination is unique.


          **Load / test scope**: static load from `raw_data/deal_changes.csv`. Contract tests cover the full
          table.


          **Freshness**: none expected today, because the data is a static load. For a live feed the
          check is ready on `change_time`: warning when the latest change is more than 1 day old, error
          after 2 days. `change_time` is when a deal field changed, so it moves forward whenever deals
          are worked. On the static data the check reports error, as expected.
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
          - dbt_utils.unique_combination_of_columns:
              arguments:
                combination_of_columns: ["deal_id", "change_time", "changed_field_key"]
```

Table without a load timestamp:

```yaml
      - name: stages
        description: >
          Lookup of the sales pipeline stages, in funnel order.


          **Grain**: one row per pipeline stage (`stage_id`). `init.sql` declares `stage_id` as the key.


          **Load / test scope**: static load from `raw_data/stages.csv`. Contract tests cover the full
          table.


          **Freshness**: none today. The table has no load timestamp, and the data is a static load. Once
          the loader adds `_loaded_at`, a freshness check on it is added with thresholds that follow the
          load schedule: daily load → warning after 1 day, error after 2 days; hourly load → warning
          after 1 hour, error after 2 hours.
        config:
          tags: ["pipedrive"]
          # TODO: once `_loaded_at` exists (declare the column too), uncomment and pick the load schedule:
          # loaded_at_field: _loaded_at
          # freshness:
          #   warn_after: {count: 1, period: day}    # hourly load: {count: 1, period: hour}
          #   error_after: {count: 2, period: day}   # hourly load: {count: 2, period: hour}
        data_tests:
          - elementary.schema_changes_from_baseline:
              arguments:
                fail_on_added: true
                enforce_types: true
```

- `columns`: every column in ordinal order, each with `name`, `data_type`, `description: "{{ doc('<key>') }}"`, and `data_tests` where applicable. Every column description is a doc reference; no inline column text.

**`_<system>__docs.md`**

- Column doc blocks only, one per column key, referenced from the YAML with `{{ doc('…') }}`. No doc blocks for the source or its tables; those descriptions stay inline in the YAML.
- Columns that mean the same thing across tables share **one** key (e.g. `deal_id`, `user_id` for `users.id` / `activity.assigned_to_user`). Check existing `_docs.md` files for a key before creating one.
- Table-specific columns: key `<table>__<column>`.
- Column docs state units/formats (timezone of timestamps, boolean meaning, JSON shape) and any raw quirks (e.g. `active` is the string `'Yes'`/`'No'`, not a boolean). Describe what the raw value **is**, not how staging will clean it.

### 7. Validate

1. `dbt parse` — must be clean.
2. `dbt test --select "source:<source_name>"` (or `source:<source_name>.<table>` for a subset). The Elementary test needs Elementary's tables to exist; if `<target schema>_elementary` is missing, run `dbt run --select elementary` first.
3. Confirm with `dbt ls --select "source:<source_name>" --resource-type source` that every intended table is listed.
4. Report: tables onboarded, column count per table (must equal warehouse count), tests passed / warned / failed with counts, and every data-quality finding.

## Done when

- [ ] Carries the project tag (`pipedrive`) in `dbt_project.yml` and in its own YAML (`config: tags: ["pipedrive"]`, first in the list when other tags exist; rule: "Project tag")
- [ ] Every target table's YAML column list equals the warehouse columns (names, order, `data_type` without size), enforced by `elementary.schema_changes_from_baseline` passing on every table
- [ ] Tests use `data_tests:` with inputs under `arguments:`; `dbt parse` shows no test-syntax deprecation warnings
- [ ] No raw file, loader, or warehouse table modified
- [ ] The source description has the load mechanism and a **Freshness assumption** section that lists the active and pending checks
- [ ] Each table description follows the standard pattern (Purpose, Grain, Load / test scope, Freshness), separated by two blank lines, with no data-quality findings, evidence queries or counts
- [ ] Every table with a load or change timestamp has a `config:` freshness check with schedule-based thresholds; every other table has the commented `# TODO` freshness lines for `_loaded_at` under its `config:`
- [ ] No test description or comment explains a known failure in the source
- [ ] Each table has a key + value contract backed by profiling evidence
- [ ] Source and table descriptions are inline in the YAML; every column description is a `{{ doc() }}` reference to a block in `_<system>__docs.md`, with shared columns using shared keys
- [ ] Only one definition per source/table in the project; existing `source()` refs still resolve
- [ ] `dbt parse` clean; source tests run and results (including failures) reported to the user
- [ ] Optional packages only added with the user's approval

## Afterwards

- Commit only when asked, following [.claude/rules/commit-dbt-changes.md](../../rules/commit-dbt-changes.md) — source YAML + `_docs.md` go in the **Sources** commit.
