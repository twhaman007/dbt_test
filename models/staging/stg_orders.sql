with source as (
    select * from {{ source('ecommerce', 'orders') }}
)
select * from source
