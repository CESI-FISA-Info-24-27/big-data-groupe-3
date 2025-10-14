{{
    config(
        materialized='table',
        tags=['staging', 'mutuelle']
    )
}}

-- Nettoyage et standardisation des mutuelles
-- Prépare les données pour dim_mutuelle
with source as (
    select * from {{ source('raw', 'mutuelle') }}
),

cleaned as (
    select
        -- Business Key
        cast("Id_Mut" as integer) as id_mut,
        
        -- Informations mutuelle
        trim("Nom") as nom_mutuelle,
        cast("Adresse" as varchar) as adresse,  -- Adresse est INTEGER dans raw !
        
        -- Classification type mutuelle
        case
            when lower("Nom") like '%cmu%' then 'CMU'
            when lower("Nom") like '%assurance%' then 'Assurance'
            else 'Mutuelle'
        end as type_mutuelle,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where "Id_Mut" is not null
)

select * from cleaned
