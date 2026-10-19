{#
    Upper-cases the first letter of each space-separated word and keeps every other letter as it
    is. Documented in macros/capitalize_words.yml.

    Unlike Postgres initcap(), it doesn't capitalize after a hyphen or slash and never lower-cases:
    "Follow-up/Customer Success" stays as written, "Qualified lead" becomes "Qualified Lead".
#}

{% macro capitalize_words(expression) -%}

    (
        select
            string_agg(upper(left(word, 1)) || substr(word, 2), ' ' order by word_position)
        from
            regexp_split_to_table({{ expression }}, '\s+') with ordinality as words (word, word_position)
    )

{%- endmacro %}
