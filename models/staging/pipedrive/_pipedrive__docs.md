{# ---------- Shared column docs ---------- #}

{% docs deal_id %}
Pipedrive deal identifier (integer). The source has no deals table, so `deal_changes` is the only
place a deal's history is recorded.
{% enddocs %}

{% docs user_id %}
Pipedrive user identifier (integer), referencing `users.id`.
{% enddocs %}

{% docs stage_id %}
Pipeline stage identifier (integer, 1–9, in funnel order), referencing `stages.stage_id`.
{% enddocs %}

{% docs activity_type %}
Activity type key (max 50 characters), e.g. `meeting`, `sc_2`, `follow_up`, `after_close_call`.
References `activity_types.type`.
{% enddocs %}

{% docs field_key %}
Deal field key (max 50 characters): one of `add_time`, `stage_id`, `user_id`, `lost_reason`.
References `fields.field_key`.
{% enddocs %}

{# ---------- Table-specific column docs ---------- #}

{% docs activity__activity_id %}
Pipedrive activity identifier (integer). Not unique in the raw data: 11 IDs appear twice with
different content. See the table description.
{% enddocs %}

{% docs activity__assigned_to_user %}
ID of the user the activity is assigned to (integer), referencing `users.id`.
{% enddocs %}

{% docs activity__done %}
Whether the activity was completed: `true` = done, `false` = open or not done. Never null.
{% enddocs %}

{% docs activity__due_to %}
Due date and time of the activity (`timestamp without time zone`; the source does not record a timezone).
{% enddocs %}

{% docs activity_types__id %}
Activity type identifier (integer, declared primary key).
{% enddocs %}

{% docs activity_types__name %}
Display name of the activity type (max 255 characters), e.g. "Sales Call 1".
{% enddocs %}

{% docs activity_types__active %}
Whether the activity type is active, stored as the **string** `'Yes'` or `'No'` (max 10 characters),
not as a boolean.
{% enddocs %}

{% docs deal_changes__change_time %}
When the field change happened (`timestamp without time zone`; the source does not record a timezone).
{% enddocs %}

{% docs deal_changes__new_value %}
Value the field was changed to, stored as text (max 255 characters). Its meaning depends on
`changed_field_key`:
- `add_time`: deal creation timestamp in ISO-8601 format (`YYYY-MM-DDTHH:MI:SS`). Always equal to `change_time`.
- `stage_id`: new stage ID (`'1'`–`'9'`), referencing `stages.stage_id`.
- `user_id`: new owner's user ID, referencing `users.id`.
- `lost_reason`: lost-reason option ID (`'1'`–`'5'`), whose labels are in `fields.field_value_options`
  for `lost_reason`.
{% enddocs %}

{% docs fields__id %}
Field identifier (integer, declared primary key).
{% enddocs %}

{% docs fields__name %}
Display name of the field (max 255 characters), e.g. "Stage", "Owner".
{% enddocs %}

{% docs fields__field_value_options %}
Picklist options for the field, as a JSONB array of `{"id": "<text id>", "label": "<display label>"}`
objects. The `id` values match `deal_changes.new_value` for that field. Null for fields that are not
picklists (`add_time`, `user_id`).
{% enddocs %}

{% docs stages__stage_name %}
Display name of the pipeline stage (max 255 characters), e.g. "Lead Generation".
{% enddocs %}

{% docs users__id %}
User identifier (integer, declared primary key).
{% enddocs %}

{% docs users__name %}
User's full name (max 255 characters). Not unique: 21 duplicate values.
{% enddocs %}

{% docs users__email %}
User's email address (max 255 characters). Not unique: 4 duplicate values.
{% enddocs %}

{% docs users__modified %}
When the user record was last modified (`timestamp without time zone`, microsecond precision; the
source does not record a timezone).
{% enddocs %}
