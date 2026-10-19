{#
    Delete post_hook for incremental models. Documented in macros/delete_rows_missing_upstream.yml.

    An incremental (append / merge) load never removes rows, so a row deleted upstream would stay in
    the model forever. This deletes every row whose key no longer exists in the upstream model, and
    does nothing while the upstream holds no rows for the filter (a failed or unfinished raw reload
    must not empty the table).
#}

{% macro delete_rows_missing_upstream(upstream, key_columns, upstream_filter='1 = 1') -%}

    delete from {{ this }} as target
    where not exists (
        select 1
        from {{ upstream }} as source
        where {{ upstream_filter }}
        {%- for column in key_columns %}
            and source.{{ column }} = target.{{ column }}
        {%- endfor %}
    )
    -- guard: an empty upstream (failed or unfinished raw reload) would delete every row
    and exists (
        select 1
        from {{ upstream }}
        where {{ upstream_filter }}
    )

{%- endmacro %}
