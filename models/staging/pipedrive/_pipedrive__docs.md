{# ---------- Shared column docs ---------- #}

{% docs deal_id %}
Pipedrive deal identifier (integer).
{% enddocs %}

{% docs user_id %}
Pipedrive user identifier (integer).
{% enddocs %}

{% docs stage_id %}
Pipeline stage identifier (integer, 1–9).
{% enddocs %}

{% docs activity_type %}
Activity type key (max 50 characters), e.g. `meeting`, `sc_2`, `follow_up`, `after_close_call`.
{% enddocs %}

{% docs field_key %}
Deal field key (max 50 characters), e.g. `add_time`, `stage_id`, `user_id`, `lost_reason`.
`user_id` is the deal owner field, named `user_id` in Pipedrive API v1 and `owner_id` in API v2
([v2 migration guide](https://pipedrive.readme.io/docs/pipedrive-api-v2-migration-guide): "`user_id`
field has been renamed to `owner_id`"); this data uses the v1 name.
{% enddocs %}

{# ---------- Table-specific column docs ---------- #}

{% docs activity__activity_id %}
Pipedrive activity identifier (integer). Not unique: some IDs appear on two deals, so join on
`activity_id` and `deal_id` together.
{% enddocs %}

{% docs activity__assigned_to_user %}
Identifier of the user the activity is assigned to (integer).
{% enddocs %}

{% docs activity__done %}
Whether the activity is marked as done (boolean).
{% enddocs %}

{% docs activity__due_to %}
Due date and time of the activity (`timestamp without time zone`), presumably UTC, as
[Pipedrive's API returns all times in UTC](https://pipedrive.readme.io/docs/core-api-concepts-date-format);
not converted. It is the planned date: "The due date field will always show the time and date the
activity was originally scheduled for" ([Pipedrive Knowledge Base: Activities](https://support.pipedrive.com/en/article/activities)).
{% enddocs %}

{% docs activity_types__id %}
Activity type identifier (integer).
{% enddocs %}

{% docs activity_types__name %}
Display name of the activity type (max 255 characters), e.g. "Sales Call 1".
{% enddocs %}

{% docs activity_types__active %}
Whether the activity type is active, stored as the string `'Yes'` or `'No'` (max 10 characters).
{% enddocs %}

{% docs deal_changes__change_time %}
When the field change happened (`timestamp without time zone`, in UTC: [Pipedrive's API uses UTC](https://pipedrive.readme.io/docs/core-api-concepts-date-format)).
{% enddocs %}

{% docs deal_changes__new_value %}
Value the field was changed to, stored as text (max 255 characters). Its meaning depends on
`changed_field_key`:
- `add_time`: the deal's creation timestamp, ISO-8601 (`YYYY-MM-DDTHH:MI:SS`).
- `stage_id`: the new stage ID.
- `user_id`: the new owner's user ID (`owner_id` in API v2, [v2 migration guide](https://pipedrive.readme.io/docs/pipedrive-api-v2-migration-guide)).
- `lost_reason`: the lost-reason option ID, a picklist option of the `lost_reason` field.
{% enddocs %}

{% docs fields__id %}
Field identifier (integer).
{% enddocs %}

{% docs fields__name %}
Display name of the field (max 255 characters), e.g. "Stage", "Owner".
{% enddocs %}

{% docs fields__field_value_options %}
Picklist options of the field, as a JSONB array of `{"id": "<text id>", "label": "<display label>"}`
objects. Null for a field without a picklist.
{% enddocs %}

{% docs stages__stage_name %}
Display name of the pipeline stage (max 255 characters), e.g. "Lead Generation".
{% enddocs %}

{% docs users__id %}
User identifier (integer).
{% enddocs %}

{% docs users__name %}
User's full name (max 255 characters). Not unique: some names are shared by several users, so
never join on it.
{% enddocs %}

{% docs users__email %}
User's email address (max 255 characters). Not unique: some addresses are shared by several
users, so never join on it.
{% enddocs %}

{% docs users__modified %}
When the user record was last modified (`timestamp without time zone`, in UTC: [Pipedrive's API uses UTC](https://pipedrive.readme.io/docs/core-api-concepts-date-format)).
{% enddocs %}

{# ---------- Staging: stg_pipedrive__activities ---------- #}

{% docs stg_pipedrive__activities__is_done %}
Whether the activity is done (boolean, never null): `coalesce(done, false)`, so an unknown
completion is `false`.
{% enddocs %}

{# ---------- Staging: stg_pipedrive__activity_types ---------- #}

{% docs stg_pipedrive__activity_types__is_activity_type_active %}
Whether the activity type is active in Pipedrive (boolean), from the raw `active`: `'Yes'` →
`true`, `'No'` → `false` (case-insensitive); any other value is null. An attribute of the
activity type, the same on every activity of that type.
{% enddocs %}

{# ---------- Staging: stg_pipedrive__users ---------- #}

{% docs stg_pipedrive__users__is_valid_email %}
Whether `email` has a valid format (boolean), checked case-insensitively with the regex
`^[a-z0-9][a-z0-9._%+-]*@[a-z0-9.-]+\.[a-z]+$`. `false` for a null email. Checks the format only,
not whether the address exists.
{% enddocs %}

{# ---------- Staging: stg_pipedrive__deal_changes ---------- #}

{% docs stg_pipedrive__deal_changes__new_value_integer %}
`new_value` as an integer (whole numbers of 1 to 9 digits) on rows whose `changed_field_key` is
not `add_time`; null on `add_time` rows and for a value that isn't such a number.
{% enddocs %}

{% docs stg_pipedrive__deal_changes__new_value_timestamp %}
`new_value` as a timestamp (`timestamp without time zone`, in UTC) on `add_time` rows; null on
other rows and for a value that isn't a valid ISO-8601 timestamp.
{% enddocs %}
