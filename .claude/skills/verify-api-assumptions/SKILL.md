---
name: verify-api-assumptions
description: Research the Pipedrive API and product behaviour behind this project and check every assumption the models make about it (deal IDs, owners at creation, change log contents, lost / reopened / deleted / merged deals, activity flags, stage order, timestamps) against what Pipedrive's own documentation, Pipedrive's official developer forum and Stack Overflow actually say. Evidence only from those sources, quoted with links, never invented and never from AI-generated or third-party pages. Use when asked to verify, fact-check, research or validate assumptions about the Pipedrive API, the source data's meaning, or "is this how Pipedrive really works?".
argument-hint: "[assumption(s) to check — default: every assumption in the inventory]"
---

# Verify API assumptions against the real Pipedrive documentation

Goal: every statement the project makes about **how Pipedrive works** (as opposed to what the data shows) is backed by a quoted, linked statement from an allowed source, or is clearly marked as unverified. The output is one report, kept in its final state, that a reviewer can check link by link.

Data findings (counts, patterns profiled with `dbt show`) are **not** in scope: they are facts about this dataset. This skill checks the **product and API behaviour** the models rely on to interpret that data.

## Non-negotiables

1. **Nothing is invented.** Every claim in the report is a short **verbatim quote** from a page that was actually opened in this session (`WebFetch`), with its **URL** and the **date accessed**. Never fill a gap from memory, from training knowledge, or by "it's well known that…". If no allowed source says it, the verdict is **Not documented**, and that's a valid, useful result.
2. **Allowed sources only.** Search with `WebSearch` using `allowed_domains`, and cite only pages on these domains:

   | Source | Domains | What it is |
   |---|---|---|
   | Pipedrive developer documentation | `developers.pipedrive.com`, `pipedrive.readme.io` | the API reference (v1 / v2), field definitions, tutorials, changelog |
   | Pipedrive OpenAPI spec | `github.com/pipedrive` (official organisation only) | the machine-readable form of the API |
   | Pipedrive knowledge base | `support.pipedrive.com` | product behaviour (lost / reopened / deleted / merged deals, owners) |
   | Pipedrive developer forum | `devcommunity.pipedrive.com` | Pipedrive's official community; prefer answers by **Pipedrive staff** |
   | Stack Overflow | `stackoverflow.com` | questions tagged `pipedrive-api` |

3. **No AI-generated or third-party content.** Excluded even when it ranks first: integration / connector docs (WSO2, Windmill, Workato, Paragon, Make, Zapier …), "knowledge" aggregators and AI-written explainers (withone.ai, getmembrane.com, bardeen.ai, guideflow, timelines.ai …), blogs, Medium, LLM chat transcripts, PyPI wrapper READMEs. On allowed domains, also discard a post that is evidently AI-generated (Stack Overflow bans them; a forum post that reads like a generic chatbot answer with no account-specific detail is excluded). When in doubt, exclude it and say so.
4. **Rank the evidence; label every quote with its type.**
   1. **Official reference** (API reference, OpenAPI spec): strongest.
   2. **Official explanation** (knowledge base, Pipedrive tutorial, staff forum answer).
   3. **Community** (non-staff forum post, Stack Overflow answer): note its score / accepted state and date; never the only basis for **Confirmed**.
5. **Date and version every quote.** API behaviour changes (v1 vs v2, deprecations). Record the API version the page describes and, for forum / Stack Overflow posts, the post date. A quote older than a documented change can't confirm current behaviour.
6. **Field names across API versions: name both, rename nothing.** When an allowed source shows a Pipedrive field renamed between API versions (e.g. the deal owner `user_id` in v1 → `owner_id` in v2; the activity flag `is_active` in v1 → `is_deleted`, negated, in v2, per the [v2 migration guide](https://pipedrive.readme.io/docs/pipedrive-api-v2-migration-guide)), the proposed description change names **both** names, says which one this data uses, and links the source. **Never propose renaming a column** to the newer API name: the data keeps the names it arrives with.
7. **Read-only on the project.** The skill writes only its report. It never changes a model, test or description; it **proposes** changes, and the user decides (see `.claude/rules/challenge-modeling-requests.md`).

## Procedure

### 1. Build the assumption inventory

Collect every statement about **Pipedrive behaviour** from:
- `.claude/tasks/*.md` (decisions, §4 "Pipedrive terms", §6 findings);
- model and source descriptions: `grep -rn -i "pipedrive" models/` and the `_docs.md` doc blocks;
- comments in the SQL that justify a rule ("Pipedrive gives…", "in Pipedrive…").

Write each as one testable sentence, with **where the project relies on it**. Starting inventory (rebuild it every run, the project changes):

| # | Assumption | Relied on in |
|---|---|---|
| A1 | Deal IDs are never reused; a re-created deal gets a new ID | `int_deals` (`has_multiple_creations` = ID collision), the funnel's exclusion of shared deal IDs |
| A2 | Every deal has an owner from creation; `user_id` defaults to the creating / API user | `int_deals.first_recorded_owner_user_id` |
| A3 | The deal change log (flow / changelog) records later field changes, not the initial values set at creation | `first_recorded_owner_user_id`, owner and stage history |
| A4 | `add_time` is the deal's creation time, set once | `int_deal_changes_filtered_to_creations`, `created_at` |
| A5 | A lost deal can be reopened and lost again; a lost reason can be edited | `int_deal_changes_filtered_to_losses` (append), latest loss in `int_deals` |
| A6 | A deleted deal can be restored within 30 days and keeps its ID; after that it's gone | delete post-hooks of the event models |
| A7 | Merging deals keeps one deal (the survivor); the other is removed | delete post-hooks, A1 |
| A8 | An activity's `active_flag = false` means the activity is deleted | `int_activities_filtered_to_done` (no per-activity flag in the export) |
| A9 | An activity type's active flag only means the type can't be chosen for new activities | `int_activities_filtered_to_done`, `dim_activity_types` |
| A10 | `done` marks a completed activity; `due_date` / `due_time` is the planned date | done-only call steps, dated by `due_at` |
| A11 | The API has a completion time for activities (e.g. `marked_as_done_time`) that this export lacks | the choice of `due_at` as the activity date |
| A12 | Stage IDs follow pipeline order (or order is defined by a separate field such as `order_nr`) | cumulative rule (`stage_id >=`), `furthest_stage_id` |
| A13 | Deals have a status (open / won / lost) in the API that this export lacks | "every deal is lost", no won status |
| A14 | API timestamps are in UTC | "no timezone in the source, not converted" |

### 2. Search, allowed domains only

For each assumption:
- run `WebSearch` with `allowed_domains` set to the table in non-negotiable 2 (one search per domain group if needed), with the field names and endpoint words (`deals`, `flow`, `changelog`, `add_time`, `user_id`, `active_flag`, `marked_as_done_time`, `order_nr`, `status`);
- prefer the **API reference** first, then the knowledge base, then staff forum answers, then Stack Overflow;
- if a search returns nothing on the allowed domains, try one rephrasing; then stop and record **Not documented** with the queries used.

### 3. Open and quote

- `WebFetch` every page you cite, and ask it for the exact passage. Copy the quote **verbatim** (short: the sentence that settles the point). A search snippet alone is not evidence.
- Record: URL, page title, source type (rank 1 / 2 / 3), API version or post date, date accessed, quote.
- If the fetched page doesn't contain the claim the snippet suggested, discard it.

### 4. Judge each assumption

| Verdict | Meaning |
|---|---|
| **Confirmed** | an official source (rank 1 or 2) states it |
| **Partially confirmed** | official sources state part of it, or only for one API version |
| **Contradicted** | an allowed source states the opposite; quote it |
| **Community only** | only rank 3 sources support it; treat as unverified |
| **Not documented** | no allowed source addresses it (list the searches) |

Then the **impact on the project**: which model, column, test or description relies on it, and what would change if it's wrong. Propose the change; don't make it.

### 5. Write the report

Write `.claude/tasks/api-assumptions.md`, replacing the previous version (it holds the current verdicts only, no change log):

1. **Scope and sources**: the date of the run, allowed domains, what was excluded and why (list excluded domains that came up in searches).
2. **Summary table**: assumption, verdict, strongest source (link), how the project handles it.
3. **One section per assumption**: the assumption, where the project relies on it, each quote with URL, type, version / date and access date, the verdict, the proposed change (if any).
4. **Not documented**: the queries tried, so the next run doesn't repeat them blindly.
5. **Open proposals**: only the changes not yet decided, for the user to approve (decided ones are reflected in the summary's last column, not logged), e.g. reword a description, add a caveat, revisit a decision. A field renamed between API versions becomes "mention both names in the description" (non-negotiable 6), never "rename the column".

### 6. Report back

Tell the user, briefly: how many assumptions were checked, how many confirmed / contradicted / unverified, the contradictions first (with their quotes and links), and the proposed changes awaiting their decision. Link the report file.

## Done when

- [ ] The inventory was rebuilt from the task file, descriptions and SQL comments, each assumption with where it's relied on
- [ ] Every cited page is on an allowed domain, was opened with `WebFetch`, and is quoted verbatim with URL, type, version / date and access date
- [ ] No claim comes from memory, a search snippet alone, a third-party / connector page or AI-generated content
- [ ] Every assumption has a verdict; **Not documented** lists the searches tried
- [ ] Impacts and proposed changes are listed; fields renamed between API versions are proposed with both names and a link, never as a column rename; no project file other than the report was changed
- [ ] The report is saved under `.claude/tasks/` and summarized to the user, contradictions first
