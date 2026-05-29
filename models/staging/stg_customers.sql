with source as (
    select * from {{ source('ecommerce', 'customers') }}
)
select * from source
