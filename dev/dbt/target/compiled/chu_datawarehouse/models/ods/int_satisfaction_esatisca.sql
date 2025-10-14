

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