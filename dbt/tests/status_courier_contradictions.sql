{{
    config(
        warn_if='>250',
        error_if='>1000'
    )
}}

/*
    Detect contradictions between order and courier statuses.

    Thresholds:
      - <= 250  -> PASS
      - <= 1000 -> WARN
      - > 1000  -> ERROR
*/

select
    order_id,
    sku,
    status_detail,
    courier_status
from {{ ref('stg_fashionable__orders') }}
where
    (status_detail = 'Shipped'
        and courier_status in ('Unshipped', 'Cancelled'))
    or
    (status_detail like 'Pending%'
        and courier_status = 'Shipped')
