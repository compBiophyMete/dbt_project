{# ---------- Intermediate: funnel column docs ---------- #}

{% docs funnel_step %}
Step of the sales funnel (text): `'1'` to `'9'` for the stage steps, `'2.1'` and `'3.1'` for the
call steps. Sorted as text, it gives the funnel order.
{% enddocs %}

{% docs kpi_name %}
Display name of the funnel step (max 100 characters), e.g. "Lead Generation".
{% enddocs %}

{% docs int_funnel_steps_mapped__stage_id %}
The stage that makes up a stage step (integer, 1–9). Null for call steps.
{% enddocs %}

{% docs int_funnel_steps_mapped__activity_type %}
The activity type that makes up a call step, e.g. `meeting`. Null for stage steps.
{% enddocs %}

{% docs int_deal_funnel_steps_unioned__entered_at %}
When the deal reached the funnel step (`timestamp without time zone`, in UTC).
{% enddocs %}
