with orders as (
    select * from {{ ref('stg_orders') }}
),
customers as (
    select * from {{ ref('stg_customers') }}
),
products as (
    select * from {{ ref('stg_products') }}
)
select
    o.order_id,
    o.customer_id,
    c.first_name,
    c.last_name,
    o.product_id,
    p.product_name,
    p.price,
    o.quantity,
    (o.quantity * p.price) as order_amount,
    o.order_date
from orders o
left join customers c on o.customer_id = c.customer_id
left join products p on o.product_id = p.product_id
