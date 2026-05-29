# DBT & MetricFlow Semantic Layer Project Documentation

This repository contains a **dbt (data build tool)** project configured to run against **Snowflake**, utilizing the **dbt Semantic Layer** (powered by MetricFlow) and table constraints to power downstream BI/analytics tools like **Omni**.

---

## 📂 Project Directory Structure

Here is the structure of the project repository:

```text
dbt_test/
├── .gitignore                  # Specifies files and folders to ignore in Git (e.g., profiles.yml)
├── dbt_project.yml             # Core configuration file for the dbt project
├── profiles.yml.example        # Template for Snowflake credentials (should be copied to profiles.yml)
├── requirements.txt            # Python dependencies (if using a virtual environment)
├── models/
│   ├── sources.yml             # Defines raw source tables in the warehouse
│   ├── semantic_models.yml     # Configures table relationships, constraints, semantic models, and metrics
│   ├── staging/
│   │   ├── stg_customers.sql   # Staging model for raw customer data
│   │   ├── stg_products.sql    # Staging model for raw product data
│   │   └── stg_orders.sql      # Staging model for raw order data
│   └── marts/
│       ├── fct_orders.sql      # Orders Fact model (joins customers, products, and orders)
│       └── time_spine_daily.sql# A daily date dimension required for MetricFlow time dimensions
```

---

## 📄 File Descriptions & SQL/YAML Code

### 1. Project Configuration

#### ⚙️ `dbt_project.yml`
This is the root configuration file for dbt. It registers the project name, defines pathing, and specifies how models should materialize (`view` vs. `table`).

```yaml
name: 'dbt_test'
version: '1.0.0'
config-version: 2

profile: 'dbt_test'

model-paths: ["models"]
analysis-paths: ["analyses"]
test-paths: ["tests"]
seed-paths: ["seeds"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]

target-path: "target"
clean-targets:
  - "target"
  - "dbt_packages"

models:
  dbt_test:
    +enabled: true
    staging:
      +materialized: view  # Staging models are built as lightweight views
    marts:
      +materialized: table # Marts are materialized as physical tables for query performance
```

---

### 2. Source Configuration

#### 🌐 `models/sources.yml`
Defines where the raw data resides in the Snowflake database. Here, the sources point to the raw tables under the `PUBLIC` schema of `ECOMMERCE_DB`.

```yaml
version: 2

sources:
  - name: ecommerce
    database: ECOMMERCE_DB
    schema: PUBLIC
    tables:
      - name: customers
      - name: orders
      - name: products
```

---

### 3. Staging Models (`models/staging/`)
Staging models clean up, rename, and type-cast columns from raw source tables. They serve as the entry point for all downstream transformations.

#### 👤 `stg_customers.sql`
```sql
with source as (
    select * from {{ source('ecommerce', 'customers') }}
)
select * from source
```

#### 📦 `stg_products.sql`
```sql
with source as (
    select * from {{ source('ecommerce', 'products') }}
)
select * from source
```

#### 🛒 `stg_orders.sql`
```sql
with source as (
    select * from {{ source('ecommerce', 'orders') }}
)
select * from source
```

---

### 4. Marts Models (`models/marts/`)
Marts are the final analytical tables prepared for business users.

#### 📊 `fct_orders.sql`
Combines orders with customer and product information, computing the order amount dynamically.
```sql
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
```

#### 📅 `time_spine_daily.sql`
Generates a continuous sequence of days. **MetricFlow requires a time spine model** to build time-series metrics.
```sql
{{ config(materialized='table') }}

with days as (
    {{ dbt.date_spine(
        datepart="day",
        start_date="cast('2020-01-01' as date)",
        end_date="cast('2030-01-01' as date)"
    ) }}
),
final as (
    select cast(date_day as date) as date_day from days
)
select * from final
```

---

### 5. Semantic Layer & Table Constraints Configuration

#### 🧬 `models/semantic_models.yml`
This file does two critical things:
1. **Defines Primary/Foreign Key constraints** (which are created in the database during runtime).
2. **Defines the dbt Semantic Layer** (`semantic_models` and `metrics`) which platforms like **Omni** read to auto-configure joins, metrics, and dashboards.

```yaml
version: 2

models:
  # Daily Time Spine configuration for MetricFlow
  - name: time_spine_daily
    description: "Daily time spine for MetricFlow"
    config:
      materialized: table
    time_spine:
      standard_granularity_column: date_day
    columns:
      - name: date_day
        description: "The date"
        granularity: day

  # Customers Staging Configuration & Primary Key Constraint
  - name: stg_customers
    columns:
      - name: customer_id
        constraints:
          - type: primary_key
            warn_unenforced: false

  # Products Staging Configuration & Primary Key Constraint
  - name: stg_products
    columns:
      - name: product_id
        constraints:
          - type: primary_key
            warn_unenforced: false

  # Orders Mart Configuration, PK, and FK constraints
  - name: fct_orders
    columns:
      - name: order_id
        constraints:
          - type: primary_key
            warn_unenforced: false
      - name: customer_id
        constraints:
          - type: foreign_key
            to: ref('stg_customers')
            to_columns: [customer_id]
            warn_unenforced: false
      - name: product_id
        constraints:
          - type: foreign_key
            to: ref('stg_products')
            to_columns: [product_id]
            warn_unenforced: false

# dbt Semantic Models (Defines how tables map to MetricFlow entities, dimensions, and measures)
semantic_models:
  # 1. Customers Semantic Model
  - name: customers_semantic
    model: ref('stg_customers')
    entities:
      - name: customer
        type: primary
        expr: customer_id
    dimensions:
      - name: first_name
        type: categorical
      - name: last_name
        type: categorical

  # 2. Products Semantic Model
  - name: products_semantic
    model: ref('stg_products')
    entities:
      - name: product
        type: primary
        expr: product_id
    dimensions:
      - name: product_name
        type: categorical
      - name: price
        type: categorical

  # 3. Orders Fact Semantic Model
  - name: fct_orders_semantic
    model: ref('fct_orders')
    defaults:
      agg_time_dimension: order_date
    entities:
      - name: order_id
        type: primary
      - name: customer
        type: foreign
        expr: customer_id
      - name: product
        type: foreign
        expr: product_id
    measures:
      - name: total_order_amount
        description: "The total value of orders"
        expr: order_amount
        agg: sum
      - name: total_quantity
        description: "The total number of product units ordered"
        expr: quantity
        agg: sum
      - name: order_count
        description: "The total count of orders placed"
        expr: 1
        agg: sum
    dimensions:
      - name: order_date
        type: time
        type_params:
          time_granularity: day

# Metrics configuration (Calculated values parsed by Omni and BI tools)
metrics:
  # Simple metric representing revenue
  - name: total_revenue
    label: Total Revenue
    description: "Sum of all order values"
    type: simple
    type_params:
      measure: total_order_amount

  # Simple metric representing number of orders
  - name: order_volume
    label: Order Volume
    description: "Total count of orders"
    type: simple
    type_params:
      measure: order_count

  # Derived metric showing Average Order Value
  - name: average_order_value
    label: Average Order Value
    description: "Average revenue per order"
    type: ratio
    type_params:
      numerator: total_revenue
      denominator: order_volume
```

---

## 🔑 Credentials Setup (`profiles.yml`)

Database credentials are **never** committed to Git. Instead, they are defined locally in a file named `profiles.yml`.

### Step-by-Step Credentials Configuration:
1. Locate the file `profiles.yml.example` in the root of the project.
2. Duplicate it and rename the copy to `profiles.yml`.
3. Open `profiles.yml` and replace the placeholder fields (`<...>`) with your database details.

#### Example `profiles.yml`:
```yaml
dbt_test:
  outputs:
    dev:
      type: snowflake
      account: LTYRFLV-FA02764              # Your Snowflake account locator
      user: akshatdbt                       # Snowflake username
      password: "your_actual_password"      # Snowflake password
      warehouse: COMPUTE_WH                 # Warehouse used for execution
      database: ECOMMERCE_DB                # Target database
      schema: PUBLIC                        # Target schema where output tables/views are created
      threads: 4                            # Number of concurrent threads
      client_session_keep_alive: False
  target: dev
```

> [!NOTE]
> `profiles.yml` is listed in `.gitignore`, so it will remain local and secure on your machine.

---

## 🚀 How to Run the Project

Ensure you have python and dbt installed. (If using the project's virtual environment, activate it using `.venv\Scripts\Activate.ps1` in PowerShell).

### 1. Test Connection
Validate your credentials setup and connection to Snowflake:
```bash
dbt debug
```

### 2. Compile Models
Check if SQL syntax and YAML semantic declarations are valid:
```bash
dbt compile
```

### 3. Build/Run Models
Compile and execute the models, generating views and tables in the specified schema (e.g., `PUBLIC`):
```bash
dbt run
```

### 4. Run Tests
Verify constraints and tests defined for the schemas:
```bash
dbt test
```
