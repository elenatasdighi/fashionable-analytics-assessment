/*
    Grain:        (ship_country, ship_city, ship_state, ship_postal_code)
    PK:           geography_key = md5(country + '|' + city + '|' + state + '|' + postal_code)
    SCD:          Type 1 (overwrite)
*/

with valid_geography as (
    select distinct
        ship_country,
        ship_city,
        ship_state,
        ship_postal_code
    from {{ ref('stg_fashionable__orders') }}
    where ship_country     is not null
      and ship_city        is not null
      and ship_state       is not null
      and ship_postal_code is not null
),

unknown_row as (
    -- Sentinel for line items missing shipping fields.
    select
        'UNKNOWN' as ship_country,
        'UNKNOWN' as ship_city,
        'UNKNOWN' as ship_state,
        'UNKNOWN' as ship_postal_code
),

combined as (
    select * from valid_geography
    union all
    select * from unknown_row
),

regions as (
    select country, state, region from {{ ref('state_to_region') }}
)

select
    {{ dbt_utils.generate_surrogate_key(
        ['c.ship_country', 'c.ship_city', 'c.ship_state', 'c.ship_postal_code']
    ) }}                                     as geography_key,
    c.ship_country,
    c.ship_city,
    c.ship_state,
    c.ship_postal_code,
    coalesce(r.region, 'Unknown')            as region
from combined c
left join regions r
    on r.country = c.ship_country
   and r.state   = c.ship_state
