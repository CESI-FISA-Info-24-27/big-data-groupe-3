{{
    config(
        materialized='table',
        tags=['ods', 'core', 'deces']
    )
}}

-- Décès enrichis avec calculs et classifications
-- Prépare les données pour fait_deces (25M+ lignes)
with deces as (
    select * from {{ ref('stg_deces') }}
),

deces_enrichi as (
    select
        -- Identifiants
        numero_acte_deces,
        
        -- Dates
        date_deces,
        date_naissance,
        
        -- Âge au décès
        age_deces,
        
        -- Classification par âge
        case
            when age_deces < 1 then 'MOINS_1_AN'
            when age_deces between 1 and 18 then 'ENFANT'
            when age_deces between 19 and 30 then 'JEUNE_ADULTE'
            when age_deces between 31 and 65 then 'ADULTE'
            when age_deces > 65 then 'SENIOR'
            else 'NON_RENSEIGNE'
        end as tranche_age_deces,
        
        -- Sexe
        case
            when sexe_code = 1 then 'M'
            when sexe_code = 2 then 'F'
            else 'INCONNU'
        end as sexe,
        
        -- Localisation décès
        code_lieu_deces,
        
        -- Localisation naissance
        code_lieu_naissance,
        lieu_naissance,
        pays_naissance,
        
        -- Identité (pour matching éventuel)
        nom,
        prenom,
        
        -- Métadonnées
        loaded_at
        
    from deces
    where date_deces is not null  -- Filtrer dates invalides
)

select * from deces_enrichi





