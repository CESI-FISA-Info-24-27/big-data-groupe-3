{{
    config(
        materialized='table',
        tags=['ods', 'core', 'satisfaction']
    )
}}

-- Consolidation de toutes les tables satisfaction e-Satis
-- Prépare les données pour fait_satisfaction
-- Utilise des modèles intermédiaires pour uniformiser les structures

with esatis48h as (
    select * from {{ ref('int_satisfaction_esatis48h') }}
),

esatisca as (
    select * from {{ ref('int_satisfaction_esatisca') }}
),

-- Standardiser vers structure commune pour UNION
esatis48h_standard as (
    select
        finess,
        nom_etablissement,
        region,
        type_enquete,
        annee_enquete,
        
        -- Scores normalisés
        score_global,
        score_accueil,
        score_pec_infirmiers as score_pec_1,
        score_pec_medecins as score_pec_2,
        score_chambre,
        score_repas,
        score_sortie,
        null::double as score_extra_1,
        null::double as score_extra_2,
        
        nombre_reponses,
        classement,
        evolution,
        taux_recommandation,
        nb_recommandations
        
    from esatis48h
),

esatisca_standard as (
    select
        finess,
        nom_etablissement,
        region,
        type_enquete,
        annee_enquete,
        
        -- Scores normalisés
        score_global,
        score_accueil,
        score_pec as score_pec_1,
        null::double as score_pec_2,
        null::double as score_chambre,
        null::double as score_repas,
        score_organisation_sortie as score_sortie,
        score_avant_hospitalisation as score_extra_1,
        score_ceremony as score_extra_2,
        
        nombre_reponses,
        classement,
        evolution,
        taux_recommandation,
        nb_recommandations
        
    from esatisca
),

all_satisfaction as (
    select * from esatis48h_standard
    union all
    select * from esatisca_standard
)

select
    *,
    current_timestamp as loaded_at
from all_satisfaction
