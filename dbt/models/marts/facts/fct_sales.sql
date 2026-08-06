/*
    Grain:        order × SKU line item 
    PK:           sales_key = md5(order_id + sku)
    Foreign keys: date_key, product_key, geography_key, status_key
*/

with orders as (
    select
        *,
        coalesce(ship_country,     'UNKNOWN') as ship_country_for_join,
        coalesce(ship_city,        'UNKNOWN') as ship_city_for_join,
        coalesce(ship_state,       'UNKNOWN') as ship_state_for_join,
        coalesce(ship_postal_code, 'UNKNOWN') as ship_postal_code_for_join
    from {{ ref('stg_fashionable__orders') }}
)

select
    -- Primary key
    {{ dbt_utils.generate_surrogate_key(['o.order_id', 'o.sku']) }}   as sales_key,

    -- Foreign keys
    d.date_key,
    p.product_key,
    g.geography_key,
    s.status_key,

    -- Degenerate dimensions
    o.order_id,
    o.sku,
    o.fulfilment,
    o.sales_channel,
    o.ship_service_level,
    o.currency,
    o.ship_country,

    -- Measures
    o.quantity,
    o.amount,
    o.revenue_amount,
    o.promo_count,

    -- Flags
    o.is_cancelled,
    o.is_b2b

from orders o
inner join {{ ref('dim_date') }}         d on d.full_date          = o.order_date
inner join {{ ref('dim_product') }}      p on p.sku                = o.sku
inner join {{ ref('dim_geography') }}    g on g.ship_country       = o.ship_country_for_join
                                          and g.ship_city          = o.ship_city_for_join
                                          and g.ship_state         = o.ship_state_for_join
                                          and g.ship_postal_code   = o.ship_postal_code_for_join
inner join {{ ref('dim_order_status') }} s on s.status_detail      = o.status_detail
