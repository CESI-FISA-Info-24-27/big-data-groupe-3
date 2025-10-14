

-- Consolidation de toutes les tables satisfaction e-Satis
-- Prépare les données pour fait_satisfaction
-- Utilise des modèles intermédiaires pour uniformiser les structures

with  __dbt__cte__int_satisfaction_esatis48h as (


-- Mapping E-SATIS 48h vers structure unifiée
with esatis48h_2019 as (
    select
        -- Identifiants établissement
        trim(finess) as finess,
        trim(rs_finess) as nom_etablissement,
        trim(region) as region,
        
        -- Type enquête
        'E-SATIS 48h MCO' as type_enquete,
        2019 as annee_enquete,
        
        -- Scores standardisés (remplacer virgule par point pour format français)
        cast(replace(score_all_rea_ajust, ',', '.') as double) as score_global,
        cast(replace(cast(score_accueil_rea_ajust as varchar), ',', '.') as double) as score_accueil,
        cast(replace(cast(score_PECinf_rea_ajust as varchar), ',', '.') as double) as score_pec_infirmiers,
        cast(replace(cast(score_PECmed_rea_ajust as varchar), ',', '.') as double) as score_pec_medecins,
        cast(replace(cast(score_chambre_rea_ajust as varchar), ',', '.') as double) as score_chambre,
        cast(replace(cast(score_repas_rea_ajust as varchar), ',', '.') as double) as score_repas,
        cast(replace(cast(score_sortie_rea_ajust as varchar), ',', '.') as double) as score_sortie,
        
        -- Nombre de réponses
        nb_rep_score_all_rea_ajust as nombre_reponses,
        
        -- Classement et évolution
        trim(classement) as classement,
        trim(evolution) as evolution,
        
        -- Taux recommandation
        cast(replace(taux_reco_brut, ',', '.') as double) as taux_recommandation,
        nb_reco_brut as nb_recommandations
        
    from "staging"."raw"."satisfaction_2019_resultats_esatis48h_mco_open_data_2019"
    where finess is not null
),

esatis48h_2017 as (
    select
        -- Identifiants établissement
        trim(finess) as finess,
        trim(rs_finess) as nom_etablissement,
        trim(region) as region,
        
        -- Type enquête
        'E-SATIS 48h MCO' as type_enquete,
        2017 as annee_enquete,
        
        -- Scores standardisés (remplacer virgule par point)
        cast(replace(cast(score_all_rea_ajust as varchar), ',', '.') as double) as score_global,
        cast(replace(cast(score_accueil_rea_ajust as varchar), ',', '.') as double) as score_accueil,
        cast(replace(cast(score_PECinf_rea_ajust as varchar), ',', '.') as double) as score_pec_infirmiers,
        cast(replace(cast(score_PECmed_rea_ajust as varchar), ',', '.') as double) as score_pec_medecins,
        cast(replace(cast(score_chambre_rea_ajust as varchar), ',', '.') as double) as score_chambre,
        cast(replace(cast(score_repas_rea_ajust as varchar), ',', '.') as double) as score_repas,
        cast(replace(cast(score_sortie_rea_ajust as varchar), ',', '.') as double) as score_sortie,
        
        -- Nombre de réponses
        nb_rep_score_all_rea_ajust as nombre_reponses,
        
        -- Classement et évolution
        trim(classement) as classement,
        trim(evolution) as evolution,
        
        -- Pas de taux recommandation en 2017
        null::double as taux_recommandation,
        null::bigint as nb_recommandations
        
    from "staging"."raw"."satisfaction_esatis48h_mco_recueil2017_donnees"
    where finess is not null
),

all_esatis48h as (
    select * from esatis48h_2019
    union all
    select * from esatis48h_2017
)

select * from all_esatis48h
),  __dbt__cte__int_satisfaction_esatisca as (


-- Mapping E-SATIS CA vers structure unifiée
with esatisca_2019 as (
    select
        -- Identifiants établissement
        trim(finess) as finess,
        trim(rs_finess) as nom_etablissement,
        trim(region) as region,
        
        -- Type enquête
        'E-SATIS CA MCO' as type_enquete,
        2019 as annee_enquete,
        
        -- Scores (structure différente de 48h) - remplacer virgule par point
        cast(replace(score_all_ajust, ',', '.') as double) as score_global,
        cast(replace(score_ACC_ajust, ',', '.') as double) as score_accueil,
        cast(replace(score_PEC_ajust, ',', '.') as double) as score_pec,
        cast(replace(score_AVH_ajust, ',', '.') as double) as score_avant_hospitalisation,
        cast(replace(score_CER_ajust, ',', '.') as double) as score_ceremony,
        cast(replace(score_OVS_ajust, ',', '.') as double) as score_organisation_sortie,
        
        -- Nombre de réponses
        nb_rep_score_all_ajust as nombre_reponses,
        
        -- Classement et évolution
        trim(classement) as classement,
        trim(evolution) as evolution,
        
        -- Taux recommandation
        cast(replace(taux_reco_brut, ',', '.') as double) as taux_recommandation,
        nb_reco_brut as nb_recommandations
        
    from "staging"."raw"."satisfaction_2019_resultats_esatisca_mco_open_data_2019"
    where finess is not null
)

select * from esatisca_2019
), esatis48h as (
    select * from __dbt__cte__int_satisfaction_esatis48h
),

esatisca as (
    select * from __dbt__cte__int_satisfaction_esatisca
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