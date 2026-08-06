{{
    config(
        warn_if='>3000',
        error_if='>10000'
    )
}}

/*
    Warn if too many fact rows fall into region='Unknown'.
    Reason is that the seed state_to_region is missing some states (misspellings from profiling)
    and currently we have some rows in fact_sales with missing shipping info (33 rows)
*/

select
    f.order_id,
    f.sku,
    g.ship_state
from {{ ref('fct_sales') }}     f
join {{ ref('dim_geography') }} g using (geography_key)
where g.region = 'Unknown'
