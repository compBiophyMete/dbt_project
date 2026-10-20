"""
Airflow DAGs that refresh the dbt project by schedule tag.

One DAG per schedule tag (`daily`, `12h`, `hourly`: the schedule tags allowed by the project's
documentation rule). A model is refreshed by the DAG of the schedule tag in its `config.tags`:

    1. source_freshness     `dbt source freshness --select tag:pipedrive`. Reports stale sources but
                            never blocks the run (the static data is always stale; see the source
                            description's Freshness assumption).
    2. incremental_refresh  `dbt run --select tag:<schedule>,tag:incremental`: the models tagged with the
                            schedule *and* `incremental` (intersection). dbt applies their incremental
                            logic (lookback window, append / merge), so only new rows are processed.
                            Example: `daily` + `incremental` → int_users and the int_deal_changes_* models,
                            refreshed incrementally once a day.
    3. refresh              `dbt run --select tag:<schedule>+ --exclude tag:incremental`: every other model
                            tagged with the schedule, plus everything downstream of the schedule's models
                            (`+`), so the marts built on the incremental models are rebuilt after them.
                            Incremental models are excluded here because step 2 already ran them.
    4. test                 `dbt test` on the refreshed models plus everything upstream of them
                            (`+tag:<schedule>+`), so the source contract tests and the staging tests run too. Test *failures* (exit code 1: e.g. the known
                            data issues that fail on purpose, no thresholds) don't fail the task, so the
                            run finishes green; dbt crashing (exit code 2+, e.g. no database connection)
                            does. The results are saved per run for the next task.
    5. report_test_failures Reads the saved `run_results.json` and logs every failed test with its failure
                            count, so failures are reported separately from the run's status. Fails only
                            when a test *errored* (couldn't run, e.g. a compilation error or a missing
                            relation), because then the data wasn't checked at all.

`dbt run` then `dbt test` as separate steps, never `dbt build`: a failing test must not skip
downstream models (project rule).

A DAG is only scheduled when at least one model carries its tag; the tasks of an unused schedule
would select nothing. Today only `daily` is in use.

Configuration (environment of the Airflow workers, never hard-coded here):
    DBT_PROJECT_DIR     path of this dbt project on the worker (default: /opt/airflow/dbt_project)
    DBT_EXECUTABLE      dbt binary (default: dbt)
    DBT_TYPE, DBT_HOST, DBT_PORT, DBT_USER, DBT_PASSWORD, DBT_DATABASE, DBT_SCHEMA, DBT_THREADS
                        read by profiles.yml; set them as worker environment variables or from an
                        Airflow connection / secrets backend.
"""

import json
import logging
import os
from datetime import datetime, timedelta

from airflow import DAG

try:  # Airflow 3
    from airflow.providers.standard.operators.bash import BashOperator
    from airflow.providers.standard.operators.python import PythonOperator
except ImportError:  # Airflow 2
    from airflow.operators.bash import BashOperator
    from airflow.operators.python import PythonOperator


DBT_PROJECT_DIR = os.environ.get("DBT_PROJECT_DIR", "/opt/airflow/dbt_project")
DBT = os.environ.get("DBT_EXECUTABLE", "dbt")
PROJECT_TAG = "pipedrive"

# schedule tag → cron (UTC). Keep in line with the schedule tags of the documentation rule.
SCHEDULES = {
    # 03:00 UTC. Assumption: the raw Pipedrive source data is refreshed daily at 02:00 UTC, so the
    # DAG runs an hour after the load; move the cron with the load. The lookback macro widens the
    # window on Mondays.
    "daily": "0 3 * * *",
    "12h": "0 3,15 * * *",
    "hourly": "0 * * * *",
}
ACTIVE_SCHEDULES = {"daily"}    # tags at least one model carries today; add a tag here when it is used

DEFAULT_ARGS = {
    "owner": "data",
    "retries": 1,
    "retry_delay": timedelta(minutes=10),
}


def dbt_command(*args: str) -> str:
    """A dbt command run from the project directory, with profiles.yml read from the project root."""
    return f"cd {DBT_PROJECT_DIR} && {DBT} {' '.join(args)} --profiles-dir {DBT_PROJECT_DIR}"


def test_results_path(run_id_template: str) -> str:
    """Where a run's test results are kept, so a later dbt command can't overwrite them."""
    return f"{DBT_PROJECT_DIR}/target/test_results_{run_id_template}.json"


def report_test_failures(results_path: str) -> dict:
    """Log every failed test of the run; fail only when a test errored (didn't run)."""
    with open(results_path) as f:
        results = json.load(f)["results"]

    failed = [r for r in results if r["status"] == "fail"]
    errored = [r for r in results if r["status"] == "error"]
    passed = sum(r["status"] == "pass" for r in results)
    warned = sum(r["status"] == "warn" for r in results)

    log = logging.getLogger(__name__)
    log.info("dbt test: %d passed, %d warned, %d failed, %d errored", passed, warned, len(failed), len(errored))
    for r in failed:
        log.warning("FAIL  %-90s %s failing rows", r["unique_id"], r.get("failures"))
    for r in errored:
        log.error("ERROR %-90s %s", r["unique_id"], r.get("message"))

    if errored:
        raise RuntimeError(f"{len(errored)} dbt test(s) errored and didn't check the data; see the log above")
    return {"passed": passed, "warned": warned, "failed": len(failed), "errored": len(errored)}


def build_dag(schedule_tag: str, cron: str) -> DAG:
    incremental = f'"tag:{schedule_tag},tag:incremental"'
    downstream = f'"tag:{schedule_tag}+"'
    with_upstream = f'"+tag:{schedule_tag}+"'   # tests also cover the sources and staging views feeding the run

    with DAG(
        dag_id=f"dbt_{PROJECT_TAG}_{schedule_tag}_refresh",
        description=f"Refresh dbt models tagged '{schedule_tag}' (incremental first, then the rest)",
        schedule=cron,
        start_date=datetime(2026, 10, 1),
        catchup=False,
        max_active_runs=1,          # incremental models must not load the same window twice in parallel
        default_args=DEFAULT_ARGS,
        tags=["dbt", PROJECT_TAG, schedule_tag],
    ) as dag:
        source_freshness = BashOperator(
            task_id="source_freshness",
            bash_command=dbt_command("source", "freshness", "--select", f"tag:{PROJECT_TAG}"),
        )

        incremental_refresh = BashOperator(
            task_id="incremental_refresh",
            bash_command=dbt_command("run", "--select", incremental),
            trigger_rule="all_done",  # a stale source is reported by source_freshness, not a reason to skip
        )

        refresh = BashOperator(
            task_id="refresh",
            bash_command=dbt_command("run", "--select", downstream, "--exclude", "tag:incremental"),
        )

        results_path = test_results_path("{{ run_id | replace(':', '_') | replace('+', '_') }}")

        # exit code 1 = test failures (reported by the next task); 2+ = dbt itself failed
        test = BashOperator(
            task_id="test",
            bash_command=(
                dbt_command("test", "--select", with_upstream)
                + f"; code=$?; cp {DBT_PROJECT_DIR}/target/run_results.json {results_path}"
                + "; if [ $code -ge 2 ]; then exit $code; fi"
            ),
        )

        report = PythonOperator(
            task_id="report_test_failures",
            python_callable=report_test_failures,
            op_kwargs={"results_path": results_path},
        )

        source_freshness >> incremental_refresh >> refresh >> test >> report

    return dag


for _tag, _cron in SCHEDULES.items():
    if _tag in ACTIVE_SCHEDULES:
        globals()[f"dbt_{PROJECT_TAG}_{_tag}_refresh"] = build_dag(_tag, _cron)
