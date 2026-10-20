{# incremental loads only add and update rows; the post_hook removes users that no longer exist upstream #}
{{
    config(
        post_hook="{{ delete_rows_missing_upstream(ref('stg_pipedrive__users'), ['user_id']) }}"
    )
}}

with

-- incremental runs read only users modified within 2 days (8 on Mondays, UTC) of the latest modified_at already loaded
users as (

    select
        user_id,
        user_name,
        email,
        is_valid_email,
        modified_at
    from {{ ref('stg_pipedrive__users') }}
    {% if is_incremental() %}
    where {{ incremental_lookback_filter('modified_at', default_days=2, weekly_days=8) }}
    {% endif %}

)

select
    user_id,
    user_name,
    email,
    is_valid_email,
    modified_at,
    -- start of the dbt run that last inserted or replaced this row
    cast('{{ run_started_at }}' as timestamp with time zone) as dwh_date
from users
