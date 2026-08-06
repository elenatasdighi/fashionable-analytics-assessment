/*

    Contract:
        status_group ∈ (Delivered, Cancelled, Returned) → is_terminal = TRUE
        status_group ∈ (Shipped, Pending)                → is_terminal = FALSE

    Protects the 13-row hardcoded VALUES() list in dim_order_status. If
    someone edits one row incorrectly, funnel and cohort work that reads
    is_terminal will silently misclassify orders. This test catches the
    edit before it lands.
*/

select
    status_detail,
    status_group,
    is_terminal
from {{ ref('dim_order_status') }}
where
    (status_group in ('Delivered', 'Cancelled', 'Returned') and is_terminal = false)
    or (status_group in ('Shipped', 'Pending') and is_terminal = true)
