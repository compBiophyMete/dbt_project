with

source as (

    select
        {{ dbt_utils.star(from=source('postgres_public', 'fields')) }}
    from
        {{ source('postgres_public', 'fields') }}

),

renamed as (

    select
        id                                      as field_id,
        lower(nullif(trim(field_key), ''))      as field_key,
        {{ capitalize_words("nullif(trim(name), '')") }} as field_name,
        field_value_options
    from
        source

)

select
    field_id,
    field_key,
    field_name,
    field_value_options
from
    renamed
