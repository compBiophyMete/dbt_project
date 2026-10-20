{# ---------- Intermediate: column docs shared across area folders ---------- #}

{% docs dwh_date %}
When the row was last written to the table (`timestamp with time zone`): the start time of the
dbt run (`run_started_at`, UTC) that inserted or last updated it.
{% enddocs %}
