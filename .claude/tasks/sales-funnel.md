# Task: Pipedrive data layers and `rep_sales_funnel_monthly`

Read this file before any work on the Pipedrive models. It states the goal, the decisions in force and the current design. It holds the final state only, not a history: when a decision changes, edit it in place.

## 1. Goal

Model the Pipedrive CRM data into **reusable dbt layers** (sources → staging → intermediate → marts), and deliver one report on top of them: `rep_sales_funnel_monthly`.

**The layers matter more than the report.** They will serve many future requests and KPIs, so:

- Write every business rule **once**, in an intermediate model, and have marts `ref()` it.
- Design intermediate models around **business entities and events** (deals, stage entries, sales calls), not around this one report.
- Keep data-quality issues visible (flags, documented findings, failing tests; no thresholds). Never quietly filter them away in a lower layer.

## 2. Brief (from the assessment)

1. Study the Pipedrive source data in depth (Pipedrive terms: see §4).
2. Define dbt sources and build the layers for relevance and maintainability.
3. Build `rep_sales_funnel_monthly`: monthly intervals, **how many deals (clients) entered each funnel step**:

   | `funnel_step` | `kpi_name` | Comes from |
   |---|---|---|
   | `1` | Lead Generation | stage 1 entered |
   | `2` | Qualified Lead | stage 2 entered |
   | `2.1` | Sales Call 1 | activity type `meeting` |
   | `3` | Needs Assessment | stage 3 entered |
   | `3.1` | Sales Call 2 | activity type `sc_2` |
   | `4` | Proposal/Quote Preparation | stage 4 entered |
   | `5` | Negotiation | stage 5 entered |
   | `6` | Closing | stage 6 entered |
   | `7` | Implementation/Onboarding | stage 7 entered |
   | `8` | Follow-up/Customer Success | stage 8 entered |
   | `9` | Renewal/Expansion | stage 9 entered |

4. Output columns, exactly: `month`, `kpi_name`, `funnel_step`, `deals_count`.

### What the assessment evaluates

| Area | What reviewers look for | How this project shows it |
|---|---|---|
| **Exploratory analysis** | A thorough investigation and understanding of the data | Every finding is a dated, rerunnable query in `analyses/` (one question per file). Descriptions state findings in words, without counts, and point to the analysis |
| **Data modelling** | Data structured and organized meaningfully | Clear layers (§8), one documented and tested grain per model, business rules written once in intermediate, entity models (`int_deals`, `int_users`) reusable beyond this report, conformed dimensions and facts in the marts |
| **SQL code efficiency** | Queries optimized for performance | See "SQL efficiency rules" below |
| **Project organization and clarity** | Work that is easy to understand and collaborate on | The rules and skills in §3; one YAML per model with concise descriptions; doc blocks reused; lineage colours in `dbt docs`; the README explains setup, run order and where the reports are; commits by layer with a clear PR summary |

**SQL efficiency rules**

- **Read only what you need.** Import CTEs select only the columns the model uses and filter as early as possible (e.g. `where changed_field_key = 'stage_id'` in the first CTE that reads `stg_pipedrive__deal_changes`), so the planner pushes predicates into the staging views. Never move such a subset filter into staging: staging keeps every source row.
- **Scan a table once per model.** Derive several facts from one pass with conditional aggregation instead of joining the same model several times.
- **Aggregate before joining.** Roll children up to the parent grain first, then join; never fix a fan-out with `distinct`.
- **Use `exists` for flags and filters** (`has_known_deal`), not a join that can multiply rows.
- **Prefer `min()` / `max()` with `group by`** over `row_number() … = 1` when one value per group is enough; latest / first *row* per group is a ranked join (`row_number()`), never a lateral join.
- **`union all`, not `union`**, when the inputs can't overlap (stage events vs call events).
- **No `count(distinct …)` where the grain already guarantees uniqueness.**
- **Materialize on purpose.** Staging: views. Intermediate: tables, or incremental where rows are immutable events or a reliable change timestamp exists. Marts: tables, none incremental (they join current names at build time and have rows that change).
- **Incremental pattern** (details in the build-intermediate-model skill): immutable events load with `append` + a lookback window (`incremental_lookback_filter`: 2 days, 8 on Mondays) + a `not exists` dedup on the grain + a unique index + a delete `post_hook` (`delete_rows_missing_upstream`); mutable records (`int_users`) load with `merge` on the `unique_key`.

## 3. Rules every agent must follow

| Topic | Rule |
|---|---|
| Challenging requests | [.claude/rules/challenge-modeling-requests.md](../rules/challenge-modeling-requests.md): check every modeling request against best practice (official dbt docs only, quoted and linked); prove a conflict with profiling numbers; propose the alternative; the user decides, and a kept trade-off is documented |
| Docs and tests | [.claude/rules/dbt-documentation-testing.md](../rules/dbt-documentation-testing.md): one YAML per model; concise inline descriptions in five sections (purpose, grain, transformations / business logic, edge cases, refresh); every column description a `{{ doc() }}` reference; no counts, decision codes or decision dates in any description; `data_tests:` with `arguments:` |
| Sources | [onboard-raw-source](../skills/onboard-raw-source/SKILL.md) skill: source table descriptions hold only purpose, grain, load / test scope and freshness |
| Staging | [build-staging-model](../skills/build-staging-model/SKILL.md) skill |
| Intermediate | [build-intermediate-model](../skills/build-intermediate-model/SKILL.md) skill |
| Marts | [build-mart-model](../skills/build-mart-model/SKILL.md) skill |
| Data findings (EDA) | [write-eda-analysis](../skills/write-eda-analysis/SKILL.md) skill: one question per file in `analyses/`; header = question, run command, dated result, conclusion, relied on by |
| Pipedrive behaviour | [verify-api-assumptions](../skills/verify-api-assumptions/SKILL.md) skill: assumptions checked against Pipedrive's own docs, its developer forum and Stack Overflow only, quoted with links |
| Commits / PR | [.claude/rules/commit-dbt-changes.md](../rules/commit-dbt-changes.md): only when asked; one commit per layer, in lineage order; never stage `.env*`, `profiles.yml` or credentials |
| Running dbt | **`dbt run` then `dbt test`, never `dbt build`**, so a failing test doesn't skip downstream models. Report pass / warn / fail with counts |
| Keys | No surrogate keys. A composite grain is enforced with `dbt_utils.unique_combination_of_columns` plus `not_null` on each column, and documented as the join key |
| Known data issues | No thresholds on any test: a known issue fails like a new one. The staging or model description's Edge cases explain that it fails on purpose, why, and which analysis to rerun; no test `description` or comment. Failing on purpose today: source `activity.activity_id` unique, source and `stg_pipedrive__activities` `deal_id` relationships, `int_deals` `not has_multiple_creations`. `severity: warn` only for early-warning tests expected to find nothing |
| Business meaning | Never invent it. Ask the user and record the answer in §7 |
| Source freshness | Every source table with a timestamp has a freshness check, thresholds by load schedule (daily: warn 1 day / error 2 days; hourly: 1 hour / 2 hours): `activity` on `due_to`, `deal_changes` on `change_time`. `activity_types`, `fields`, `stages`, `users` wait for a `_loaded_at` column (commented `config:` ready) |
| Tags | Every model and source table carries `pipedrive`, set in `dbt_project.yml` and in its own YAML. Every intermediate and mart model carries `daily`; lookback incrementals also `incremental`. Staging views carry no schedule tag |
| Orchestration | `orchestration/airflow/dags/dbt_pipedrive_refresh.py`: source freshness, then `tag:daily,tag:incremental`, then `tag:daily+` (excluding incrementals), then tests on `+tag:daily+`; test failures are reported by a separate task and don't turn the run red |
| Naming | Staging `stg_<folder>__<entity>s` in schema `stg_<folder>`. Intermediate `int_<entity>s_<verb>s` in business-area folders (`deals/`, `funnel/`, `activities/`, `users/`, `fields/`), each with `_intermediate_<area>__docs.md`; entity models keep plain names (`int_deals`, `int_users`). Marts `dim_` / `fct_` / `rep_`; columns per dbt's style guide: primary key `<object>_id`, one name per concept across models (`lost_at`), display names end in `_name`, ids first. Exceptions: the brief's report columns and `funnel_step` |
| Load timestamp | `dwh_date` (`run_started_at` of the run that wrote the row) on every incremental model only: `int_users` and the four `int_deal_changes_filtered_to_*` models. None in staging views, table models or marts, where it would be the build time on every row |
| Database | Read-only (`dbt show` selects) while profiling |

## 4. Pipedrive terms

- **Deal**: a sales opportunity with a client. The source has **no deals table**; deals exist only through the change log `deal_changes` (and as `activity.deal_id`).
- **Pipeline / stage**: the ordered steps a deal moves through (`stages`, 1–9).
- **Deal change log** (`deal_changes`): one row per change to a deal field. `changed_field_key` says which field changed: `add_time` (deal created), `stage_id` (moved to a stage), `user_id` (new owner; `owner_id` in API v2), `lost_reason` (marked lost, with a reason ID).
- **Fields** (`fields`): metadata of the deal fields; picklist options (stage and lost-reason labels) are a JSON array in `field_value_options`.
- **Activity**: a scheduled task on a deal, assigned to a user. `activity_types` maps `type` to a name: `meeting` = Sales Call 1, `sc_2` = Sales Call 2, `follow_up` = Follow Up Call, `after_close_call` = After Close Call.
- **User / owner**: a Pipedrive user (sales rep) who owns deals and is assigned activities.

## 5. Current state

Every model below is built, documented and tested.

### Sources
`models/staging/pipedrive/_pipedrive__sources.yml`: source `pipedrive`, 6 tables, every column with `data_type`, Elementary `schema_changes_from_baseline`, key and value contract tests on the full table (static load), freshness as in §3.

### Staging (`stg_pipedrive` schema, views)
| Model | Grain | Notes |
|---|---|---|
| `stg_pipedrive__activities` | (`activity_id`, `deal_id`) | `activity_id` alone is not unique; `is_done` = `coalesce(done, false)` |
| `stg_pipedrive__activity_types` | `activity_type_id` | `activity_type` also unique; `is_activity_type_active` from Yes / No only |
| `stg_pipedrive__deal_changes` | (`deal_id`, `changed_at`, `changed_field_key`) | `new_value` typed by key: `new_value_integer` / `new_value_timestamp`, after a format check; `where`-limited relationship tests per key |
| `stg_pipedrive__fields` | `field_id` | `field_value_options` jsonb |
| `stg_pipedrive__stages` | `stage_id` | names cased with `capitalize_words`; pair test against the stage picklist |
| `stg_pipedrive__users` | `user_id` | names and emails not unique; email case kept; `is_valid_email` |

### Intermediate (`int_pipedrive` schema)
| Model | Grain | Notes |
|---|---|---|
| `int_deal_changes_filtered_to_creations` | (`deal_id`, `changed_at`) | `add_time` rows; `created_at`; incremental event pattern |
| `int_deal_changes_filtered_to_stages` | (`deal_id`, `changed_at`) | `stage_id` rows; incremental event pattern; no names stored |
| `int_deal_changes_filtered_to_owners` | (`deal_id`, `changed_at`) | `user_id` rows as `owner_user_id`; incremental event pattern |
| `int_deal_changes_filtered_to_losses` | (`deal_id`, `changed_at`) | `lost_reason` rows as `lost_reason_id`; incremental event pattern; a reason edit or re-loss adds a row |
| `int_deal_losses_joined_to_stages` | (`deal_id`, `changed_at`) | stage at loss = latest stage change at or before the loss (ranked join) |
| `int_deal_stage_changes_aggregated_to_entries` | (`deal_id`, `stage_id`) | first entry per deal and recorded stage |
| `int_deals` | `deal_id` | the deal list: creation, first recorded / current owner, current / furthest stage, latest loss, counts, `has_multiple_creations` |
| `int_funnel_steps_mapped` | `funnel_step` | the only place stages and activity types are mapped to steps and named |
| `int_deal_funnel_steps_unioned` | (`deal_id`, `funnel_step`) | all funnel rules (§7); stage steps `union all` call steps |
| `int_activities_joined_to_types` | (`activity_id`, `deal_id`) | activities with `activity_type_id`, name and active state |
| `int_activities_filtered_to_done` | (`activity_id`, `deal_id`) | done activities with `has_known_deal` |
| `int_users` | `user_id` | incremental `merge`; hand-written delete `post_hook` |
| `int_fields_unnested_to_options` | (`field_key`, `option_id`) | picklist options; lost-reason names |

### Marts (`pipedrive_analytics` schema, tables, enforced contracts)
| Model | Grain | Notes |
|---|---|---|
| `dim_deals` | `deal_id` | `int_deals` plus current owner, stage and lost-reason names |
| `dim_users` | `user_id` | no `email` (personal data) |
| `dim_stages` | `stage_id` | |
| `dim_lost_reasons` | `lost_reason_id` | `lost_reason_name` |
| `dim_activity_types` | `activity_type_id` | `activity_type` also unique (funnel mapping key) |
| `dim_funnel_steps` | `funnel_step` | from `int_funnel_steps_mapped` |
| `fct_deal_stage_changes` | (`deal_id`, `changed_at`) | stage changes with current `stage_name`; no time in stage |
| `fct_deal_losses` | (`deal_id`, `lost_at`) | losses with `lost_reason_name` and stage at loss |
| `fct_deal_events` | (`deal_id`, `changed_at`, `event_type`) | `union all` timeline of every change-log row; sparse columns per type |
| `fct_deal_funnel_steps` | (`deal_id`, `funnel_step`) | from `int_deal_funnel_steps_unioned` |
| `fct_activities` | (`activity_id`, `deal_id`) | done activities only |
| `rep_sales_funnel_monthly` | (`month`, `funnel_step`) | the brief's report, exactly its four columns; full month × step grid |

Exposure: `sales_funnel_monthly` in `models/marts/_marts__exposures.yml` (type `analysis`; switch to `dashboard` + `url` when one exists). One schema for all marts.

## 6. Data findings that shape the design

Numbers live in the analyses; rerun them before relying on a finding.

- **Activities barely link to deals**: almost no activity `deal_id` exists in `deal_changes`, and the few matches look like chance. So the call steps are a separate population. Evidence: `analyses/profile_activity_deal_linkage.sql`.
- **Skipped stages are common.** Evidence: `analyses/profile_stage_skips.sql`, `analyses/profile_funnel_entered_vs_reached.sql`.
- **Every deal's first stage change is to stage 1**, usually weeks after its creation. Evidence: `analyses/profile_first_stage_and_lead_lag.sql`, `analyses/profile_creations_vs_lead_generation_by_month.sql`.
- **A few deal IDs carry two deals each** (two creations, two interleaved lifecycles, the first deal not dropped): an ID collision. They are the only deals with backward moves or revisits. Evidence: `analyses/profile_shared_deal_ids_timeline.sql`, `analyses/profile_shared_deal_ids_time_of_day.sql`, `analyses/profile_shared_deal_ids_first_deal_not_dropped.sql`.
- **No edited creation dates** in the data (an edited date shows 12:00 AM in Pipedrive). Evidence: `analyses/profile_edited_creation_dates.sql`; warning test `assert_no_edited_creation_dates`.
- **Some `activity_id`s are reused** on a second deal. Evidence: `analyses/profile_staging_grains.sql`.
- **Timestamps carry no timezone**; they are UTC (Pipedrive's API uses UTC) and are not converted.
- **`due_at` is the only activity date**: the planned date, not a confirmed completion time.
- **The source has no won status**: deals usually end lost, even after onboarding. Evidence: `analyses/profile_stage_at_loss.sql`.

## 7. Decisions

| Topic | Decision |
|---|---|
| Skipped stages | **Cumulative**: a deal reaches stage step N at its first entry into stage N or any later stage, so a 1 → 3 deal counts in step 2, dated by its stage 3 entry. `int_deal_stage_changes_aggregated_to_entries` keeps the recorded entries; the rule lives in `int_deal_funnel_steps_unioned` |
| Re-entries | A stage counts once per deal, at its first entry |
| Shared deal IDs | Excluded from the funnel only (`int_deal_funnel_steps_unioned`); kept and flagged (`has_multiple_creations`) everywhere else; not split. `created_at` = earliest creation |
| Call deals | Every deal with a done call counts, whether or not it is in `deal_changes`; `has_known_deal` flags the linked ones |
| Done calls | A Sales Call counts only when done (`is_done = true`) |
| Call month | The month of `due_at` (the planned date) |
| Empty months | The report shows every month × step of the data period, with 0 where no deal reached a step |
| Report month spine | `rep_sales_funnel_monthly` generates its months itself (`generate_series` over the data period), with no `dim_months`. Trade-off: no shared calendar and no `is_partial_month`. The build-mart-model skill states the same rule |
| Losses | A loss doesn't remove a deal from the steps it reached |
| Owner at creation | Not in the data: `int_deals` exposes `first_recorded_owner_user_id`, named for what it is |
| Names in event tables | Append tables store IDs only; current names are joined in the marts at build time |
| Edited creation dates | Not handled yet (none in the data). If the warning test fires: keep `recorded_created_at` and `edited_created_date` plus `has_edited_creation_date` in `int_deals`, and don't count the edit as a second creation |
| Marts | Tables in `pipedrive_analytics`, enforced contracts, none incremental |
| Cohort report | Includes the call steps (they fill in if the IDs line up in future data) |

Each decision is stated in plain words in the description of the model that applies it.

## 8. Data flow

```
stg_pipedrive__deal_changes ─┬─> int_deal_changes_filtered_to_creations ─┐
                             ├─> int_deal_changes_filtered_to_stages ────┼─> int_deal_stage_changes_aggregated_to_entries ─┐
                             ├─> int_deal_changes_filtered_to_owners ────┤                                                  │
                             └─> int_deal_changes_filtered_to_losses ────┼─> int_deal_losses_joined_to_stages               │
                                                                         └─> int_deals (shared-ID flag) ───────────────────┤
stg_pipedrive__stages + stg_pipedrive__activity_types ──> int_funnel_steps_mapped ─────────────────────────────────────────┤
stg_pipedrive__activities ──> int_activities_joined_to_types ──> int_activities_filtered_to_done ──────────────────────────┴─> int_deal_funnel_steps_unioned
int_deal_funnel_steps_unioned ──> fct_deal_funnel_steps ──> rep_sales_funnel_monthly
stg_pipedrive__users ──> int_users ──> dim_users
stg_pipedrive__fields ──> int_fields_unnested_to_options ──> dim_lost_reasons
```

Design rules:

- **Combine stage events and call events with `union all`, never a join**: a join between them fans out and keeps almost nothing.
- **Facts are never joined to each other** on `deal_id` / `changed_at`: their timestamps don't coincide, and a `deal_id`-only join fans out. Cross-event questions get their own model: an as-of rule (`int_deal_losses_joined_to_stages`) or a timeline (`fct_deal_events`).
- The funnel step mapping lives only in `int_funnel_steps_mapped`; no mart remaps anything.
- Join activities on (`activity_id`, `deal_id`), users on `user_id` only.
- Models whose rows change when new events arrive (`int_deals`, the funnel) are rebuilt as tables.

## 9. Report requirements (`rep_sales_funnel_monthly`)

- Exactly the columns `month`, `kpi_name`, `funnel_step`, `deals_count`, in that order.
- `contract: enforced: true`: `month date`, `kpi_name character varying(100)`, `funnel_step character varying(10)`, `deals_count integer`, each `not_null`.
- Tests: grain `unique_combination_of_columns` on (`month`, `funnel_step`); `accepted_values` on `funnel_step` and `kpi_name`; `deals_count >= 0`; singular tests `assert_rep_sales_funnel_monthly_complete_grid` and `assert_rep_sales_funnel_monthly_reconciles`.

## 10. Done when

- [ ] Every finding in §6 has its query in `analyses/`
- [ ] SQL follows the efficiency rules in §2
- [ ] README up to date (setup, `dbt run` then `dbt test`, docs and Elementary report, layer overview)
- [ ] Every decision in §7 stated in the descriptions of the models that apply it
- [ ] `dbt run` then `dbt test` over the whole project: every model built; test results reported with counts, intentional failures explained
- [ ] Row counts reconciled at every grain change; spot checks on a deal that skipped a stage, a shared deal ID and a linked activity deal
- [ ] Commits and the PR only when the user asks, per the commit rule
