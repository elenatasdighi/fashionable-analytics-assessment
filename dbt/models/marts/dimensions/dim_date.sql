/*
    Season logic (Indian seasons):
        Spring  = Mar–Apr        Summer  = May–Jun
        Monsoon = Jul–Sep        Autumn  = Oct–Nov
        Winter  = Dec–Feb
*/

with dates as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2020-01-01' as date)",
        end_date="cast('2031-01-01' as date)"
    ) }}
)

select
    cast(strftime(date_day, '%Y%m%d') as int)              as date_key,
    date_day                                               as full_date,
    extract(year    from date_day)                         as year,
    extract(quarter from date_day)                         as quarter,
    extract(month   from date_day)                         as month,
    strftime(date_day, '%B')                               as month_name,
    extract(day     from date_day)                         as day_of_month,
    extract(dow     from date_day)                         as day_of_week,
    strftime(date_day, '%A')                               as day_name,
    extract(dow     from date_day) in (0, 6)               as is_weekend,
    extract(week    from date_day)                         as week_of_year,
    case
        when extract(month from date_day) in (3, 4)         then 'Spring'
        when extract(month from date_day) in (5, 6)         then 'Summer'
        when extract(month from date_day) in (7, 8, 9)      then 'Monsoon'
        when extract(month from date_day) in (10, 11)       then 'Autumn'
        else 'Winter'
    end                                                    as season
from dates
