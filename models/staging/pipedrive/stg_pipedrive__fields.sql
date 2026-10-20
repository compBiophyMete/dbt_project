with

source as (

    select
        {{ dbt_utils.star(from=source('pipedrive', 'fields')) }}
    from
        {{ source('pipedrive', 'fields') }}

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
