{{
    config(
        materialized='table',
        tags=['staging', 'etablissement']
    )
}}

-- Nettoyage et standardisation des activités professionnelles
with source as (
    select * from {{ source('raw', 'etablissement_de_sante_activite_professionnel_sante') }}
),

cleaned as (
    select
        -- Identifiants
        trim(identifiant) as identifiant,  -- RPPS/ADELI
        *,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where identifiant is not null
)

select * from cleaned
