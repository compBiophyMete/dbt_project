with

source as (

    select
        {{ dbt_utils.star(from=source('pipedrive', 'deal_changes')) }}
    from
        {{ source('pipedrive', 'deal_changes') }}

),

renamed as (

    select
        deal_id,
        lower(nullif(trim(changed_field_key), ''))  as changed_field_key,
        nullif(trim(new_value), '')                 as new_value,
        change_time::timestamp                                 as changed_at
    from
        source

)

select
    deal_id,
    changed_field_key,
    new_value,
    -- The key decides the expected type: add_time holds a timestamp, every other key an integer.
    -- The format is checked before casting, so bad data becomes null (and fails its not_null test)
    -- instead of breaking the view. \d{1,9} keeps out values too large for integer.
    case
        when changed_field_key <> 'add_time'
            and new_value ~ '^\d{1,9}$'
            then new_value::integer
    end                                             as new_value_integer,
    changed_at,
    case
        when changed_field_key = 'add_time'
            and new_value ~ '^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])T([01]\d|2[0-3]):[0-5]\d:[0-5]\d$'
            then new_value::timestamp
    end                                             as new_value_timestamp
from
    renamed
