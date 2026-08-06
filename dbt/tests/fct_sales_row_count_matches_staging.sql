/*
    Row-count reconciliation: fct_sales must match stg_fashionable__orders
    exactly. Any mismatch means an INNER JOIN in fct_sales dropped rows
    that a dim failed to cover.
*/

with fact_count as (
    select count(*) as n from {{ ref('fct_sales') }}
),
stg_count as (
    select count(*) as n from {{ ref('stg_fashionable__orders') }}
)
select
    f.n         as fact_rows,
    s.n         as staging_rows,
    f.n - s.n   as delta_rows
from fact_count f, stg_count s
where f.n != s.n
