/*
    Grain:        1 row per status_detail (13 rows exactly)
    PK:           status_key = md5(status_detail)
    Natural key:  status_detail

    Values hardcoded here rather than seeded 
*/

with statuses(status_detail, status_group, is_terminal) as (
    values
        ('Shipped',                          'Shipped',   false),
        ('Shipped - Delivered to Buyer',     'Delivered', true),
        ('Cancelled',                        'Cancelled', true),
        ('Shipped - Returned to Seller',     'Returned',  true),
        ('Shipped - Picked Up',              'Delivered', true),
        ('Pending',                          'Pending',   false),
        ('Pending - Waiting for Pick Up',    'Pending',   false),
        ('Shipped - Returning to Seller',    'Returned',  true),
        ('Shipped - Out for Delivery',       'Delivered', true),
        ('Shipped - Rejected by Buyer',      'Returned',  true),
        ('Shipping',                         'Pending',   false),
        ('Shipped - Lost in Transit',        'Returned',  true),
        ('Shipped - Damaged',                'Returned',  true)
)

select
    {{ dbt_utils.generate_surrogate_key(['status_detail']) }}  as status_key,
    status_detail,
    status_group,
    is_terminal
from statuses
