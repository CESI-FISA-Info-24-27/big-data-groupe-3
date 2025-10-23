{{
    config(
        materialized='table',
        tags=['fait', 'dwh', 'satisfaction']
    )
}}

with satisfaction_source as (
    select * from {{ ref('ods_satisfaction_unifie') }}
),

dim_etablissement as (
    select * from {{ ref('dim_etablissement') }}
),

fait_satisfaction as (
    select
        row_number() over (order by s.finess, s.annee_enquete) as sk_fait_satisfaction,
        
        -- Logique en cascade pour trouver l'établissement
        coalesce(
            -- 1. Recherche dans finess_site
            (select de1.sk_etablissement 
             from dim_etablissement de1 
             where de1.finess_site like '%' || s.finess || '%'
             limit 1),
            
            -- 2. Recherche dans finess
            (select de2.sk_etablissement 
             from dim_etablissement de2 
             where de2.finess like '%' || s.finess || '%'
             limit 1),
            
            -- 3. Recherche dans finess_etablissement_juridique
            (select de3.sk_etablissement 
             from dim_etablissement de3 
             where de3.finess_etablissement_juridique like '%' || s.finess || '%'
             limit 1),
            
            -- 4. Valeur par défaut si rien n'est trouvé
            -1
        ) as sk_etablissement,
        
        s.region,
        s.annee_enquete,
        s.score_global,
        s.score_accueil,
        s.score_pec_1 as score_pec_infirmiers,
        s.score_pec_2 as score_pec_medecins,
        s.score_chambre,
        s.score_repas,
        s.score_sortie,
        s.taux_recommandation,
        s.nombre_reponses,
        s.classement,
        s.evolution,
        s.loaded_at as date_chargement
        
    from satisfaction_source s
)

select * from fait_satisfaction
order by sk_fait_satisfaction


