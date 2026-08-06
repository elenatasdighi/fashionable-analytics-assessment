/*
    Row-count reconciliation between raw and stg_fashionable__orders.

*/

with raw_distinct_pairs as (
    select count(*) as n
    from (
        select distinct "Order ID", "SKU"
        from {{ source('fashionable', 'fashionable_sales_raw') }}
    )
),
staging_count as (
    select count(*) as n from {{ ref('stg_fashionable__orders') }}
)
select
    r.n         as expected_rows_from_raw_dedup,
    s.n         as actual_staging_rows,
    r.n - s.n   as unexpected_delta
from raw_distinct_pairs r, staging_count s
where r.n != s.n
