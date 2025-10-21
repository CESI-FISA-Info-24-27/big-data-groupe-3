{{
    config(
        materialized='table',
        tags=['datamart', 'consultations', 'light']
    )
}}

-- Data Mart LÉGER : Consultations agrégées (version allégée)
-- Seulement les données essentielles pour Power BI
-- Grain : 1 ligne = 1 combinaison (établissement, diagnostic, période)

with consultations_base as (
    select 
        fc.sk_temps,
        fc.sk_diagnostic,
        fc.sk_patient,
        
        -- Dimensions descriptives essentielles
        dt.annee,
        dt.trimestre,
        dt.mois,
        
        dd.code_diagnostic,
        dd.libelle_diagnostic,
        dd.chapitre_cim10,
        
        dp2.sexe,
        dp2.tranche_age,
        
        -- Mesures essentielles
        fc.nombre_consultations,
        fc.duree_consultation
        
    from {{ ref('fait_consultation') }} fc
    left join {{ ref('dim_temps') }} dt on fc.sk_temps = dt.sk_temps
    left join {{ ref('dim_diagnostic') }} dd on fc.sk_diagnostic = dd.sk_diagnostic
    left join {{ ref('dim_patient') }} dp2 on fc.sk_patient = dp2.sk_patient
    where dt.annee >= 2020  -- Seulement les 2 dernières années
),

-- Agrégations simplifiées
agregations as (
    select 
        annee,
        trimestre,
        mois,
        code_diagnostic,
        libelle_diagnostic,
        chapitre_cim10,
        sexe,
        tranche_age,
        
        sum(nombre_consultations) as nb_consultations,
        sum(duree_consultation) as duree_totale,
        count(distinct sk_patient) as nb_patients_uniques,
        avg(duree_consultation) as duree_moyenne
        
    from consultations_base
    group by 1,2,3,4,5,6,7,8
),

final as (
    select 
        -- Clés temporelles
        (annee * 10000 + trimestre * 100 + mois) as sk_temps,
        annee,
        trimestre,
        mois,
        
        -- Diagnostic
        code_diagnostic,
        libelle_diagnostic,
        chapitre_cim10,
        
        -- Profil patient
        sexe,
        tranche_age,
        
        -- Mesures
        nb_consultations,
        duree_totale,
        nb_patients_uniques,
        duree_moyenne,
        
        -- Métadonnées
        current_timestamp as date_chargement
        
    from agregations
)

select * from final
