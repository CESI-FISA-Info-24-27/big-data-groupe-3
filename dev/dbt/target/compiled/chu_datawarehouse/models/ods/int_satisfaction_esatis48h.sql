

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