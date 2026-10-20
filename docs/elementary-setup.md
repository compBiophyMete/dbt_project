# Elementary setup

How to generate the Elementary observability report: test results with failing-row samples, run history and lineage, as one HTML page. See the [README](../README.md#documentation-and-observability) for what it shows.

The Elementary dbt package (in `packages.yml`) already logs every dbt run and test into the `<DBT_SCHEMA>_elementary` schema. The report is built from those tables by the Elementary CLI, which is installed separately.

## 1. Install the CLI

Use the same version as the dbt package in [`packages.yml`](../packages.yml):

```bash
.venv/bin/pip install 'elementary-data[postgres]==0.20.1'
```

## 2. Create the connection profile

The CLI reads its own profile from `.edr/profiles.yml`. The file is git-ignored, so create it on every fresh clone. It contains no secrets: it reads the same `DBT_*` variables as dbt (see [Configure credentials](../README.md#configure-credentials)).

```yaml
elementary:
  target: default
  outputs:
    default:
      type: "{{ env_var('DBT_TYPE') }}"
      host: "{{ env_var('DBT_HOST') }}"
      port: "{{ env_var('DBT_PORT') | as_number }}"
      user: "{{ env_var('DBT_USER') }}"
      password: "{{ env_var('DBT_PASSWORD') }}"
      dbname: "{{ env_var('DBT_DATABASE') }}"
      schema: "{{ env_var('DBT_SCHEMA') }}_elementary"
      threads: "{{ env_var('DBT_THREADS') | as_number }}"
```

## 3. Generate and open the report

From the repository root, in a terminal where your credentials are exported:

```bash
.venv/bin/dbt run                              # builds every model
.venv/bin/dbt test                             # runs every test; Elementary logs the results
.venv/bin/edr report --profiles-dir .edr       # writes edr_target/elementary_report.html
open edr_target/elementary_report.html         # macOS; xdg-open on Linux, start on Windows
```

If `dbt test` reports failures, the report shows each one with its failing rows. Re-run these steps whenever you want fresh results. The report is built from your own database, so it is not committed.
