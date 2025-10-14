

-- Dimension Spécialité
-- Source : stg_specialites (93 spécialités avec 30+ catégories)
-- Clé substitut : sk_specialite (auto-incrémenté via row_number)

with specialites_source as (
    select * from "staging"."staging"."stg_specialites"
),

dimension_specialite as (
    select
        -- Clé substitut (génération séquentielle)
        row_number() over (order by code_specialite) as sk_specialite,
        
        -- Business key (max 10 caractères selon db.sql)
        left(code_specialite, 10) as code_specialite,
        
        -- Attributs descriptifs
        fonction,
        specialite,
        categorie,  -- 30+ catégories (Medecine generale, Medecine specialisee, Soins infirmiers, etc.)
        
        -- Métadonnées
        loaded_at as date_chargement
        
    from specialites_source
)

select * from dimension_specialite
order by sk_specialite