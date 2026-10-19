{# ---------- Intermediate: fields column docs ---------- #}

{% docs int_fields_unnested_to_options__option_id %}
Picklist option identifier (integer), unique within its `field_key`: the option's `id`, cast
from text.
{% enddocs %}

{% docs int_fields_unnested_to_options__option_label %}
Display label of the picklist option, e.g. "Pricing Issues": the option's `label`, trimmed,
empty → null, cased with `capitalize_words`.
{% enddocs %}
