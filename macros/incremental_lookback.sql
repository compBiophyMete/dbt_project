{#
    Lookback windows for incremental models. Documented in macros/incremental_lookback.yml.

    lookback_days() decides how many days a run re-reads; incremental_lookback_filter() renders the
    window predicate. Call the filter inside the model's own {% if is_incremental() %} block, so the
    model shows which runs are incremental.
#}

{% macro lookback_days(default_days, weekly_days=none, weekly_weekday=0) -%}

    {#- 1. an explicit --vars '{lookback_days: N}' wins, e.g. for a one-off backfill -#}
    {%- if var('lookback_days', none) is not none -%}
        {{ return(var('lookback_days') | int) }}
    {%- endif -%}

    {#- 2. the weekly re-check: weekly_days on the given weekday (0 = Monday, UTC run start) -#}
    {%- if weekly_days is not none and run_started_at.weekday() == weekly_weekday -%}
        {{ return(weekly_days | int) }}
    {%- endif -%}

    {#- 3. otherwise the model's default window -#}
    {{ return(default_days | int) }}

{%- endmacro %}


{% macro incremental_lookback_filter(column, default_days, weekly_days=none, weekly_weekday=0) -%}

    {%- set days = lookback_days(default_days, weekly_days, weekly_weekday) -%}

    {#- one column for the filter and the watermark, so both compare the same clock.
        coalesce: on an empty table max() is null, and the window would select nothing -#}
    {{ column }} >= (
        select coalesce(max({{ column }}), '-infinity'::timestamp)
        from {{ this }}
    ) - interval '{{ days }} days'

{%- endmacro %}
