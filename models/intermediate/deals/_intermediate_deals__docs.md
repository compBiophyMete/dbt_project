{# ---------- Intermediate: deals column docs ---------- #}

{% docs has_multiple_creations %}
Whether the deal ID has more than one creation (`add_time`) row in the deal change log (boolean).
{% enddocs %}

{% docs int_deals__creation_count %}
Number of creation (`add_time`) rows the deal has in the deal change log (integer, ≥ 0).
{% enddocs %}

{% docs stage_id_at_loss %}
Pipeline stage the deal was in when it was lost (integer, 1–9): the `stage_id` of the deal's
latest stage change at or before the loss's `changed_at`.
{% enddocs %}

{% docs int_deals__stage_id_at_loss %}
Pipeline stage the deal was in at its latest loss (integer, 1–9): the `stage_id` of the deal's
latest stage change at or before `lost_at`. Null when the deal has no loss.
{% enddocs %}

{% docs int_deal_changes_filtered_to_creations__created_at %}
When the deal was created (`timestamp without time zone`, in UTC): the `add_time` value of the
deal change log.
{% enddocs %}

{% docs int_deal_changes_filtered_to_stages__changed_at %}
When the deal moved into `stage_id` (`timestamp without time zone`, in UTC).
{% enddocs %}

{% docs int_deal_changes_filtered_to_owners__owner_user_id %}
Identifier of the user the deal was handed to (integer): the `user_id` value of the deal change
log (`owner_id` in API v2, [v2 migration guide](https://pipedrive.readme.io/docs/pipedrive-api-v2-migration-guide)).
{% enddocs %}

{% docs int_deal_changes_filtered_to_owners__changed_at %}
When the deal was handed to `owner_user_id` (`timestamp without time zone`, in UTC).
{% enddocs %}

{% docs int_deal_changes_filtered_to_losses__lost_reason_id %}
Identifier of the reason the deal was lost for (integer, 1–5): a picklist option of the
`lost_reason` field.
{% enddocs %}

{% docs int_deal_changes_filtered_to_losses__changed_at %}
When the deal was marked lost (`timestamp without time zone`, in UTC).
{% enddocs %}

{% docs int_deals__first_recorded_owner_user_id %}
Identifier of the deal's first owner in the deal change log (integer): the owner of its earliest
owner change.
{% enddocs %}

{% docs int_deals__owner_change_count %}
Number of owner changes after the first recorded owner (integer, ≥ 0): the deal's owner rows
minus 1.
{% enddocs %}

{% docs int_deals__stage_change_count %}
Number of moves into a stage in the deal change log (integer, ≥ 0), re-entries included.
{% enddocs %}

{% docs int_deals__current_owner_user_id %}
Identifier of the deal's current owner (integer): the owner of its latest owner change.
{% enddocs %}

{% docs int_deals__current_stage_id %}
Stage the deal is in now (integer, 1–9): the stage of its latest stage change.
{% enddocs %}

{% docs int_deals__furthest_stage_id %}
Highest stage the deal ever entered (integer, 1–9): `max(stage_id)` over its stage changes.
{% enddocs %}

{% docs int_deals__created_at %}
When the deal was first created (`timestamp without time zone`, in UTC): its earliest creation
time.
{% enddocs %}

{% docs int_deals__current_stage_entered_at %}
When the deal moved into `current_stage_id` (`timestamp without time zone`, in UTC).
{% enddocs %}

{% docs int_deals__lost_at %}
When the deal was last marked lost (`timestamp without time zone`, in UTC). Null when the deal has
no loss.
{% enddocs %}

{% docs int_deal_stage_changes_aggregated_to_entries__entered_at %}
When the deal first entered `stage_id` (`timestamp without time zone`, in UTC).
{% enddocs %}
