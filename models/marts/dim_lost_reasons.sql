with

-- the lost-reason picklist: option_id is unique per field_key, so one row per reason
lost_reasons as (

    select
        option_id                               as lost_reason_id,
        option_label                            as lost_reason_name
    from
        {{ ref('int_fields_unnested_to_options') }}
    where
        field_key = 'lost_reason'

)

select
    lost_reason_id,
    lost_reason_name::varchar(255)             as lost_reason_name
from
    lost_reasons
