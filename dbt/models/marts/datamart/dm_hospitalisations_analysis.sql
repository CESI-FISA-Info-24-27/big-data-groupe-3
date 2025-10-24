{{ config(
    materialized='table',
    schema='datamart',
    tags=['datamart', 'kpi']
) }}

-- Datamart Hospitalisations pour Power BI
select 
    fh.sk_temps,
    fh.sk_etablissement,
    fh.sk_diagnostic,
    fh.sk_patient,
    
    -- Dimensions temporelles
    dt.date_complete,
    dt.annee,
    dt.trimestre,
    dt.mois,
    
    -- Dimensions établissement
    de.nom_etablissement,
    de.region as region_etablissement,
    
    -- Dimensions diagnostic
    dd.code_diagnostic,
    dd.libelle_diagnostic,
    
    -- Dimensions patient
    dp.sexe,
    dp.tranche_age,
    
    -- Métriques
    fh.nombre_hospitalisations,
    fh.jour_hospitalisation,
    
    current_timestamp as date_chargement

from {{ ref('fait_hospitalisation') }} fh
left join {{ ref('dim_temps') }} dt on fh.sk_temps = dt.sk_temps
left join {{ ref('dim_etablissement') }} de on fh.sk_etablissement = de.sk_etablissement
left join {{ ref('dim_diagnostic') }} dd on fh.sk_diagnostic = dd.sk_diagnostic
left join {{ ref('dim_patient') }} dp on fh.sk_patient = dp.sk_patient

