{{ config(
    materialized='table',
    schema='datamart',
    tags=['datamart', 'kpi']
) }}

with satisfaction_2020 as (
    select 
        fs.sk_etablissement,
        fs.annee_enquete as annee,
        coalesce(fs.region, de.region) as region,
        fs.score_global as note_satisfaction,
        fs.nombre_reponses,
        fs.taux_recommandation,
        de.nom_etablissement
    from {{ ref('fait_satisfaction') }} fs
    left join {{ ref('dim_etablissement') }} de on fs.sk_etablissement = de.sk_etablissement
    where fs.annee_enquete = 2020
      and coalesce(fs.region, de.region) is not null 
      and coalesce(fs.region, de.region) != 'Non renseigne'
)

select 
    20200101 as sk_temps,
    2020 as annee,
    1 as trimestre,
    1 as mois,
    cast('2020-01-01' as date) as date_complete,
    region,
    count(distinct sk_etablissement) as nb_etablissements_region,
    sum(nombre_reponses) as nb_reponses_totales_region,
    sum(note_satisfaction * nombre_reponses) / nullif(sum(nombre_reponses),0) as taux_satisfaction_moyen_region,
    sum(taux_recommandation * nombre_reponses) / nullif(sum(nombre_reponses),0) as taux_recommandation_moyen_region,
    min(note_satisfaction) as note_min_region,
    max(note_satisfaction) as note_max_region,
    avg(note_satisfaction) as note_moyenne_simple_region,
    current_timestamp as date_chargement
from satisfaction_2020
group by region

