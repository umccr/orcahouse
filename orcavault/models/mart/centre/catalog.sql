{{
    config(
        materialized='view'
    )
}}

with source as (

    select * from {{ ref('dictionary__data_mart_catalog') }}

),

final as (

    select
        cast(table_name as varchar) as table_name,
        cast(table_description as varchar) as table_description,
        cast(table_remark as varchar) as table_remark
    from
        source

)

select * from final
