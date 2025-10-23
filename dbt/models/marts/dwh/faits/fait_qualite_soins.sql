{{
    config(
        materialized='table',
        tags=['fait', 'dwh', 'qualite']
    )
}}

with qualite_source as (
    select * from {{ ref('ods_qualite_soins_unifie') }}
),

dim_etablissement as (
    select * from {{ ref('dim_etablissement') }}
),

fait_qualite_soins as (
    select
        row_number() over (order by q.finess, q.annee_enquete) as sk_fait_qualite,
        
        -- Logique en cascade pour trouver l'établissement
        coalesce(
            -- 1. Recherche dans finess_site
            (select de1.sk_etablissement 
             from dim_etablissement de1 
             where de1.finess_site like '%' || q.finess || '%'
             limit 1),
            
            -- 2. Recherche dans finess
            (select de2.sk_etablissement 
             from dim_etablissement de2 
             where de2.finess like '%' || q.finess || '%'
             limit 1),
            
            -- 3. Recherche dans finess_etablissement_juridique
            (select de3.sk_etablissement 
             from dim_etablissement de3 
             where de3.finess_etablissement_juridique like '%' || q.finess || '%'
             limit 1),
            
            -- 4. Valeur par défaut si rien n'est trouvé
            -1
        ) as sk_etablissement,
        
        q.region,
        q.annee_enquete,
        q.annee_donnee,
        q.ratio_ete_ortho,
        q.alerte_ete,
        q.cible,
        q.observations,
        q.attendu,
        q.position_seuil,
        q.loaded_at as date_chargement
        
    from qualite_source q
)

select * from fait_qualite_soins
order by sk_fait_qualite


