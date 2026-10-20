with

stages as (

    select
        stage_id,
        stage_name
    from
        {{ ref('stg_pipedrive__stages') }}

)

select
    stage_id,
    stage_name::varchar(255)                    as stage_name
from
    stages
