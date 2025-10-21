{{
    config(
        materialized='table',
        tags=['staging', 'deces']
    )
}}

-- Nettoyage et standardisation des données de décès (25M+ lignes)
-- Prépare les données pour fait_deces
with source as (
    select * from {{ source('raw', 'deces_en_france_deces') }}
),

cleaned as (
    select
        -- Identifiant acte
        trim(numero_acte_deces) as numero_acte_deces,
        
        -- Date décès (format peut être YYYY-MM ou YYYY-MM-DD)
        try_cast(date_deces as date) as date_deces,
        
        -- Localisation décès
        trim(code_lieu_deces) as code_lieu_deces,
        
        -- Localisation naissance
        trim(code_lieu_naissance) as code_lieu_naissance,
        trim(lieu_naissance) as lieu_naissance,
        trim(pays_naissance) as pays_naissance,
        
        -- Informations personne
        cast(sexe as integer) as sexe_code,
        
        -- Date naissance (pour calcul âge et matching)
        try_cast(date_naissance as date) as date_naissance,
        
        -- Calcul âge au décès (si les dates sont valides)
        date_part('year', age(try_cast(date_deces as date), try_cast(date_naissance as date))) as age_deces,
        
        -- Informations pour matching
        trim(upper(nom)) as nom,
        trim(upper(prenom)) as prenom,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where date_deces is not null
      and date_naissance is not null
)

select * from cleaned
