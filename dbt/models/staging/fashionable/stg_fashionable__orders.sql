/*
    Grain: one row per order line item (order_id × sku), after dedupe.

    Transformations:
      - snake_case renames + typing
      - Dedup 7 exact-duplicate (order_id, sku)
      - Drop columns: index (technical), currency, ship-country, fulfilled-by,
        Unnamed: 22 
      - UPPER(TRIM()) 
      - Postal code cleanup: strips '.0' float-export artefact
      - Date cast with strptime('%m-%d-%y')
      - Derived measures: is_cancelled + revenue_amount, promo_count 
*/

with source as (
    select * from {{ source('fashionable', 'fashionable_sales_raw') }}
),

renamed_and_typed as (
    select
        -- Kept as an internal dedup tiebreaker; dropped from the final projection.
        try_cast("index" as int)                                       as _source_index,

        trim("Order ID")                                               as order_id,
        trim("SKU")                                                    as sku,

        try_strptime("Date", '%m-%d-%y')::date                         as order_date,

        trim("Status")                                                 as status_detail,
        trim("Courier Status")                                         as courier_status,

        trim("Fulfilment")                                             as fulfilment,
        trim("Sales Channel")                                          as sales_channel,
        trim("ship-service-level")                                     as ship_service_level,

        trim("Style")                                                  as product_style,
        trim("Category")                                               as product_category,
        trim("Size")                                                   as product_size,
        trim("ASIN")                                                   as asin,

        try_cast("Qty" as int)                                         as quantity,
        try_cast("Amount" as decimal(10, 2))                           as amount,
        trim("currency")                                               as currency,

        upper(trim("ship-city"))                                       as ship_city,
        trim("ship-city")                                              as ship_city_raw,
        upper(trim("ship-state"))                                      as ship_state,
        trim("ship-state")                                             as ship_state_raw,
        split_part(trim("ship-postal-code"), '.', 1)                   as ship_postal_code,
        trim("ship-country")                                           as ship_country,

        nullif(trim("promotion-ids"), '')                              as promotion_ids_raw,

        lower(trim("B2B")) = 'true'                                    as is_b2b
    from source
),

deduped as (
-- Keep one row per (order_id, sku).
-- Prefer rows with a non-null amount; otherwise keep the latest row.
-- This avoids keeping incomplete records when a later, more complete version exists.
    select *
    from renamed_and_typed
    qualify row_number() over (
        partition by order_id, sku
        order by (amount is null), _source_index desc
    ) = 1
),

with_derived_measures as (
    select
        order_id,
        sku,
        order_date,

        status_detail,
        courier_status,

        fulfilment,
        sales_channel,
        ship_service_level,

        product_style,
        product_category,
        product_size,
        asin,

        quantity,
        amount,
        currency,

        ship_city,
        ship_city_raw,
        ship_state,
        ship_state_raw,
        ship_postal_code,
        ship_country,

        promotion_ids_raw,

        is_b2b,

        status_detail = 'Cancelled'                                    as is_cancelled,

        case
            when status_detail = 'Cancelled' then 0::decimal(10, 2)
            else amount
        end                                                            as revenue_amount,

        case
            when promotion_ids_raw is null then 0
            else length(promotion_ids_raw)
                 - length(replace(promotion_ids_raw, ',', ''))
                 + 1
        end                                                            as promo_count
    from deduped
)

select * from with_derived_measures
