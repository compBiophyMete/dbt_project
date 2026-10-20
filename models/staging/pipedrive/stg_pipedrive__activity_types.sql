with

source as (

    select
        {{ dbt_utils.star(from=source('pipedrive', 'activity_types')) }}
    from
        {{ source('pipedrive', 'activity_types') }}

),

renamed as (

    select
        id                                      as activity_type_id,
        lower(nullif(trim(type), ''))           as activity_type,
        {{ capitalize_words("nullif(trim(name), '')") }} as activity_type_name,
        -- only Yes / No are known states; anything else (null, empty, 'Maybe') stays null and fails not_null
        case
            when lower(trim(active)) = 'yes' then true
            when lower(trim(active)) = 'no' then false
        end                                     as is_activity_type_active
    from
        source

)

select
    activity_type_id,
    activity_type,
    activity_type_name,
    is_activity_type_active
from
    renamed
