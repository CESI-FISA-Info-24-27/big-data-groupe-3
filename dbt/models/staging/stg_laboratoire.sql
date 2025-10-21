{{
    config(
        materialized='table',
        tags=['staging', 'laboratoire']
    )
}}

-- Nettoyage et standardisation des laboratoires pharmaceutiques
-- Prépare les données pour référentiel laboratoires
with source as (
    select * from {{ source('raw', 'laboratoire') }}
),

cleaned as (
    select
        -- Identifiant
        cast(Id_labo as integer) as id_labo,
        
        -- Informations laboratoire
        trim(Laboratoire) as nom_laboratoire,
        coalesce(trim(Pays), 'NON RENSEIGNE') as pays,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where Id_labo is not null  -- Filtrer les lignes sans ID
)

select * from cleaned
