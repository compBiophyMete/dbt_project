---
name: build-staging-model
description: Build dbt staging models (stg_<folder>__<entity>s in schema stg_<folder>, named after the source folder, e.g. stg_pipedrive__activities) on top of an onboarded source — one model per source table with light transformations only: renaming to standard column names, casting, null handling, deduplication, and generic typed columns. Documented and tested per .claude/rules/dbt-documentation-testing.md. Use when asked to build, add, write, or refactor a staging model / stg_ model / the staging layer, or to "clean up" a raw source table for downstream use.
argument-hint: "[source tables — default: every table of the source without a staging model]"
---

# Build staging models

Goal: one clean, consistently named, correctly typed model per source table. Every downstream model reads it instead of the raw table. Staging (including any `base_` model, see step 4) is the **only** layer that reads `{{ source() }}`, and it changes how the data *looks*, never what it *means*.

Standards for YAML structure, descriptions, doc blocks and tests live in [.claude/rules/dbt-documentation-testing.md](../../rules/dbt-documentation-testing.md). Read it first. This skill is the procedure that applies it to the staging layer. If the two ever disagree, the rule wins.

## What belongs in staging (and what doesn't)

| ✅ Staging | ❌ Not staging (→ intermediate / marts) |
|---|---|
| Renaming columns to the project's naming conventions | Joins between source tables |
| Casting to the right type (text → integer/boolean/timestamp) | Aggregations (`group by`, counts, sums) |
| Standardizing values: `trim`, `lower`, `'Yes'/'No'` → boolean, `''` → `null` | Pivoting rows into columns (e.g. one row per deal from a change log) |
| Null handling where the meaning is certain | Business rules (funnel step definitions, KPIs) |
| Deduplicating rows that are true duplicates | Filtering out rows for business reasons |
| Simple derived columns from **one** row (typed columns by value shape, `is_` flags, date parts) | Window logic across entities (e.g. "first stage reached") |

Rules of thumb:
- **One staging model per source table, one-to-one.** Lookup tables (stages, types, users) get a staging model too, so nothing downstream reads a source directly.
- **Grain is preserved.** One output row per source row, unless the model deduplicates. In that case the description says what was removed and why.
- **Never invent meaning.** If a fix needs a business decision (which of two conflicting rows wins, what a null means, which timezone a timestamp is in), ask the user. Don't guess.
- **No `*` anywhere.** Use `dbt_utils.star()` to read the source and list every column explicitly after that (see non-negotiable 2).

## Non-negotiables

1. **Read only from `{{ source() }}`**, exactly one source table per model (a `base_` sub-model is the only exception; see step 4).
2. **Never write `*`.** Not in any CTE, and not in the final select.
   - The `source` CTE reads the source with `{{ dbt_utils.star(from=source('<source>', '<table>')) }}`. At compile time it expands to the table's actual column list (each column quoted), so the compiled SQL names every column, and a dropped or renamed source column fails at build instead of flowing on silently. Use its `except=[...]` argument to leave out a column on purpose.
   - Every later CTE lists its columns by name (`dbt_utils.star()` can't read a CTE, only a relation).
   - The **final select always names the exact output columns**, in output order, so a reader sees the model's shape without opening any CTE.
3. **Keep every source column by default.** Dropping a column needs a reason, written in the model description (e.g. "`email` dropped: PII, not used downstream"). Ask the user before dropping.
4. **Data-quality issues are resolved or flagged, never hidden.** If a dedup or a filter drops rows, the description says how many and why. An issue that can't be resolved in staging (e.g. orphan foreign keys) stays in the data and is documented.
5. **Read-only on the database** during profiling: only `select` queries via `dbt show` (MCP `mcp__dbt__show`).

## Challenge the request first

Follow [.claude/rules/challenge-modeling-requests.md](../../rules/challenge-modeling-requests.md): check the request against best practice, prove a conflict with profiling numbers, propose the alternative, and let the user decide. Warning signs at the staging layer:

| Warning sign | Why it's wrong | Best-practice alternative |
|---|---|---|
| **A business filter in staging** (only `stage_id` changes, only done activities) | staging keeps every source row; a filter here hides rows other models need | filter in the import CTE of the `int_` model that needs the subset |
| **A join in staging** | staging is one-to-one with its source table | join in intermediate |
| **Business meaning given here** (`new_value` named `stage_id`, a status derived from flags) | staging changes how data *looks*, not what it *means* | typed, generic columns here; meaning in intermediate |
| **Dropping or "fixing" bad rows silently** | data-quality issues must stay visible | keep the row, null the bad value, and let a test report it |
| **A run-timestamp audit column in a view** (`cast('{{ run_started_at }}' …) as dwh_date`) | `run_started_at` is the run's start time ([dbt docs](https://docs.getdbt.com/reference/dbt-jinja-functions/run_started_at)), written into the view's SQL when it's built: the same value on every row, changing only on rebuild, saying nothing about the data. Not among the staging transformations in [dbt's staging guide](https://docs.getdbt.com/best-practices/how-we-structure/2-staging) (renaming, type casting, basic computations, categorizing), and staging views already give "the freshest data possible" | leave it out; source freshness covers arrival. A load timestamp belongs in an incremental model, where it records when each row was written (`dwh_date` on every incremental `int_` model) |

## Procedure

### 1. Scope and context

- Find the source: `models/staging/<system>/_<system>__sources.yml`. Read each target table's description and its **Known data-quality findings**. They are the to-do list for staging.
- **Location (mandatory):** every staging model lives under `models/staging/<system>/`, next to that system's `_<system>__sources.yml`. If `models/staging/` or `models/staging/<system>/` doesn't exist, create it. Never put a `stg_` model anywhere else.
- List existing staging models (`models/staging/<system>/stg_*.sql`) and skip or extend those instead of duplicating them.
- Check that `dbt_project.yml` has the `staging:` block (view, docs color) and a `<folder>: +schema: stg_<folder>` block for this source folder, and add what's missing. Check that `macros/generate_schema_name.sql` exists, so the schema is used as-is (see step 6).

### 2. Profile what the transformations need

The source onboarding already profiled keys and values. Profile only what staging decisions need, for example:

- String hygiene: values with leading/trailing spaces, empty strings, inconsistent case (`count(*) filter (where col <> trim(col))`, `filter (where col = '')`).
- Castability of text columns you plan to cast (e.g. `new_value ~ '^\d+$'` per key), so a cast can't fail at build time.
- Duplicates: exact duplicate rows vs rows sharing a key with different content.
- Every value of the columns you plan to map (e.g. `'Yes'`/`'No'`), so the mapping covers all of them.

### 3. Decide the column contract

Write down, per column, the **source name → staging name**, the **type**, and the **transformation**. Apply these naming conventions (dbt style guide):

| Kind | Convention | Example |
|---|---|---|
| All names | `snake_case`, no abbreviations unless universal, no reserved/ambiguous words (`type`, `name`, `id` alone) | `type` → `activity_type`, `name` → `user_name` |
| Primary key | `<entity>_id` | `users.id` → `user_id`, `activity_types.id` → `activity_type_id` |
| Foreign key | bare `<entity>_id` **only** when the column simply is that entity. When it plays a **role** (assignee, owner, creator, new value), prefix the role: `<role>_<entity>_id` | `activity.deal_id` → `deal_id`; `assigned_to_user` → `assigned_user_id`; the new owner in `deal_changes` → `owner_user_id` |
| Booleans | `is_` / `has_` prefix; name the entity when the flag could be read as another one's state after a join | `done` → `is_done`, `activity_types.active` → `is_activity_type_active` |
| Timestamps | `<event>_at` | `change_time` → `changed_at`, `due_to` → `due_at` |
| Dates | `<event>_date` | `created_date` |
| Same concept, different tables | **same name everywhere**, and a name always means the same thing: never reuse a bare name like `user_id` for a role | `deal_id`, `stage_id`; `user_id` only for the user entity itself |

Column order in the select: **keys** (PK, then FKs) → **strings** → **numerics** → **booleans** → **dates / timestamps**. The YAML and doc blocks follow the same order (rule: "Match model column order").

Transformations:
- **Casting**: use `::type` or `cast()` once, in the renaming CTE. Cast text IDs to `integer`. Map string booleans explicitly (`case when active = 'Yes' then true when active = 'No' then false end`). An unmapped value must stay `null` and be caught by a test, not become `false`.
- **Nulls**: `nullif(trim(col), '')` for text. Use `coalesce` only when a null has one certain meaning (e.g. a counter with no events is `0`). Never coalesce keys, foreign keys or timestamps to placeholder values (`-1`, `'unknown'`, `1900-01-01`).
- **Timestamps**: keep the source type. If the source has no timezone, don't convert. Document "timezone not recorded in the source", or ask the user which timezone to assume.
- **Polymorphic columns** (a value column whose meaning depends on a key column, like `deal_changes.new_value`): keep the row grain and the raw text column, and add **one typed column per value type**, with the key deciding which type a row is expected to have: e.g. `case when changed_field_key = 'add_time' and new_value ~ '<timestamp pattern>' then new_value::timestamp end as new_value_timestamp`, and `case when changed_field_key <> 'add_time' and new_value ~ '^\d{1,9}$' then new_value::integer end as new_value_integer`. A Postgres `case` returns one type, so never mix types in one column. Always check the format with a regex **before** casting (bounded digits so integers can't overflow; valid month/day/time ranges for timestamps): an unchecked cast errors and breaks the view, while a checked one turns bad data into null, which a `not_null` test (limited with `where` to that type's keys) reports. No columns named after a key's meaning (`stage_id`, `owner_user_id`, …) in staging: deciding what a key means is business logic. Those columns, their names and their relationship tests belong in intermediate (e.g. `int_deal_changes_filtered_to_stages` filters `changed_field_key = 'stage_id'` and renames `new_value_integer as stage_id`). Keep `accepted_values` on the key column at `warn`, so a new key is reported without blocking the build.

### 4. Deduplication

Handle duplicates in staging only when the rule is unambiguous:

- **Exact duplicate rows** (every column equal): remove them with `distinct` or `row_number()`, and document how many were removed.
- **Same key, different content** (e.g. one `activity_id` on two deals): this is a business question. Ask the user which rule applies (latest wins, keep both with a surrogate key, flag and exclude, …). Until they decide, keep all rows and do **not** test the key as unique at `error`.
- When dedup is needed, use a deterministic `row_number()` with a full tie-breaking `order by`, so reruns pick the same row. The `partition by` and `order by` **are** the dedup rule, so they come from the user's decision, never from a default.

The example below shows the **pattern only**, assuming the user chose "latest `due_at` wins". It is **not** this project's rule: for `activity`, the user decided to keep every row and only warn on `activity_id`. Don't copy it without a decision.

```sql
-- dedup rule (decided by the user): latest due_at wins per activity_id
deduplicated as (

    select
        activity_id,
        deal_id,
        assigned_user_id,
        activity_type,
        is_done,
        due_at,
        row_number() over (
            partition by activity_id
            order by due_at desc, deal_id   -- deterministic tie-breaker
        ) as row_num
    from renamed

)

select
    activity_id,
    deal_id,
    assigned_user_id,
    activity_type,
    is_done,
    due_at
from deduplicated
where row_num = 1
```

- A model that needs heavy pre-processing before renaming (e.g. unioning two source tables of the same entity) gets a `base_<folder>__<entity>s` model first, then the staging model reads it. Use this sparingly.

### 5. Write the SQL

**Naming convention (mandatory): driven by the folder the model lives in**. For a model in `models/staging/<folder>/`, where `<folder>` is the source system's folder:

- **Model name** = `stg_<folder>__<entity>s`: the folder name, a double underscore, then the source table's entity in the **plural** (a table name that is already plural stays as it is). This is [dbt's staging convention](https://docs.getdbt.com/best-practices/how-we-structure/2-staging): "`stg_[source]__[entity]s.sql` - the double underscore between source system and entity helps visually distinguish the separate parts", and "**Plural.**"
- **Schema** = `stg_<folder>`, set once for that folder in `dbt_project.yml` (`staging: <folder>: +schema: stg_<folder>`, step 6) and used as-is by `macros/generate_schema_name.sql`. So the relation is `stg_<folder>.stg_<folder>__<entity>s`.
- **Files**: `models/staging/<folder>/stg_<folder>__<entity>s.sql` and `.yml`.
- **Model-specific doc keys**: `stg_<folder>__<entity>s__<column>`.
- Never hard-code a source name in a new model's name or schema; take it from the folder. A new source system means a new folder, which brings its own prefix and schema, and keeps model names unique when two systems have a table with the same name (e.g. two `users`).

Example (this repo, `<folder>` = `pipedrive`): source table `activity` → model `stg_pipedrive__activities` in `models/staging/pipedrive/`, relation `stg_pipedrive.stg_pipedrive__activities`; `deal_changes` → `stg_pipedrive__deal_changes`.

Use the standard CTE pattern:

```sql
with

source as (

    select
        {{ dbt_utils.star(from=source('postgres_public', 'activity')) }}
    from {{ source('postgres_public', 'activity') }}

),

renamed as (

    select
        -- keys
        activity_id,
        deal_id,
        assigned_to_user                        as assigned_user_id,

        -- strings
        nullif(trim(type), '')                  as activity_type,

        -- booleans
        done                                    as is_done,

        -- timestamps
        due_to                                  as due_at

    from source

)

select
    activity_id,
    deal_id,
    assigned_user_id,
    activity_type,
    is_done,
    due_at
from renamed
```

- No `*` anywhere: `dbt_utils.star()` in the `source` CTE, explicit names in every other CTE, and the exact output columns in the final select.
- Lowercase SQL keywords, trailing commas, 4-space indents, one column per line, aliases with `as`.
- No hardcoded schema or table names; always `{{ source() }}`.
- Write `source('<source>', '<table>')` directly where it's used, in both `dbt_utils.star(from=...)` and `from`. Don't assign it to a Jinja variable (`{% set ... %}`): the SQL should read top to bottom without Jinja indirection.
- No `order by` in the final select.

### 6. Materialization

Staging models are **always views**, with no exceptions. They are thin, aren't queried by end users, and a view is always in sync with its source. This is set once at folder level in `dbt_project.yml` (the project default for other layers is `table`), together with the staging schema and docs color:

```yaml
models:
  enpal_assessment_project:
    staging:
      +materialized: view
      +docs:
        node_color: "#2E8B57"     # green: marks staging nodes in the dbt docs lineage graph
      # One block per source folder: schema stg_<folder>, models stg_<folder>__<entity>s.
      <folder>:                   # e.g. pipedrive
        +schema: stg_<folder>     # used as-is (macros/generate_schema_name.sql): stg_<folder>.stg_<folder>__<entity>s
```

Adding a new source folder means adding its `<folder>: +schema: stg_<folder>` block here.

- If the `staging:` block is missing, add it.
- Never override it: no `materialized=`, `schema=` or `docs` color in a staging model's `config()` or YAML.
- The schema name is used **as-is** because the project overrides dbt's `generate_schema_name` in `macros/generate_schema_name.sql`: this project's models get exactly their `+schema`, so staging views land in `stg_<folder>` (e.g. `stg_pipedrive`), kept apart from the intermediate and mart tables. (Package models such as Elementary keep dbt's default `<target schema>_` prefix.) If that macro is missing, dbt would build `<target schema>_stg_pipedrive` instead: stop and tell the user rather than accepting the wrong schema.
- The folder config only applies to models under `models/staging/`, which is another reason the location rule in step 1 is mandatory.

### 7. Write the YAML and docs

Follow the rule. In short:

**`stg_<folder>__<entity>s.yml`** — one file per model, same folder:
- `version: 2`, one `models:` entry.
- `description:` **inline** (`>` block, never `{{ doc() }}`), covering the rule's five points:
  1. **Purpose**: which source table it cleans, and what for.
  2. **Grain**: "One row per …". Say if dedup changed it.
  3. **Transformations** (this exact heading; never "Transformations and business logic", because staging has no business logic): renames, casts, value mappings (`'Yes'` → `true`, a null with one certain meaning → `false`), typed columns by value shape, and the dedup rule (or **Deduplication**: none, with why). These are the staging transformations of [dbt's staging guide](https://docs.getdbt.com/best-practices/how-we-structure/2-staging): renaming, type casting, basic computations, categorizing. No section may be labelled "Business rule": if a description needs one, the logic belongs in an `int_` model, and staging only points to it (e.g. "what two creations of one deal ID mean is decided in `int_deals`").
  4. **Edge cases**: about **this model only**: nulls, rows removed (which and why), data-quality findings carried over from the source and how the model treats them, each with its `analyses/` file. Don't describe downstream models, their decisions, or the impact on them (e.g. "funnel steps will be empty", "downstream must decide…").
  5. **Refresh**: e.g. "Rebuilt on every `dbt run`. The source is a static, one-time load, so there is no freshness check."
- No counts, data date ranges or "today" claims anywhere in the YAML or doc blocks: describe each finding in words and point to its `analyses/` file (rule: "No counts or profiling results in documentation").
- `columns:` every output column, in select order, each with `description: "{{ doc('<key>') }}"`.

**Doc blocks** in `models/staging/<system>/_<system>__docs.md`, the closest `_docs.md`:
- **Reuse the source's key whenever the meaning is unchanged, even if the column was renamed.** A doc key is not tied to the column name: `assigned_to_user` → `assigned_user_id` reuses `{{ doc('activity__assigned_to_user') }}`, `due_to` → `due_at` reuses `{{ doc('activity__due_to') }}`. A rename, `trim`, or `nullif(…, '')` that changes no meaning is not a reason for a new docstring. Duplicate docstrings drift apart.
- Create a **new** key only when the transformation changes what the values mean or how they are encoded: a cast, a value mapping (`'Yes'` → `true`), a `coalesce` that gives null a meaning, a typed column. Name it `stg_<folder>__<entity>s__<column>` (e.g. `stg_pipedrive__activities__is_done` for `coalesce(done, false)`), or a shared key if several models use the same concept.
- A new docstring states the transformation and its meaning (e.g. "`true` when the raw `active` was `'Yes'`", "`false` also covers unknown").

### 8. Tests

Per the rule's "When to Test": test what staging **changed or guarantees**, and don't repeat source tests on untouched columns.

| Column | Test |
|---|---|
| Primary key / grain | `unique` + `not_null` (or `dbt_utils.unique_combination_of_columns`). **Always**, because staging owns the grain downstream relies on. If a known issue stops the key from being unique, use `severity: warn` and explain it in the description |
| Cast or mapped columns | `not_null` where the source was non-null (proves the cast/mapping lost nothing), `accepted_values` on mapped enumerations |
| Typed columns (`new_value_integer`, …) | `not_null` with `config: where:` limited to the keys expected to have that type, so a value that failed its format check is reported as bad data. Key-specific tests (`relationships` to `stg_pipedrive__stages` / `stg_pipedrive__users`, `accepted_values` on lost-reason IDs) go on the intermediate models that give each key its meaning |
| Renamed foreign keys | `relationships` to the parent **staging** model (`ref('stg_…')`) only if the source didn't already test it, or the transformation could break it |
| Untouched columns | none: the source tests already cover them |

Use `data_tests:`, with inputs under `arguments:` and `severity`/`where` under `config:`. Staging models don't need `contract: enforced` (rule: "Model Contracts"). Ask the user whether a model is critical enough for a freshness check. For a static load the answer is normally no.

### 9. Validate

1. `dbt parse` must be clean, with no test-syntax deprecation warnings.
2. Build and test as **two separate commands**, never `dbt build`: first `dbt run --select stg_<folder>__<entity>s`, then `dbt test --select stg_<folder>__<entity>s`. `dbt build` skips every downstream model when a test fails; run-then-test builds all selected models first and then reports every failing test, so a failing test is a finding to report, not a reason to leave models unbuilt.
3. **Reconcile row counts** with `dbt show`: `count(*)` of the model vs the source. They must be equal unless the model deduplicates or filters, and then the difference must equal the documented count.
4. Spot-check casts with `dbt show`: no unexpected nulls in cast columns (`count(*) filter (where new_col is null and old_col is not null)` = 0).
5. Report to the user: models built, row counts (source → staging), tests passed / warned / failed, and every decision made or still open (dedup rules, dropped columns, timezone assumptions).

## Done when

- [ ] Carries the project tag (`pipedrive`) in `dbt_project.yml` and in its own YAML (`config: tags: ["pipedrive"]`, first in the list when other tags exist; rule: "Project tag")
- [ ] One `stg_<folder>__<entity>s` model per target source table, named after its folder (plural entity; relation `stg_<folder>.stg_<folder>__<entity>s`), reading only `{{ source() }}`, with no `*` anywhere: `dbt_utils.star()` in the `source` CTE and the exact column names in every later CTE and the final select
- [ ] Column names follow the naming conventions; the same concept has the same name across models
- [ ] Every cast and mapping is checked against the data (no rows lost to null); the grain is preserved, or every dedup/filter is documented (in words, counts in `analyses/`)
- [ ] No counts or profiling results in the description, doc blocks or test comments; a test that fails on purpose is explained in the description's Edge cases, not on the test
- [ ] No business logic, joins or aggregations; decisions that need business judgment were asked, not guessed
- [ ] The description's third section is headed **Transformations**, and no section is labelled "Business rule"
- [ ] One YAML per model; the inline description covers purpose, grain, logic, edge cases, refresh; every column is a `{{ doc() }}` reference, in select order
- [ ] PK/grain tested; transformed columns tested; untouched columns not re-tested; `data_tests:` with `arguments:`
- [ ] Models live under `models/staging/<folder>/` (folder created if missing) and build as views in the `stg_<folder>` schema with the staging docs color, all via the `staging:` block (and its `<folder>:` sub-block) in `dbt_project.yml`, with no per-model override
- [ ] `dbt run` then `dbt test` on the models (not `dbt build`): models built, tests pass (or warnings/failures reported with counts), and row counts reconcile with the source

## Afterwards

- Commit only when asked, following [.claude/rules/commit-dbt-changes.md](../../rules/commit-dbt-changes.md). Staging models, their YAML and their doc blocks go in the **Staging** commit, after any Sources commit they depend on. If the `staging:` block had to be added to `dbt_project.yml`, that goes in its own commit before them.
