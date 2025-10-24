{{
    config(
        materialized='ephemeral',
        tags=['intermediate', 'satisfaction']
    )
}}

-- Mapping E-SATIS CA vers structure unifiée
with esatisca_2020 as (
    select
        trim(finess) as finess,
        trim(rs_finess) as nom_etablissement,
        trim(region) as region,
        'E-SATIS CA MCO' as type_enquete,
        2020 as annee_enquete,
        
        -- Tout caster en varchar pour 2020
        cast(replace(cast(score_all_ajust as varchar), ',', '.') as double) as score_global,
        cast(replace(cast(score_ACC_ajust as varchar), ',', '.') as double) as score_accueil,
        cast(replace(cast(score_PEC_ajust as varchar), ',', '.') as double) as score_pec,
        cast(replace(cast(score_AVH_ajust as varchar), ',', '.') as double) as score_avant_hospitalisation,
        cast(replace(cast(score_CER_ajust as varchar), ',', '.') as double) as score_ceremony,
        cast(replace(cast(score_OVS_ajust as varchar), ',', '.') as double) as score_organisation_sortie,
        nb_rep_score_all_ajust as nombre_reponses,
        trim(classement) as classement,
        trim(evolution) as evolution,
        cast(replace(cast(taux_reco_brut as varchar), ',', '.') as double) as taux_recommandation,
        nb_reco_brut as nb_recommandations
    from {{ source('raw', 'satisfaction_2020_resultats_esatisca_mco_open_data_2020') }}
    where finess is not null
),

esatisca_2019 as (
    select
        trim(finess) as finess,
        trim(rs_finess) as nom_etablissement,
        trim(region) as region,
        'E-SATIS CA MCO' as type_enquete,
        2019 as annee_enquete,
        cast(replace(score_all_ajust, ',', '.') as double) as score_global,
        cast(replace(score_ACC_ajust, ',', '.') as double) as score_accueil,
        cast(replace(score_PEC_ajust, ',', '.') as double) as score_pec,
        cast(replace(score_AVH_ajust, ',', '.') as double) as score_avant_hospitalisation,
        cast(replace(score_CER_ajust, ',', '.') as double) as score_ceremony,
        cast(replace(score_OVS_ajust, ',', '.') as double) as score_organisation_sortie,
        nb_rep_score_all_ajust as nombre_reponses,
        trim(classement) as classement,
        trim(evolution) as evolution,
        cast(replace(taux_reco_brut, ',', '.') as double) as taux_recommandation,
        nb_reco_brut as nb_recommandations
    from {{ source('raw', 'satisfaction_2019_resultats_esatisca_mco_open_data_2019') }}
    where finess is not null
)

select * from esatisca_2020
union all
select * from esatisca_2019
