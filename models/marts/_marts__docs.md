{# ---------- Shared mart column docs ---------- #}

{% docs lost_reason_name %}
Display name of the reason the deal was lost (max 255 characters), e.g. "Pricing Issues".
{% enddocs %}

{# ---------- Marts: fct_activities ---------- #}

{% docs has_known_deal %}
Whether the activity's `deal_id` exists in `int_deals` (boolean).
{% enddocs %}

{# ---------- Marts: fct_deal_events ---------- #}

{% docs fct_deal_events__changed_at %}
When the event was recorded in the deal change log (`timestamp without time zone`, in UTC).
{% enddocs %}

{% docs fct_deal_events__event_type %}
Type of the event (max 20 characters): `created`, `stage_changed`, `owner_changed` or `lost`, one
per change-log field key (`add_time`, `stage_id`, `user_id`, `lost_reason`).
{% enddocs %}

{% docs fct_deal_events__owner_name %}
Name of the user the deal was handed to on an `owner_changed` event (max 255 characters). Not
unique, so never join on it. Null on other event types.
{% enddocs %}

{# ---------- Marts: rep_sales_funnel_monthly ---------- #}

{% docs rep_sales_funnel_monthly__month %}
Calendar month (`date`, the first day of the month), e.g. 2024-03-01.
{% enddocs %}

{% docs rep_sales_funnel_monthly__deals_count %}
Number of deals that reached the funnel step in the month (integer, ≥ 0).
{% enddocs %}

{# ---------- Marts: dim_deals ---------- #}

{% docs dim_deals__first_recorded_owner_name %}
Name of the deal's first recorded owner (max 255 characters). Not unique, so never join on it.
{% enddocs %}

{% docs dim_deals__current_owner_name %}
Name of the deal's current owner (max 255 characters). Not unique, so never join on it.
{% enddocs %}

{% docs dim_deals__current_stage_name %}
Name of the stage the deal is in now (max 255 characters), e.g. "Negotiation".
{% enddocs %}

{% docs dim_deals__furthest_stage_name %}
Name of the highest stage the deal ever entered (max 255 characters), e.g. "Closing".
{% enddocs %}

{% docs fct_deal_losses__stage_id_at_loss %}
Pipeline stage the deal was in when it was lost (integer, 1–9): the `stage_id` of the deal's
latest stage change at or before `lost_at`.
{% enddocs %}

{% docs stage_name_at_loss %}
Name of the stage the deal was in when it was lost (max 255 characters), e.g. "Negotiation".
{% enddocs %}
