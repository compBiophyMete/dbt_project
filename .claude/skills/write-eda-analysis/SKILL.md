---
name: write-eda-analysis
description: Write an exploratory data analysis (EDA) as a dbt analysis in analyses/ — one question per file, with a header stating the question, the run command, the result with the date of the run, and the conclusion, so every data finding the project relies on can be rerun by a reviewer. Use when asked to profile, explore, investigate or analyse the data, to save a finding or profiling query, to back a claim in a model description with evidence, or to add/update an EDA or analysis.
argument-hint: "[question to answer — e.g. 'how often are stages skipped?']"
---

# Write an EDA analysis

Goal: every data finding the project relies on (findings in descriptions, decisions in the task file, edge cases) is backed by a saved query that anyone can rerun and get the same answer. A finding that exists only in a chat or a description can't be checked.

**The analysis is the only home for the numbers.** Model descriptions describe a finding in words and point here (source descriptions report no findings at all); they never carry counts, data date ranges or "profiled <date>" (rule: "No counts or profiling results in documentation" in `.claude/rules/dbt-documentation-testing.md`). So the dated result in this header is what a reviewer compares a failing test against.

## Non-negotiables

1. **One question per file.** A file answers exactly one question and returns **one result set**. Two questions → two files.
2. **The result in the header is the query's real output.** Run the query (`dbt show` / MCP `mcp__dbt__show`) **before** writing the header, and copy the numbers from that run. Never write a result from memory, from a model description or from an earlier conversation.
3. **Read-only.** Only `select`; read with `{{ ref() }}` / `{{ source() }}`, never a hard-coded schema or table name. Analyses are compiled, never built, so they never change the warehouse.
4. **Data findings only.** An EDA states what the data shows. Claims about how Pipedrive works belong to the `verify-api-assumptions` skill (quoted, linked sources), not here.
5. **No business decision is made in an EDA.** The conclusion says what the data shows and which model or decision it supports; a new rule still goes through the user (`.claude/rules/challenge-modeling-requests.md`).

## The header (mandatory, in this order)

Every file starts with a `/* … */` block:

```sql
/*
    Question: <one sentence, ending with a question mark>

    Run: dbt show --select <file name without .sql> --limit <n>

    Result (run <YYYY-MM-DD>):
    - <the numbers, copied from the run: a short list or a small table>

    Conclusion: <what the result means, in one or two sentences>

    Relied on by: <models, columns, tests, task-file decisions or descriptions that use this finding>
*/
```

- **Question**: specific and answerable by the query ("How often do deals skip a stage?", not "Stage analysis").
- **Run**: the exact command. `--limit` must be large enough to show every row of the result (dbt `show` defaults to 5).
- **Result**: dated with the day the query was run. Show the numbers a reader needs to check the conclusion; for a long result (a transition matrix), the totals plus the notable rows.
- **Conclusion**: the answer to the question, plus what it does *not* show if that matters (e.g. "all 10 backward moves are on the 5 shared IDs; no normal deal moves backwards").
- **Relied on by**: so a reader can go from the evidence to the model, and back.

## Procedure

1. **Check for an existing analysis** answering the same question (`ls analyses/`). Update it rather than adding a near-duplicate.
2. **Write the query**: CTEs per the project SQL style (lowercase, one column per line, comments for any non-obvious step). Prefer the model that holds the concept (e.g. `int_deal_stage_changes_aggregated_to_entries` for stage entries) over re-deriving it from staging.
3. **Run it** with `dbt show` (`mcp__dbt__show` in Claude Code: paste the SQL; the `ref()`s resolve). Check that the result answers the question; if not, fix the query, not the header.
4. **Write the header** from that run's output, with today's date.
5. **Name the file** `profile_<subject>.sql` (e.g. `profile_stage_skips.sql`); one subject, snake_case.
6. **Link it**: where a model description states the finding, it must cite the analysis (`Evidence: analyses/profile_stage_skips.sql`), and the analysis's "Relied on by" names that model or test. Don't copy the numbers into the description.
7. **Re-running later**: when the data changes, rerun, and update the result, its date and, if needed, the conclusion together. A result without its date is incomplete.

## Done when

- [ ] One question, one result set, one file named `profile_<subject>.sql` in `analyses/`
- [ ] Header in order: Question, Run, Result (run date), Conclusion, Relied on by
- [ ] Every number in the result was copied from a run of this exact query on the stated date
- [ ] Only `ref()` / `source()`, only `select`; `dbt parse` is clean
- [ ] No Pipedrive-behaviour claim (that's `verify-api-assumptions`) and no new business rule
