with

fields as (

    select
        field_id,
        field_key,
        field_name,
        field_value_options
    from {{ ref('stg_pipedrive__fields') }}

),

-- one row per element of the field_value_options array; fields without options (null) yield no rows
unnested as (

    select
        fields.field_id,
        fields.field_key,
        fields.field_name,
        options.option ->> 'id'                 as raw_option_id,
        options.option ->> 'label'              as raw_option_label
    from fields
    cross join lateral jsonb_array_elements(fields.field_value_options) as options (option)

),

typed as (

    select
        field_id,
        field_key,
        trim(raw_option_id)::integer    as option_id,
        field_name,
        {{ capitalize_words("nullif(trim(raw_option_label), '')") }} as option_label
    from unnested

)

select
    field_key,
    option_id,
    field_id,
    field_name,
    option_label
from typed
