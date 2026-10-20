/*
    Question: Which columns identify one row in each staging model?

    Run: dbt show --select profile_staging_grains --limit 20

    Method: per model, start from the key `init.sql` declares (or, without one, the entity's ID)
    and test it: a key holds when distinct keys = rows and no key column is null. When it fails,
    look at what differs between the duplicate rows, add that column and test again. Columns that
    other models join on (names, emails, field keys) are tested too, to know whether they are safe
    join keys.

    Result (run 2026-10-21), no key column is null in any step:
    | model         | step | key tested                                  | rows   | distinct | surplus |
    |---------------|------|---------------------------------------------|--------|----------|---------|
    | deal_changes  | 1    | deal_id                                     | 15,406 |  1,995   | 13,411  |
    | deal_changes  | 2    | (deal_id, changed_field_key)                | 15,406 |  7,980   |  7,426  |
    | deal_changes  | 3    | (deal_id, changed_at)                       | 15,406 | 15,406   |      0  |
    | deal_changes  | 4    | (deal_id, changed_at, changed_field_key)    | 15,406 | 15,406   |      0  |
    | activities    | 1    | activity_id                                 |  4,579 |  4,568   |     11  |
    | activities    | 2    | (activity_id, deal_id)                      |  4,579 |  4,579   |      0  |
    | activity_types| 1    | activity_type_id                            |      4 |      4   |      0  |
    | fields        | 1    | field_id                                    |      4 |      4   |      0  |
    | fields        | 2    | field_key                                   |      4 |      4   |      0  |
    | stages        | 1    | stage_id                                    |      9 |      9   |      0  |
    | users         | 1    | user_id                                     |  1,787 |  1,787   |      0  |
    | users         | 2    | user_name                                   |  1,787 |  1,766   |     21  |
    | users         | 3    | email                                       |  1,787 |  1,783   |      4  |

    Conclusion:
    - deal_changes is a log, so the deal alone repeats (step 1), and so does deal + field, because
      a deal changes its stage or owner more than once (step 2). Adding the change time makes the
      rows unique (step 3): no deal has two changes in the same second. The field key (step 4)
      adds nothing in this data; the tested grain includes it.
    - activities: 11 activity IDs appear twice (step 1). Adding the deal makes the rows unique
      (step 2): each reused ID sits on two different deals. So the grain is (activity_id, deal_id)
      and joins use both.
    - activity_types, fields, stages and users: the declared primary key holds. field_key is unique
      too, so deal_changes can safely join fields on it. User names and emails repeat, so users
      join on user_id only.

    Relied on by: the grain tests and "Join on …" notes of every staging model; the failing
    `unique` test on source activity.activity_id; the join keys of int_activities_joined_to_types
    and every model joining users.
*/

with

key_checks as (

    -- deal_changes: init.sql declares no key, so build one up from the deal
    select
        'stg_pipedrive__deal_changes'           as model,
        1                                       as step,
        'deal_id'                               as key_tested,
        count(*)                                as row_count,
        count(distinct deal_id)                 as distinct_keys,
        count(*) filter (where deal_id is null) as rows_with_null_key
    from
        {{ ref('stg_pipedrive__deal_changes') }}

    union all

    -- a deal changes the same field several times (e.g. stage after stage)
    select
        'stg_pipedrive__deal_changes',
        2,
        '(deal_id, changed_field_key)',
        count(*),
        count(distinct (deal_id, changed_field_key)),
        count(*) filter (where deal_id is null or changed_field_key is null)
    from
        {{ ref('stg_pipedrive__deal_changes') }}

    union all

    -- the change time tells repeated changes of one deal apart
    select
        'stg_pipedrive__deal_changes',
        3,
        '(deal_id, changed_at)',
        count(*),
        count(distinct (deal_id, changed_at)),
        count(*) filter (where deal_id is null or changed_at is null)
    from
        {{ ref('stg_pipedrive__deal_changes') }}

    union all

    select
        'stg_pipedrive__deal_changes',
        4,
        '(deal_id, changed_at, changed_field_key)',
        count(*),
        count(distinct (deal_id, changed_at, changed_field_key)),
        count(*) filter (where deal_id is null or changed_at is null or changed_field_key is null)
    from
        {{ ref('stg_pipedrive__deal_changes') }}

    union all

    -- activities: init.sql declares no key; start from the activity ID
    select
        'stg_pipedrive__activities',
        1,
        'activity_id',
        count(*),
        count(distinct activity_id),
        count(*) filter (where activity_id is null)
    from
        {{ ref('stg_pipedrive__activities') }}

    union all

    -- a reused ID sits on different deals, so the deal tells its rows apart
    select
        'stg_pipedrive__activities',
        2,
        '(activity_id, deal_id)',
        count(*),
        count(distinct (activity_id, deal_id)),
        count(*) filter (where activity_id is null or deal_id is null)
    from
        {{ ref('stg_pipedrive__activities') }}

    union all

    -- activity_types: init.sql declares id as the primary key
    select
        'stg_pipedrive__activity_types',
        1,
        'activity_type_id',
        count(*),
        count(distinct activity_type_id),
        count(*) filter (where activity_type_id is null)
    from
        {{ ref('stg_pipedrive__activity_types') }}

    union all

    -- fields: init.sql declares ID as the primary key
    select
        'stg_pipedrive__fields',
        1,
        'field_id',
        count(*),
        count(distinct field_id),
        count(*) filter (where field_id is null)
    from
        {{ ref('stg_pipedrive__fields') }}

    union all

    -- the column deal_changes.changed_field_key points to
    select
        'stg_pipedrive__fields',
        2,
        'field_key',
        count(*),
        count(distinct field_key),
        count(*) filter (where field_key is null)
    from
        {{ ref('stg_pipedrive__fields') }}

    union all

    -- stages: init.sql declares stage_id as the primary key
    select
        'stg_pipedrive__stages',
        1,
        'stage_id',
        count(*),
        count(distinct stage_id),
        count(*) filter (where stage_id is null)
    from
        {{ ref('stg_pipedrive__stages') }}

    union all

    -- users: init.sql declares id as the primary key
    select
        'stg_pipedrive__users',
        1,
        'user_id',
        count(*),
        count(distinct user_id),
        count(*) filter (where user_id is null)
    from
        {{ ref('stg_pipedrive__users') }}

    union all

    -- a name or an email would be a tempting join key from other systems
    select
        'stg_pipedrive__users',
        2,
        'user_name',
        count(*),
        count(distinct user_name),
        count(*) filter (where user_name is null)
    from
        {{ ref('stg_pipedrive__users') }}

    union all

    select
        'stg_pipedrive__users',
        3,
        'email',
        count(*),
        count(distinct email),
        count(*) filter (where email is null)
    from
        {{ ref('stg_pipedrive__users') }}

)

select
    model,
    step,
    key_tested,
    row_count,
    distinct_keys,
    row_count - distinct_keys                   as surplus_rows,
    rows_with_null_key
from
    key_checks
order by
    model,
    step
