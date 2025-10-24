{{ 
    config(
        materialized='table',
        schema='datamart',
        tags=['datamart', 'kpi']
    )
}}

-- Datamart Consultations pour Power BI
select 
    fc.sk_temps,
    fc.sk_etablissement,
    fc.sk_diagnostic,
    fc.sk_professionnel,
    fc.sk_patient,
    
    -- Dimensions temporelles
    dt.date_complete,
    dt.annee,
    dt.trimestre,
    dt.mois,
    
    -- Dimensions établissement
    de.nom_etablissement,
    de.region as region_etablissement,
    de.categorie as type_etablissement,
    
    -- Dimensions diagnostic
    dd.code_diagnostic,
    dd.libelle_diagnostic,
    dd.categorie_cim10 as categorie_diagnostic,
    
    -- Dimensions professionnel
    dp.profession,
    ds.specialite,
    
    -- Métriques
    fc.nombre_consultations,
    fc.duree_consultation,
    
    current_timestamp as date_chargement

from {{ ref('fait_consultation') }} fc
left join {{ ref('dim_temps') }} dt on fc.sk_temps = dt.sk_temps
left join {{ ref('dim_etablissement') }} de on fc.sk_etablissement = de.sk_etablissement
left join {{ ref('dim_diagnostic') }} dd on fc.sk_diagnostic = dd.sk_diagnostic
left join {{ ref('dim_professionnel') }} dp on fc.sk_professionnel = dp.sk_professionnel
left join {{ ref('dim_specialite') }} ds on dp.fk_specialite = ds.sk_specialite

