{{
    config(
        indexes=[
            {'columns': ['library_id'], 'type': 'btree'},
            {'columns': ['alias_library_id'], 'type': 'btree'},
            {'columns': ['run'], 'type': 'btree'},
            {'columns': ['comments'], 'type': 'btree'},
            {'columns': ['load_datetime'], 'type': 'btree'},
        ]
    )
}}

with source as (

    select
        row_number() over (partition by library_id order by load_datetime desc) as rank,
        library_id,
        run,
        sheet_name,
        comments,
        record_source,
        load_datetime
    from {{ ref('spreadsheet_library_tracking_metadata') }}

),

transformed as (

    select
        sal.base_library_id as library_id,
        sal.alias_library_id,
        src.run,
        src.sheet_name,
        src.comments,
        src.record_source,
        src.load_datetime
    from {{ ref('sal_library') }} sal
            join source src on src.library_id = sal.alias_library_id and src.rank = 1

),

final as (

    select
        cast(library_id as varchar(255)) as library_id,
        cast(alias_library_id as varchar(255)) as alias_library_id,
        cast(run as varchar) as run,
        cast(sheet_name as varchar) as sheet_name,
        cast(comments as text) as comments,
        cast(record_source as varchar(255)) as record_source,
        cast(load_datetime as timestamptz) as load_datetime
    from
        transformed
    order by library_id desc

)

select * from final
