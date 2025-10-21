{{
    config(
        materialized='table',
        tags=['staging', 'etablissement']
    )
}}

-- Nettoyage et standardisation des professionnels par établissement
-- Permet de lier professionnels et établissements
with source as (
    select * from {{ source('raw', 'etablissement_de_sante_professionnel_sante') }}
),

cleaned as (
    select
        -- Identifiant professionnel
        trim(identifiant) as identifiant,  -- RPPS/ADELI
        
        -- Informations personnelles
        upper(civilite) as civilite,
        trim(upper(nom)) as nom,
        trim(upper(prenom)) as prenom,
        
        -- Informations professionnelles
        trim(categorie_professionnelle) as categorie_professionnelle,
        trim(profession) as profession,
        trim(specialite) as specialite,
        trim(type_identifiant) as type_identifiant,
        
        -- Localisation (commune du professionnel)
        trim(commune) as commune,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where identifiant is not null
)

select * from cleaned
