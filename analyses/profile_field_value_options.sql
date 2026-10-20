/*
    Question: Which deal fields have picklist options in `field_value_options`, and is the column
    null exactly for the fields that are not picklists (never an empty array or a non-array value)?

    Run: dbt show --select profile_field_value_options --limit 10

    Result (run 2026-10-18):
    | field_key   | field_name   | options_is_null | options_json_type | option_count |
    |-------------|--------------|-----------------|-------------------|--------------|
    | add_time    | Deal Created | true            |                   |              |
    | lost_reason | Lost Reason  | false           | array             | 5            |
    | stage_id    | Stage        | false           | array             | 9            |
    | user_id     | Owner        | true            |                   |              |

    Conclusion: only the two picklist fields (`lost_reason`, `stage_id`) have options, always as a
    JSON array. The two other fields (`add_time`, a timestamp, and `user_id`, a user ID) have a null
    `field_value_options`, never an empty array or another JSON type. So a null means "this field
    has no options", not a missing value, and unnesting the column yields rows only for the
    picklist fields.

    Relied on by: the null edge case of stg_pipedrive__fields (`field_value_options` null = "no options"); the
    `fields__field_value_options` doc block; the "fields that are not picklists produce no rows"
    edge case of int_fields_unnested_to_options.
*/

select
    field_key,
    field_name,
    field_value_options is null                         as options_is_null,
    jsonb_typeof(field_value_options)                   as options_json_type,
    case
        when jsonb_typeof(field_value_options) = 'array'
            then jsonb_array_length(field_value_options)
    end                                                 as option_count
from
    {{ ref('stg_pipedrive__fields') }}
order by
    field_key
