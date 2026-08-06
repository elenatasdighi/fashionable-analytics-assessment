/*
    every cancelled order must carry revenue_amount = 0.

    Protects the derivation logic:
        revenue_amount = CASE WHEN is_cancelled THEN 0 ELSE amount END
    Any refactor that breaks this rule will fail here before revenue
    rollups on fct_sales become silently wrong.

*/

select
    order_id,
    sku,
    status_detail,
    amount,
    revenue_amount
from {{ ref('fct_sales') }}
inner join {{ ref('dim_order_status') }} using (status_key)
where is_cancelled = true
  and revenue_amount != 0
