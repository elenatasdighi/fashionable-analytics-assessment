/*
    Grain:        SKU
    PK:           product_key = md5(sku)
    Natural key:  sku
*/

with source as (
    select
        sku,
        asin,
        product_style,
        product_category,
        product_size
    from {{ ref('stg_fashionable__orders') }}
),

deduped as (
    select
        sku,
        max(asin)              as asin,
        max(product_style)     as product_style,
        max(product_category)  as product_category,
        max(product_size)      as product_size
    from source
    group by sku
)

select
    {{ dbt_utils.generate_surrogate_key(['sku']) }}  as product_key,
    sku,
    asin,
    product_style,
    product_category,
    product_size
from deduped
