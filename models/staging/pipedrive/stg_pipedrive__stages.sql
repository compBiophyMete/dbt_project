with

source as (

    select
        {{ dbt_utils.star(from=source('postgres_public', 'stages')) }}
    from
        {{ source('postgres_public', 'stages') }}

),

renamed as (

    select
        stage_id,
        {{ capitalize_words("nullif(trim(stage_name), '')") }} as stage_name
    from
        source

)

select
    stage_id,
    stage_name
from
    renamed
