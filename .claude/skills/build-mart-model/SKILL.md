---
name: build-mart-model
description: Build dbt mart models, the public, consumer-facing layer — dimensions (dim_<entity>, one row per business entity with its descriptive attributes), facts (fct_<process>, one row per business event or measurement at a declared grain), and reports (rep_<subject>_<grain>, aggregated to a reporting grain for one consumer, e.g. rep_sales_funnel_monthly). Applies dimensional modeling (facts and dimensions) with dbt's marts and style guides, with enforced contracts, documented and tested per .claude/rules/dbt-documentation-testing.md. Use when asked to build, add, write, or refactor a mart, fact, dimension, report, rep_/fct_/dim_ model, star schema, or the marts layer, or to expose data to a dashboard or BI tool.
argument-hint: "[mart to build or business question — e.g. 'rep_sales_funnel_monthly', 'dim_deals', 'deal pipeline fact']"
---

# Build mart models

Goal: the **public layer**, the only tables that dashboards, BI tools, analysts and other teams query. Staging changes how the data *looks*, intermediate decides what it *means*, and marts **shape it for a consumer**: one clear grain per table, consumer-friendly names, current labels, and a contract that guarantees the shape.

Standards for YAML structure, descriptions, doc blocks, tests and contracts live in [.claude/rules/dbt-documentation-testing.md](../../rules/dbt-documentation-testing.md). Read it first, especially "Model Contracts (Marts)" and "Exposure Documentation Standards". This skill is the procedure that applies it to the marts layer. If the two ever disagree, the rule wins.

## The three kinds of mart

| Kind | Name | One row per | Holds | Example |
|---|---|---|---|---|
| **Dimension** | `dim_<entity>` (plural) | business entity: a deal, a user, a stage | the entity's key and **descriptive attributes** used to filter, group and label (name, type, current stage, owner, flags) | `dim_deals`, `dim_users`, `dim_stages` |
| **Fact** | `fct_<business process>` (plural, as events) | business **event or measurement** at a declared grain | keys of the dimensions involved, the event's timestamps, and **numeric measures** | `fct_deal_stage_entries`, `fct_sales_calls`, `fct_deal_pipeline` |
| **Report** | `rep_<subject>_<grain>` | **reporting grain** for one consumer (month × KPI, owner × week) | aggregated, presentation-ready columns with the exact names the consumer asked for | `rep_sales_funnel_monthly` |

How they relate: **dimensions and facts are the reusable core** (a star schema: facts in the middle, dimensions around them, joined on the dimension key). **Reports are built on top of facts and dimensions** for one specific question. Build a report only when a request asks for it; a new question should usually be answerable from the existing facts and dimensions.

**Where marts stop and intermediate begins.** Business rules (what counts as "entered a stage", which deals are excluded) live **once**, in intermediate. A mart selects, joins, aggregates and renames for the consumer; it does not decide meaning. If you are about to write a new business rule in a mart, it belongs in an `int_` model first (see the [build-intermediate-model](../build-intermediate-model/SKILL.md) skill).

## Non-negotiables

1. **Read from `int_` models and other marts.** Never `{{ source() }}`. Read a `stg_` model only for a plain lookup with no logic (e.g. `stg_pipedrive__stages` for the current `stage_name`); anything with a rule goes through an `int_` model. Dependencies only flow downstream: `dim_` / `fct_` read `int_`; `rep_` reads `fct_` / `dim_` (or the `int_` model that already holds the report's events, when no fact exists yet).
2. **Declare the grain before writing SQL**: one sentence, "one row per …", plus the columns that define it. **One grain per table**: never mix grains (no total or subtotal rows in a report, no deal-level and month-level rows in one fact). A different grain is a different table.
3. **Natural keys, no surrogate keys** (project rule). Facts carry the dimensions' natural keys (`deal_id`, `stage_id`, `owner_user_id`). A composite grain is enforced with `dbt_utils.unique_combination_of_columns` + `not_null` on each column. No hashed surrogate keys: the source IDs are stable integers, there is no SCD type 2 yet, and a natural key shows which columns define the row.
4. **Every mart has an enforced contract** (`contract: enforced: true`) with an exact Postgres `data_type` (with size/precision) on every column, and `not_null` constraints on the grain columns (rule: "Model Contracts (Marts)").
5. **Display names are current, joined at build time.** Names (`stage_name`, `lost_reason_name`, `owner_name`) are joined in the mart from their lookup, never stored in an incremental/append model where a rename would leave them stale.
6. **Never write `*`.** Every CTE and the final select list their columns by name.
7. **One definition per concept.** Never build the same concept twice for different teams (`finance_deals`, `marketing_deals`). If a definition really differs, it is a different concept with its own name (`qualified_deals`, not `marketing_deals`).
8. **Column naming** ([dbt style guide](https://docs.getdbt.com/best-practices/how-we-style/1-how-we-style-our-dbt-models)): a dimension's primary key is `<object>_id` (`activity_type_id`, not the text key `activity_type`); one concept keeps one name in every model (a loss time is `lost_at` everywhere, never `changed_at` in one fact); display names end in `_name`, never `_label`; columns ordered ids, strings, numerics, booleans, dates, timestamps. A column name fixed by the consumer (the brief's `month`, `funnel_step`) is the exception.
9. **Read-only on the database** while profiling: only `select` queries via `dbt show` (MCP `mcp__dbt__show`).

## Challenge the request first

Follow [.claude/rules/challenge-modeling-requests.md](../../rules/challenge-modeling-requests.md): check the request against best practice, prove a conflict with profiling numbers, propose the alternative, and let the user decide. Warning signs at the mart layer:

| Warning sign | Why it's wrong | Best-practice alternative |
|---|---|---|
| **Joining two facts** on `deal_id`, `changed_at` or both (stage changes × losses, stage changes × activities) | different processes and grains: on the timestamp it matches nothing, on the entity key it fans out | the right model for the question: an as-of rule in intermediate (e.g. stage at loss), a `union all` timeline (`fct_deal_events`), or a per-entity accumulating snapshot |
| **A conditional join key** ("on `changed_at`, else on `deal_id`") | each row means something different; no single grain to declare or test | one grain per table; separate models per question |
| **One wide table of several event streams** "to start the analysis from" | mixed grains, fan-out, `count(distinct)` everywhere, rows lost by inner matches | stack events (`union all`) at one grain, or one row per entity with aggregated milestones |
| **A dimension made from an event-grain model** (e.g. `int_activities_joined_to_types` as `dim_activity_types`) | the key isn't unique: ~1,100 rows per type; joins multiply | build the dimension from the entity's own table at one row per entity |
| **A dimension's members from `select distinct` on a fact** | members with no events disappear | read the entity's lookup/list |
| **A fact whose name hides its scope** (e.g. `fct_activities` holding only done activities) | consumers assume completeness and compute wrong rates | name the scope (`fct_activities_done`) or store the atomic grain with a flag (`is_done`) |
| **A business rule written in the mart** (a mapping, an exclusion, "which row wins") | rules must live once, reusable, in intermediate | put the rule in an `int_` model and let the mart select from it |
| **A membership flag checked against an event table** (`has_known_deal` via stage changes) | ties "the entity exists" to "the entity had this event" | check against the entity list (`int_deals` / `dim_deals`) |

## Procedure

### 1. Scope and consumer

- Who consumes it (dashboard, analyst, export, another team) and **which question** it answers. If no one will consume it, ask whether it's needed.
- Which kind it is (table above). A request for "a monthly report with these columns" is a `rep_`; "something to slice deals by owner and stage" is a `fct_` + `dim_`s.
- If the consumer fixed column names or values (e.g. the README's `month`, `kpi_name`, `funnel_step`, `deals_count`), they are the contract: use them exactly.
- Read the task file (`.claude/tasks/*.md`) for decisions already made (e.g. the funnel rules), and the upstream `int_` YAMLs for grain, join keys and edge cases.
- List existing marts and extend or reuse them (a conformed `dim_deals` serves every fact about deals).
- **Location (mandatory):** `models/marts/`. Group into subfolders by business area (`models/marts/sales/`) only once there are about 10 marts or more.
- Check that `dbt_project.yml` has a `marts:` block (step 7). If it's missing, propose it and ask before adding it.

### 2. Design it in four steps

Write these down before coding:

1. **Business process**: the activity being measured (deals moving through the pipeline, sales calls being held).
2. **Grain**: the most atomic level the process records, unless the consumer explicitly needs a summary (then it's a `rep_`). Atomic facts answer questions nobody has asked yet; summaries only answer the one they were built for.
3. **Dimensions**: the "who, what, when" that describe each row at that grain (deal, stage, owner, date). Every candidate must be single-valued at the grain; if it isn't, the grain is wrong or it belongs in another fact.
4. **Facts (measures)**: the numbers at that grain (`deals_count`, `days_in_stage`, `activity_count`). Every measure must be true at the declared grain.

### 3. Dimensions (`dim_`)

- **One row per entity**, keyed by its natural key (`deal_id`), tested `unique` + `not_null`.
- **Wide and denormalized** (star, not snowflake): fold descriptive attributes of closely related lookups into the dimension (`dim_deals` carries `current_stage_id` *and* `current_stage_name`, `owner_user_id` *and* `owner_name`), so consumers need one join, not a chain.
- **Conformed**: one dimension per entity, shared by every fact. Never build a second deal dimension for another report.
- **Slowly changing attributes**: default is **type 1** (current value only, overwritten on each build). Keep history (**type 2**: one row per version with `valid_from` / `valid_to`) only when a consumer needs "as it was at the time", and ask first: it needs a dbt snapshot on the staging/source data, and the dimension's grain becomes (`<entity>_id`, `valid_from`).
- **Null attributes**: keep `null` in data columns where null means "unknown". For a **label that consumers group by**, replace null with an explicit, documented value (`'Unknown'`, `'Not lost'`) so a BI group-by doesn't show an empty bucket; say which in the column doc.
- Data-quality flags from intermediate (`has_multiple_creations`) are carried into the dimension as attributes, so consumers can filter them.

### 4. Facts (`fct_`)

Pick the type from the process (three fact table types, plus factless):

| Type | One row per | Use when | Example here |
|---|---|---|---|
| **Transaction** | event, at the moment it happens | the process is a stream of discrete events | `fct_deal_stage_entries`: one row per deal and stage entered |
| **Periodic snapshot** | entity × regular period (day, month), even with no activity | measuring a **state** over time (open pipeline per month) | `fct_pipeline_monthly`: one row per stage and month, open deals |
| **Accumulating snapshot** | process instance, with one timestamp per milestone | a pipeline with a clear start, known steps and an end | `fct_deal_pipeline`: one row per deal, `created_at`, `stage_1_entered_at` … `lost_at`, lags in days |
| **Factless** | an event with no numeric measure, only keys | recording that something happened (a call held, a deal entering a step) | `fct_sales_calls`: one row per done call |

- **Measures are additive whenever possible** (summable across every dimension: counts, amounts, durations). **Semi-additive** measures (balances, open-deal counts in a snapshot) can't be summed over time; document that on the column. **Non-additive** measures (ratios, conversion rates) are never stored alone: store the additive **numerator and denominator**, and compute the ratio in the report or BI layer.
- **Foreign keys to dimensions are never null for a data gap.** Each FK has a `relationships` test to its `dim_`. A null is only allowed where it means "not applicable / not happened yet" (an accumulating snapshot's `lost_at` before the deal is lost), and the column doc says so.
- **Timestamps per role** (role-playing dates): name each date for its role (`created_at`, `entered_at`, `lost_at`, `due_at`), never a generic `date`. Add a truncated column only when the grain needs it (`entered_month`). Dates stay columns on the fact; a report that needs a complete period list generates it (step 5).
- **Degenerate dimensions** (an ID with no table of its own, like `activity_id`) stay in the fact as plain columns.
- An accumulating snapshot in dbt is simply a table **rebuilt on every run** from the `int_` event models; it never needs `update` logic.

### 5. Reports (`rep_`)

- **Built from facts and dimensions** (or the `int_` event model that already applies the report's rules). The report aggregates; it doesn't re-derive events.
- **Complete grids**: when the consumer expects every period × category (every month × every funnel step, zeros included), build a **spine** and `left join` the counts onto it, `coalesce(count, 0)`. Periods: generated in the report with `generate_series`, **over the report's data range** (from the month of the smallest date to the month of the largest); the project has no shared calendar dimension. Categories: the **closed list** from a lookup (an `int_` model or a seed), never `select distinct` from the events, which would drop a category with no events. Document the spine's range and where it comes from (the data's min/max, not a hard-coded date unless the consumer fixed it).
- **Periods are dates, not strings**: `month` is a `date` (first day of the month, `date_trunc('month', …)::date`), so it sorts and filters correctly in BI. Format it in the BI tool, not in SQL.
- **Exact column names and values** from the request; categorical columns get `accepted_values`.
- **Count at the right grain**: `count(*)` when the input grain is already one row per counted thing; `count(distinct …)` only when it isn't, and say why.
- Ratios: output numerator and denominator alongside the rate (step 4).
- No `order by` in the model; sorting belongs to the consumer.

### 6. SQL

Same structure as the other layers: one **import CTE per `ref()`** that selects only the needed columns and filters as early as possible, **logical CTEs** that each do one step, and a **final select** with the exact output columns in contract order.

```sql
with

-- one row per deal, funnel step and month (funnel rules applied in int_deal_funnel_steps_unioned)
funnel_events as (

    select
        funnel_step,
        kpi_name,
        event_month
    from {{ ref('int_deal_funnel_steps_unioned') }}

),

-- every month of the data period
months as (

    select
        generate_series(
            (select min(event_month) from funnel_events),
            (select max(event_month) from funnel_events),
            interval '1 month'
        )::date                                 as month

),

-- the closed list of steps, never the distinct steps seen in the events:
-- a step with no events at all must still get its rows
steps as (

    select
        funnel_step,
        kpi_name
    from {{ ref('int_funnel_steps_mapped') }}

),

-- every month × step, so a step with no entries shows 0
spine as (

    select
        months.month,
        steps.kpi_name,
        steps.funnel_step
    from months
    cross join steps

),

counts as (

    select
        event_month                             as month,
        funnel_step,
        count(*)                                as deals_count
    from funnel_events
    group by
        event_month,
        funnel_step

)

select
    spine.month,
    spine.kpi_name,
    spine.funnel_step,
    coalesce(counts.deals_count, 0)            as deals_count
from spine
left join counts
    on spine.month = counts.month
    and spine.funnel_step = counts.funnel_step
```

- **Aggregate before joining**: roll events up to the target grain, then join to the spine or dimension; never join first and repair the fan-out with `distinct`.
- **Join dimensions on their natural key only**, and reconcile row counts (step 9): a dimension join must never change a fact's row count.
- `union all`, never `union`, when inputs can't overlap (stage events vs call events).
- Too many joins in one mart (more than 4–5 concepts) is a sign that an intermediate model is missing: build it there, then join fewer, wider inputs here.
- Lowercase SQL, trailing commas, 4-space indents, one column per line, aliases with `as`, every column prefixed with its CTE in joins.

### 7. Materialization and schema

No `dwh_date` (load timestamp) in marts: they are rebuilt in full, so it would be the build time on every row and one more contract column for consumers; only incremental `int_` models carry it.

One folder-level `marts:` block in `dbt_project.yml`, never per-model overrides. If it's missing, propose this and ask before adding it:

```yaml
    marts:
      +materialized: table          # public layer: queried often, so computed once per run, not per dashboard refresh
      +schema: pipedrive_analytics  # used as-is (macros/generate_schema_name.sql): the public schema
      +docs:
        node_color: "#D4A017"       # gold: marks mart nodes in the dbt docs lineage graph
```

- `table` is the default. Make a mart **incremental only when a full rebuild is too slow**, never by default; a report over a spine or a dimension with type 1 attributes is cheapest and safest as a table. An incremental mart follows the intermediate skill's step 6 (strategy, lookback macro, `on_schema_change: fail` or `append_new_columns`, as contracts require).
- Indexes (`indexes:` config) only for columns that consumers filter on heavily and only on large tables; say why in the description.

### 8. Write the YAML, docs and tests

**Files**: `models/marts/<name>.sql` and `<name>.yml` (one model per YAML, `version: 2`). Dashboards and other consumers are declared as **exposures** in `models/marts/_marts__exposures.yml` (rule: "Exposure Documentation Standards"): purpose, the mart driving it, its grain, refresh.

**Description** (inline `>` block), the rule's five points, plus for marts:
1. **Purpose**: the consumer and the question; for a report, the request it fulfils.
2. **Grain**: "One row per …", the defining columns, the join key. For facts, the **fact type**; for reports, the spine's range.
3. **Transformations and business logic**: which `int_` models apply which rules (in words, never by decision code), each join (type, key, cardinality), each aggregation, and the additivity of every measure.
4. **Edge cases**: excluded entities (which and why, with the `analyses/` file that lists them), zero-filled rows, null meanings ("not lost yet"), known data-quality issues and how they show up for the consumer.
5. **Refresh**: e.g. "Table, rebuilt on every `dbt run`. The upstream source is a static, one-time load."

No counts, data date ranges or "today" claims anywhere in the YAML or doc blocks: describe each finding in words and point to its `analyses/` file (rule: "No counts or profiling results in documentation"). For a report's grain, name the spine ("every month of the data period × every funnel step"), not its current row count.

**Contract** (rule: "Model Contracts (Marts)"):

```yaml
    config:
      contract:
        enforced: true
    columns:
      - name: month
        description: "{{ doc('rep_sales_funnel_monthly__month') }}"
        data_type: date
        constraints:
          - type: not_null
      - name: kpi_name
        description: "{{ doc('kpi_name') }}"
        data_type: character varying(100)
        constraints:
          - type: not_null
```

Every column: `description` as a `{{ doc() }}` reference (reuse existing keys; new keys in `models/marts/_marts__docs.md`), an exact `data_type`, in select order. Cast in SQL to the declared type where Postgres would infer something else (`count(*)` is `bigint`; cast to `integer` if the contract says so).

**Tests** (constraints guarantee the shape; tests check the content):

| What | Test |
|---|---|
| Grain | `unique` (single column) or `dbt_utils.unique_combination_of_columns` (composite), at `error`; `not_null` is covered by the contract's constraints |
| Fact → dimension keys | `relationships` to the `dim_` (a null only where it means "not applicable", excluded with a `where`) |
| Categorical report columns | `accepted_values` with the exact list (`funnel_step`, `kpi_name`) |
| Complete grid | row count = periods × categories (`dbt_utils.expression_is_true` on a count, or a singular test) |
| Reconciliation | the report's total equals the events it counts (`sum(deals_count)` = rows of the `int_` event model): a singular test in `tests/` |
| Measures | `dbt_utils.expression_is_true` for ranges (`deals_count >= 0`, `days_in_stage >= 0`) |
| Known data-quality issues | the test **fails**, no thresholds (`warn_if` / `error_if`): explained in the model description's **Edge cases** (fails on purpose, why, the analysis to rerun), never on the test; no counts (project rules) |

### 9. Validate

1. `dbt parse` clean, with no deprecation warnings.
2. `dbt run --select <mart>`, then `dbt test --select <mart>`, **never `dbt build`**, so a failing test doesn't leave models unbuilt. The contract's preflight fails the run if columns or types drift.
3. **Reconcile** with `dbt show`: the row count matches the grain (facts: equal to the `int_` input at the same grain; reports: periods × categories), and totals match the input events.
4. **Spot-check** a few real entities end to end (a deal through every step, an excluded deal, a zero month), input rows next to output rows.
5. Report to the user: models built, row counts, tests passed / warned / failed with counts, the decisions applied, and anything still open.

## Done when

- [ ] Carries the project tag (`pipedrive`) in `dbt_project.yml` and in its own YAML (`config: tags: ["pipedrive"]`, first in the list when other tags exist; rule: "Project tag")
- [ ] Each mart is a `dim_` / `fct_` / `rep_` with one declared, tested grain, under `models/marts/`, reading only `int_` models, other marts or plain `stg_` lookups, with no `*`
- [ ] Facts state their type; measures are additive or documented as semi/non-additive (ratios stored as numerator + denominator)
- [ ] Dimensions are conformed (one per entity) and wide; labels are current, joined at build time
- [ ] No business rule is defined here that isn't in an `int_` model; every decision applied is named in the description
- [ ] Contract enforced with exact Postgres types and `not_null` constraints on the grain
- [ ] Inline description covers purpose, grain, logic, edge cases, refresh; every column is a `{{ doc() }}` reference, in select order
- [ ] Grain, relationships, accepted values, completeness and reconciliation tested; consumers declared as exposures
- [ ] Materialization from the `marts:` block in `dbt_project.yml`, no per-model override
- [ ] No counts, data date ranges or example IDs in the description, doc blocks, test comments or exposures; tests failing on purpose are explained in the description, not on the test
- [ ] `dbt run` then `dbt test` (not `dbt build`): built, tests pass (or failures reported with counts), totals reconciled

## Afterwards

- Update the task file (`.claude/tasks/*.md`) when a mart is built or a decision is made.
- Commit only when asked, following [.claude/rules/commit-dbt-changes.md](../../rules/commit-dbt-changes.md). Marts, their YAML, doc blocks and exposures go in the **Marts** commit, after the Intermediate commit they depend on. If the `marts:` block had to be added to `dbt_project.yml`, it goes in its own commit before them (or with the first marts commit).

## References

- dbt, [How we structure our dbt projects: Marts](https://docs.getdbt.com/best-practices/how-we-structure/4-marts): entity grain, no duplicate concepts per team, start simple with materializations, avoid too many joins.
- dbt, [How we style our dbt models](https://docs.getdbt.com/best-practices/how-we-style/1-how-we-style-our-dbt-models): `<object>_id` keys, consistent field names, column order, `<event>_at` / `<event>_date`.
- dbt, [Model contracts](https://docs.getdbt.com/docs/mesh/govern/model-contracts): shape guarantees, Postgres enforces all constraint types.
