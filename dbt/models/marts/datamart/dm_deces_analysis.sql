{{ config(
    materialized='table',
    schema='datamart',
    tags=['datamart', 'kpi']
) }}

with deces_2019 as (
    select 
        fd.sk_temps,
        fd.sk_localisation,
        dt.annee,
        dt.trimestre,
        dt.mois,
        dt.date_complete,
        dl.region,
        dl.departement,
        fd.nombre_deces
    from {{ ref('fait_deces') }} fd
    left join {{ ref('dim_temps') }} dt on fd.sk_temps = dt.sk_temps
    left join {{ ref('dim_localisation') }} dl on fd.sk_localisation = dl.sk_localisation
    where dt.annee = 2019
      and dl.region is not null 
      and dl.region != 'Non renseigne'
)

select 
    sk_temps,
    annee,
    trimestre,
    mois,
    date_complete,
    region,
    departement,
    sum(nombre_deces) as nb_deces_departement,
    current_timestamp as date_chargement
from deces_2019
group by 1,2,3,4,5,6,7