---
name: build-intermediate-model
description: Build dbt intermediate models (int_<entity>s_<verb>s, in business-area folders such as models/intermediate/deals/) on top of the staging layer — joins, enrichment of one entity with attributes from others, business logic, re-graining (pivoting a change log into one row per entity, rolling child rows up to a parent), and window logic (first/last, durations, stage reached). Documented and tested per .claude/rules/dbt-documentation-testing.md. Use when asked to build, add, write, or refactor an intermediate model / int_ model / the intermediate layer, or to prepare reusable building blocks for marts.
argument-hint: "[entity or business question — e.g. 'deal stage history', 'deals with first activity']"
---

# Build intermediate models

Goal: reusable building blocks that turn clean staging data into **business entities and business facts**. Staging changes how the data *looks*; intermediate decides what it *means*; marts shape it for a consumer. Every business rule is written **once**, here, and every mart that needs it `ref()`s the intermediate model instead of repeating the logic.

Standards for YAML structure, descriptions, doc blocks and tests live in [.claude/rules/dbt-documentation-testing.md](../../rules/dbt-documentation-testing.md). Read it first. This skill is the procedure that applies it to the intermediate layer. If the two ever disagree, the rule wins.

## What belongs in intermediate (and what doesn't)

| ✅ Intermediate | ❌ Not intermediate |
|---|---|
| Joins between staging models (and other intermediate models) | Reading `{{ source() }}` (→ staging only) |
| Enrichment: adding attributes of related entities (deal + owner name + stage name) | Renaming, casting, trimming raw columns (→ staging) |
| Business logic: giving meaning to codes and keys, classifications, flags (`is_won`, `funnel_step`) | Final, consumer-facing shapes: one row per month per KPI, dashboard-ready labels (→ marts) |
| Re-graining: pivoting a change log into one row per entity, rolling child rows up to a parent (activities per deal) | Report-level aggregations: counts per month, conversion rates for a dashboard (→ marts) |
| Window logic across rows: first/last event, time between events, "stage reached", ordering of changes | Presentation: sorting, formatting, display names for a BI tool (→ marts) |
| Filtering to a meaningful subset (only `stage_id` changes) | Exposing to end users or dashboards directly (→ marts, with a contract) |
| Unioning models of the same entity from different systems | |

**Aggregations: the line between intermediate and marts.** Aggregating *to an entity grain* is intermediate (activities rolled up to one row per deal: `first_activity_at`, `activity_count`). Aggregating *to a reporting grain* is a mart (deals counted per month per funnel step). If the aggregated table only makes sense for one dashboard, it's a mart.

Rules of thumb:
- **One clear purpose per model.** A model does one kind of thing (pivots, joins, *or* applies a rule set). If the description needs "and then … and then …", split it into a chain of intermediate models.
- **Intermediate models are internal.** They are not queried by end users or dashboards; marts are the only public layer.
- **Never invent business meaning.** Funnel definitions, which of two conflicting rows wins, how a reopened deal is counted: ask the user, then write the decision into the description.

## Non-negotiables

1. **Read only from `ref()` to `stg_` and `int_` models.** Never `{{ source() }}`, never a mart (`fct_` / `dim_` / `rep_`). Dependencies only flow downstream.
2. **Never write `*`.** Every CTE and the final select list their columns by name, so the model's shape is visible without opening any upstream model.
3. **State the grain before writing SQL, and test it.** Every model has one documented grain ("one row per deal", "one row per deal and stage") and a test that enforces it (see step 7).
4. **No surrogate keys.** When the grain is more than one column, keep the natural columns, enforce them with `dbt_utils.unique_combination_of_columns`, and document the combination as the join key. A hashed key doesn't help a join; it only hides which columns define the row.
5. **Every join is checked for fan-out and for dropped rows.** Know the grain of both sides, and reconcile row counts after the join (step 8). A join that silently multiplies or drops rows is the most common bug in this layer.
6. **Data-quality issues are carried forward visibly, never hidden.** If a filter or an inner join drops rows, the description says how many and why. Known issues inherited from staging (e.g. activities whose deal is not in `deal_changes`) are documented, not papered over.
7. **Read-only on the database** during profiling: only `select` queries via `dbt show` (MCP `mcp__dbt__show`).

## Challenge the request first

Follow [.claude/rules/challenge-modeling-requests.md](../../rules/challenge-modeling-requests.md): check the request against best practice, prove a conflict with profiling numbers, propose the alternative, and let the user decide. Warning signs at the intermediate layer:

| Warning sign | Why it's wrong | Best-practice alternative |
|---|---|---|
| **A filter or status built on a column that doesn't describe the row** (e.g. the activity *type's* `active` flag used as the activity's status) | the value is the same on every row of a group, so it filters whole groups (it would have removed every Sales Call) | filter on the row's own columns (`is_done`); keep the group attribute as information |
| **`current_date` / `now()` in a business rule** | the result changes from day to day with no change in the data; untestable | compare with `run_started_at`, or keep the status out of the model and compute it where "today" matters |
| **Labels stored in an incremental / append model** (`stage_name`, `lost_reason_name`) | rows are never rewritten, so a rename leaves stale labels and a late lookup leaves nulls forever | store only IDs; join labels in the mart at build time |
| **Joining two event streams row to row** | fan-out or empty matches (see the mart skill) | an as-of rule with a ranked join (`row_number()`), or a `union all` at one grain |
| **A pass-through model** that only selects from one upstream model | adds a table, YAML and tests without meaning | read the upstream model directly; add the `int_` model when a rule appears |
| **A per-entity flag checked against an event table** | "exists" quietly becomes "had this event" | check against the entity list (`int_deals`) |
| **A business meaning nobody confirmed** (which loss wins, what counts as entered) | invented meaning spreads to every mart | ask the user; record the decision in the task file and the description |

## Procedure

### 1. Scope and context

- Clarify the **business question** the model serves, and which marts will use it. If none will, ask whether the model is needed.
- Read the upstream staging/intermediate YAMLs: their **grain**, **join keys**, and **edge cases** are the inputs to every decision below. In this project, for example:
  - `stg_pipedrive__activities` has grain (`activity_id`, `deal_id`): join on both, never on `activity_id` alone.
  - `stg_pipedrive__deal_changes` has grain (`deal_id`, `changed_at`, `changed_field_key`), and `new_value` is polymorphic: its meaning depends on `changed_field_key`.
  - `stg_pipedrive__users` must be joined on `user_id` only (names and emails are not unique).
- List existing `int_` models and extend or reuse them instead of duplicating logic.
- **Location (mandatory):** `models/intermediate/<area>/`, one folder per **business area**, not per source system ([dbt's intermediate guide](https://docs.getdbt.com/best-practices/how-we-structure/3-intermediate): "✅ **Subdirectories based on business groupings** … not by their source system, but by their area of business concern"). This repo: `deals/`, `funnel/`, `activities/`, `users/`, `fields/`. Put a new model in the area of the entity it is about; create a new area folder only for a new business concern. The folder holds the models, their YAMLs and the folder's doc-block file `_intermediate_<area>__docs.md`. `dbt_project.yml`'s `intermediate:` settings apply to every area folder, so a new folder needs no config.
- Check that `dbt_project.yml` has an `intermediate:` block (step 6). If it's missing, propose it and ask before adding it.

### 2. Profile what the logic needs

Profile with `dbt show` before deciding a rule, for example:

- **Grain candidates**: `count(*)` vs `count(distinct <key columns>)` on the output you plan to build.
- **Join coverage**: how many rows on each side have no match (`left join … where right.key is null`). This decides `left` vs `inner` join and is reported as a count.
- **Fan-out**: the max number of matches per key on the right side. If it's > 1 where you expected one, the join key or the grain is wrong.
- **Edge cases of the business rule**: deals skipping stages, revisiting a stage, changing stage several times on one day, having two creation times, events before the creation time, ties on timestamps.

### 3. Decide the model's contract

Write down before coding:

- **Grain** and the columns that define it.
- **Inputs** (`ref()`s) and, for each join: the join type, the join key, the expected cardinality (1:1, n:1), and what happens to unmatched rows.
- **Output columns**, with naming per the staging skill's conventions (`<entity>_id`, `<role>_<entity>_id`, `is_`/`has_`, `<event>_at`, `<event>_date`). New columns created here follow the same rules, for example:
  - polymorphic values get their business name here: `new_value_integer as stage_id` for `stage_id` changes, `new_value_integer as owner_user_id` for `user_id` changes;
  - derived timestamps name the event: `first_activity_at`, `reached_stage_at`, `lost_at`;
  - counts are `<thing>_count`, durations carry their unit: `days_to_close`.
- **Business rules** in plain words, each confirmed with the user (e.g. "a deal counts as having reached a stage the first time it enters it; later re-entries are ignored").

Column order: **keys** (grain columns, then FKs) → **strings** → **numerics** → **booleans** → **dates / timestamps**. The YAML and doc blocks follow the same order.

### 4. Joins and enrichment

- **Join to the grain, never below it.** Joining a parent (deal) to children (activities) fans out to the child grain. If the output should stay at the parent grain, **aggregate the children first, in their own CTE or model**, then join.
- **Default to `left join`** from the entity the model is about, so it keeps all its rows. Use `inner join` only when dropping unmatched rows is the business rule, and document which rows it drops (in words; the count goes in an `analyses/` file).
- **Join on the full documented join key**: (`activity_id`, `deal_id`) for activities, `user_id` for users. Never on names, emails or display labels.
- **Lookups** (stages, activity types, field options) are joined to add labels and attributes; they must never change the row count. The `relationships` tests upstream guarantee a match, and step 8 reconciles the counts.
- **Unnest JSON in its own model or CTE** (e.g. `stg_pipedrive__fields.field_value_options` → one row per field and option) before joining it, so the lookup has a clean grain of its own.

### 5. Business logic and window functions

- **Write each rule once, with a name.** A rule that more than one mart needs (funnel step mapping, "is won") lives in one intermediate model; marts `ref()` it.
- **Deterministic window functions.** Every `row_number()` / `first_value()` / `lag()` has a complete `order by` with a tie-breaker, so reruns produce the same result (`order by changed_at, new_value_integer`). The `partition by` and `order by` are the business rule: write them from the user's decision, not a default.
- **Prefer `min()`/`max()` with `group by`** over `row_number() … where rn = 1` when only one value per group is needed; it states the intent and can't pick an arbitrary row.
- **"Latest / first matching row per group": a ranked join, never a lateral join.** When you need the whole row (or a value from another table) as of a point, e.g. the stage a deal was in when it was lost, write a regular join plus `row_number() over (partition by … order by …)` in its own CTE, named for what it ranks (`stage_rank`), and keep `rank = 1` in the next CTE. Don't write `left join lateral (… order by … limit 1)`: the ranked join is the familiar pattern, readable without knowing lateral semantics. Keep a `left join` when unmatched rows must survive (rank 1 then carries nulls), and say in a comment why the order has no ties. Example: `int_deal_losses_joined_to_stages`.
  ```sql
  -- every stage change at or before the loss, latest first
  stage_changes_before_loss as (
      select
          losses.deal_id,
          losses.changed_at,
          stage_changes.stage_id,
          row_number() over (
              partition by losses.deal_id, losses.changed_at
              order by stage_changes.changed_at desc
          )                                   as stage_rank
      from losses
      left join stage_changes
          on losses.deal_id = stage_changes.deal_id
          and stage_changes.changed_at <= losses.changed_at
  )
  -- … then: where stage_rank = 1
  ```
- **`case` mappings are explicit and closed**: every expected value has a branch, with no `else` that silently assigns a business meaning. An unmapped value stays `null` and is caught by a `not_null` test.
- **Nulls carry meaning here**: a deal that never reached a stage has a null `reached_stage_at`, not a placeholder date. Use `coalesce` only when the meaning is certain (`activity_count` with no activities is `0`).
- **Timestamps**: keep the type and timezone from staging (this source records none). Truncate to a date or month only when the model's grain needs it, and name the column accordingly (`changed_date`, `changed_month`).

Use the standard CTE pattern: one **import CTE per `ref()`** at the top, then **logical CTEs** that each do one step, then a **final select** with the exact output columns.

**Filter in the import CTE.** It selects only the columns the model uses **and only the rows it needs**: the subset filter (e.g. `changed_field_key = 'stage_id'`) and, in incremental models, the lookback (`incremental_lookback_filter`) go in its `where`. Filtering at the first read lets Postgres push the predicate through the staging view to the source, so later CTEs only ever see the needed rows. **Never move such a filter down into staging**: staging keeps every source row, so each intermediate model can take its own subset, and a filter there would drop rows other models need.

```sql
with

-- only the stage rows: filtered at the first read, so the predicate reaches the source
deal_changes as (

    select
        deal_id,
        new_value_integer,
        changed_at
    from {{ ref('stg_pipedrive__deal_changes') }}
    where changed_field_key = 'stage_id'

),

stages as (

    select
        stage_id,
        stage_name
    from {{ ref('stg_pipedrive__stages') }}

),

-- business meaning: a stage_id change moves the deal into the stage in new_value_integer
stage_changes as (

    select
        deal_id,
        new_value_integer                       as stage_id,
        changed_at
    from deal_changes

),

enriched as (

    select
        stage_changes.deal_id,
        stage_changes.stage_id,
        stages.stage_name,
        stage_changes.changed_at
    from stage_changes
    left join stages
        on stage_changes.stage_id = stages.stage_id

)

select
    deal_id,
    stage_id,
    stage_name,
    changed_at
from enriched
```

- The example enriches with `stage_name` because it is rebuilt in full (view or table). In an **incremental / append** model, keep only the IDs and join labels in the mart: an appended row is never rewritten, so a stored label would go stale (see `int_deal_changes_filtered_to_stages` → `fct_deal_stage_changes`).
- Import CTEs are named after the model they read, without the `stg_` / `int_` prefix.
- Prefix every column with its CTE name in joins; no ambiguous columns.
- Lowercase SQL keywords, trailing commas, 4-space indents, one column per line, aliases with `as`.
- Repeated SQL across models becomes a macro only when it's purely technical (a date spine, a regex check). A business rule stays visible in a model, not hidden in a macro.
- No `order by` in the final select.

### 6. Materialization and schema

Intermediate models are internal building blocks, so the project needs **one folder-level `intermediate:` block** in `dbt_project.yml`, never per-model overrides. If it's missing, propose this and ask the user before adding it:

```yaml
    intermediate:
      +materialized: view         # small static data; switch to table only if a model is expensive or reused by many marts
      +schema: int_pipedrive      # used as-is (macros/generate_schema_name.sql): int_pipedrive.int_<…>
      +docs:
        node_color: "#4682B4"     # blue: marks intermediate nodes in the dbt docs lineage graph
```

- `view` is the default: always in sync, no storage, and the data volume here is small. Use `table` for a model with heavy window logic that several marts read. Use `ephemeral` only for a small step with a single consumer; it can't be tested or queried on its own, so prefer a view.
- A separate schema keeps building blocks apart from the public marts (`pipedrive_analytics`).
- `contract: enforced` is optional for intermediate models (rule: "Model Contracts"); contracts are for marts.
- **Incremental models** are the one allowed per-model override (e.g. `int_users`). Use them only when the input has a reliable change timestamp, and follow the rule's "Incremental Models and the `incremental` Tag" section (tags, documented lookback). Pick the strategy from how the data changes:

  | Data | Strategy | Notes |
  |---|---|---|
  | **Immutable events**: a row never changes once written (a stage change, a logged call) | `append` | Cheapest: insert only. Either a strict watermark (`where <event_at> > (select max(<event_at>) from {{ this }})`), or a lookback window via the macro **plus** a `not exists` anti-join on the grain, because re-reading the window would otherwise insert the same events again (see `int_deal_changes_filtered_to_creations`). Back the grain with a unique index and test it with `unique` / `unique_combination_of_columns`, so a duplicate fails |
  | **Mutable records**, small row-level changes per run (users updated one by one) | `merge` on `unique_key` | Updates changed rows in place, inserts new ones. Needs Postgres 15+. Allows `merge_update_columns` / `merge_exclude_columns` when some columns must survive updates |
  | **Mutable records**, large batches per run (a whole day or month replaced) | `delete+insert` on `unique_key` | Deletes the batch's keys and re-inserts them: cheaper than row-by-row matching for big batches |

  **Lookback windows use the project macro**, never a hand-written interval: `{{ incremental_lookback_filter('<column>', default_days=N, weekly_days=M) }}` inside the model's `{% if is_incremental() %}` block, in the import CTE. The one column is filtered in the input and read as the watermark from the model's own table, so keep it in the output and prefer a raw column (e.g. `changed_at`) so the filter is pushed down (see [macros/incremental_lookback.yml](../../../macros/incremental_lookback.yml); e.g. `int_deal_changes_filtered_to_creations`: 2 days, 8 on Mondays). A lookback re-reads loaded rows, so pair it with deduplication (`merge` / `delete+insert`, or `append` + a `not exists` anti-join on the grain).

  Deletes in the source never reach an incremental model by themselves. When they matter, add a delete `post_hook` rendered by the `delete_rows_missing_upstream` macro (upstream `ref`, raw key columns, optional filter; it never empties the table when the upstream is empty), e.g. `int_deal_changes_filtered_to_stages`, and an `equal_rowcount` test against the input where the grains match. Never hand-write the delete SQL in a model.
  **Load timestamp (incremental models only)**: every incremental model ends its select with `cast('{{ run_started_at }}' as timestamp with time zone) as dwh_date` (doc key `dwh_date` in `_intermediate_shared__docs.md`, tested `not_null`), so each row shows the run that wrote it; it changes only for rows a later run inserts or updates. Table and view models don't get it: a full rebuild stamps the same value on every row, and dbt's `run_results.json` and Elementary already record when each model was built.
- **Physical layout**: when downstream models mostly filter on one set of categories (e.g. `changed_field_key`, `funnel_step`), add an index with the `indexes` config (`indexes: [{columns: ['funnel_step']}]`). dbt-postgres has **no `cluster_by`** (that's Snowflake/BigQuery). To also order the table physically, create a **named** index and cluster on it in a post-hook: `create index if not exists <model>__<column>_idx on {{ this }} (<column>)`, then `cluster {{ this }} using <model>__<column>_idx`. (dbt gives `indexes` from the config hashed names, so a hook can't reliably refer to them.) Postgres doesn't keep that order for new rows, so the hook re-sorts after every load. Do this only for large tables that are read far more often than written, and say why in the description.

### 7. Write the YAML, docs and tests

**Naming (mandatory): `int_<entity>s_<verb>s`**, per [dbt's intermediate guide](https://docs.getdbt.com/best-practices/how-we-structure/3-intermediate): "✅ `int_[entity]s_[verb]s.sql` … think about *verbs* (e.g. `pivoted`, `aggregated_to_user`, `joined`, `fanned_out_by_quantity`, `funnel_created`, etc.)".

- **The input entity, plural, then what was done to it**, e.g. `int_deal_changes_filtered_to_stages` (the change log filtered to stage moves), `int_deal_stage_changes_aggregated_to_entries` (stage changes rolled up to the first entry per deal and stage), `int_deal_losses_joined_to_stages`, `int_activities_filtered_to_done`, `int_fields_unnested_to_options`. Prefer the guide's verbs: `filtered_to_`, `joined_to_`, `aggregated_to_`, `pivoted_to_`, `unnested_to_`, `unioned`, `windowed_to_`, `mapped`.
- **No source name and no double underscore**: "we've dropped the double underscores at this layer … simply reference the unified entity". The one exception from the guide: a model that works at source-system level before a later union keeps it (`int_<source>__<entity>s_<verb>s`, e.g. `int_shopify__orders_summed`).
- **Exception for entity models**: the layer's one-row-per-entity models keep the plain entity name, `int_deals` and `int_users`, because consumers know them as "the deal list" and "the user list"; dbt itself says naming here is "harder to dictate strictly". Use this only for a model that is *the* entity table.
- **Files**: `models/intermediate/<area>/int_<…>.sql` and `int_<…>.yml`.

**`int_<…>.yml`**: one file per model, same folder, `version: 2`, one `models:` entry. `description:` **inline** (`>` block, never `{{ doc() }}`), covering the rule's five points:
1. **Purpose**: which business question it answers, and which marts use it.
2. **Grain**: "One row per …", the columns that define it, and the join key consumers must use (e.g. "**Join on `deal_id` and `stage_id` together.**").
3. **Transformations and business logic**: each join (type, key, unmatched rows), each business rule in plain words, each aggregation and window rule (partition, order, tie-breaker).
4. **Edge cases**: deals skipping or revisiting stages, ties, nulls and what they mean, rows dropped by filters or inner joins (which rows and why, with the `analyses/` file that counts them), known data-quality issues inherited from upstream and how this model treats them.
5. **Refresh**: e.g. "View, rebuilt on every `dbt run`. The upstream source is a static, one-time load, so there is no freshness check."

No counts, data date ranges or "today" claims anywhere in the YAML or doc blocks: describe each finding in words and point to its `analyses/` file (rule: "No counts or profiling results in documentation").

`columns:` every output column, in select order, each `description: "{{ doc('<key>') }}"`.

**Doc blocks**: reuse existing keys (e.g. `deal_id`, `stage_id`, `stages__stage_name`) whenever the meaning is unchanged; a renamed column with the same meaning keeps its key. A column whose meaning is new here (a rule, a derived timestamp, a count, a role) gets a new key named `int_<model>__<column>`, or a shared key if several models use the concept. New keys go in `models/intermediate/<area>/_intermediate_<area>__docs.md`, in the model's own folder (e.g. `models/intermediate/deals/_intermediate_deals__docs.md`); create it if missing. A key used by models in **several** area folders goes in `models/intermediate/_intermediate_shared__docs.md` (create it if missing). Keys are global in dbt, so a mart can reference any of them.

**Tests** (per the rule's "When to Test": test what this model creates or guarantees; don't repeat upstream tests on untouched columns):

| What | Test |
|---|---|
| Grain | **Always.** `unique` + `not_null` on a single-column grain; `dbt_utils.unique_combination_of_columns` + `not_null` on each grain column for a composite grain (the combination test doesn't catch nulls) |
| Columns given meaning here (`new_value_integer as stage_id`, `owner_user_id`) | `not_null`, plus `relationships` to the parent staging model unless upstream already tests it for that key (e.g. a `where`-limited relationships test on `stg_pipedrive__deal_changes`) |
| Mapped / classified columns (`funnel_step`, `is_won`) | `not_null` (proves the mapping is closed) + `accepted_values` |
| Joins that must not drop or multiply rows | a row-count check against the driving model, e.g. `dbt_utils.equal_rowcount` against the upstream model at the same grain |
| Rules across columns (`lost_at >= created_at`, counts ≥ 0) | `dbt_utils.expression_is_true` |
| Rules across rows (no stage change before creation) | a singular test in `tests/`, only if a generic test can't express it |
| Enriched columns copied from a lookup (`stage_name`) | none beyond `not_null` if the join could leave it null; the lookup's own tests cover its values |

**Severity**: grain and business-rule tests use `severity: error`. **No thresholds** (`warn_if` / `error_if`) on any test: a known, documented data-quality issue fails like a new one, so the build shows it until the source is fixed. Explain it in the model description's **Edge cases** (fails on purpose, why, `Evidence: analyses/…`), never with a test `description` or comment; no counts (project rules). `severity: warn` is only for early-warning tests that are expected to find nothing and flag a pattern worth reviewing (e.g. `assert_deals_start_at_stage_1`). Use `data_tests:`, with inputs under `arguments:` and `severity` / `where` under `config:`.

### 8. Validate

1. `dbt parse` must be clean, with no test-syntax deprecation warnings.
2. Build and test as **two separate commands**, never `dbt build`: first `dbt run --select int_<…>`, then `dbt test --select int_<…>`. `dbt build` skips every downstream model when a test fails; run-then-test builds all selected models first and then reports every failing test, so a failing test is a finding to report, not a reason to leave models unbuilt.
3. **Reconcile row counts** with `dbt show`:
   - same grain as the driving model → counts must be equal;
   - re-grained (pivot, roll-up) → `count(*)` equals `count(distinct <grain columns>)` of the input;
   - filtered or inner-joined → the difference matches the rows the filter is documented to drop (check against the `analyses/` file).
4. **Spot-check the business rule** on a few real entities, including the edge cases from step 2 (a deal that skipped a stage, one that revisited a stage, one with two creation times). Show the input rows and the output row side by side.
5. Report to the user: models built, row counts (input → output), tests passed / warned / failed, every business rule applied, and every decision still open.

## Done when

- [ ] Carries the project tag (`pipedrive`) in `dbt_project.yml` and in its own YAML (`config: tags: ["pipedrive"]`, first in the list when other tags exist; rule: "Project tag")
- [ ] Each model has one purpose, is named `int_<entity>s_<verb>s` (or is an entity model: `int_deals`, `int_users`), lives under its business-area folder `models/intermediate/<area>/` with its doc blocks in that folder's `_intermediate_<area>__docs.md`, and reads only `ref()`s to `stg_` / `int_` models, with no `*` anywhere
- [ ] The grain is documented with its defining columns and join key, and tested (composite grains via `unique_combination_of_columns` + `not_null`; no surrogate keys)
- [ ] Every join has a documented type, key and cardinality; fan-out and dropped rows were profiled and the counts reconciled
- [ ] Every business rule was confirmed with the user, is written once, and is described in plain words; window functions are deterministic; "latest / first row per group" uses a ranked join (`row_number()`), not a lateral join
- [ ] One YAML per model; the inline description covers purpose, grain, logic, edge cases, refresh; every column is a `{{ doc() }}` reference, in select order, with shared keys reused
- [ ] Created/derived columns tested; known issues fail (no thresholds), explained in the model description's Edge cases (not on the test); untouched upstream columns not re-tested
- [ ] No counts or profiling results in the description, doc blocks or test comments; findings point to `analyses/`
- [ ] Materialization and schema come from the `intermediate:` block in `dbt_project.yml`, with no per-model override
- [ ] `dbt run` then `dbt test` on the models (not `dbt build`): models built, tests pass (or warnings/failures reported with counts)

## Afterwards

- Commit only when asked, following [.claude/rules/commit-dbt-changes.md](../../rules/commit-dbt-changes.md). Intermediate models, their YAML and their doc blocks go in the **Intermediate** commit, after the Staging commit they depend on. If the `intermediate:` block had to be added to `dbt_project.yml`, it goes in its own commit before them (or with the first intermediate commit).
