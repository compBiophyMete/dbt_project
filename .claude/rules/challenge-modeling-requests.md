# Challenge Modeling Requests

Use this rule for every request that creates or changes a dbt model, source, seed, test or its YAML. The user wants to be **challenged against modeling best practice** (dbt's official documentation, the rules in this folder, the layer skills and the task file's decisions), not just obeyed.

## Sources of best practice (mandatory)

- **External best practice comes from the official dbt documentation only**: `docs.getdbt.com`, including its best-practice guides (e.g. [How we structure our dbt projects](https://docs.getdbt.com/best-practices/how-we-structure/1-guide-overview)) and reference pages.
- Open the page in the session (`WebFetch`), quote the relevant sentence and link it. Never cite a dbt practice from memory.
- No blogs, community posts, vendor articles, AI-written explainers or books as the authority for a challenge. If the dbt docs don't cover the point, say so and argue from the data and the project's own rules and decisions instead.

## Procedure (mandatory)

1. **Check before building.** Compare the request with the layer's non-negotiables and with the warning signs listed in the layer skill (`onboard-raw-source`, `build-staging-model`, `build-intermediate-model`, `build-mart-model`), and with the decisions in the task file (`.claude/tasks/*.md`).
2. **If it fits, say so in one line and proceed.** Don't invent objections. A request that matches best practice needs no debate.
3. **If it conflicts, prove it with data, not theory.** Run read-only profiling (`dbt show` / MCP `mcp__dbt__show`) that shows the consequence: rows that match or don't, fan-out counts, rows lost, a result that would change from day to day. "The join on `changed_at` matches 0 rows" convinces; "joining facts is discouraged" alone doesn't.
4. **Then state, briefly:**
   - **the concern**: what goes wrong, with the numbers;
   - **the principle**: which practice it breaks, with its source: a quoted, linked dbt documentation page, or a project rule or decision;
   - **the alternative**: the best-practice way to reach the user's goal, at the right layer.
5. **The user decides.** If they still want their version:
   - implement it as asked; don't substitute your own design;
   - write the trade-off into the model's description (and a `TODO` in the SQL when a better path is planned, e.g. "check against `int_deals` once it exists"), so the next reader sees why it's built this way;
   - record the decision in the task file.
6. **Never comply silently, never deviate silently.** Building something you believe is wrong without saying so, and building something other than what was asked without saying so, are both failures.
7. **"Evaluate, don't implement" means evaluate only.** Profile and explain; change no files.

## What a good challenge looks like

> **Concern**: joining `int_deal_changes_filtered_to_stages` to `int_activities_filtered_to_done` on `deal_id` keeps 2 of 1,128 done sales calls: activity deal IDs barely exist in the change log.
> **Principle**: funnel steps from different sources are stacked with `union all`, one row per deal and step (task file, design rules); a join on `deal_id` alone between two event tables multiplies or drops rows.
> **Alternative**: `int_deal_funnel_steps_unioned` = stage entries `union all` done sales calls, one row per deal and funnel step.

Keep it short: a few lines and a table of numbers, not an essay. The goal is a better model, not winning the argument.
