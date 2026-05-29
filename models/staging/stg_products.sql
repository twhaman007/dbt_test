with source as (
    select * from {{ source('ecommerce', 'products') }}
)
select * from source
