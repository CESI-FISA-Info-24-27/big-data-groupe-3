{{
    config(
        materialized='table',
        tags=['dimension', 'dwh', 'temps']
    )
}}

-- Génération de la dimension temps (2015-2030)
-- Clé primaire : sk_temps au format YYYYMMDD
-- Contient tous les attributs temporels + jours fériés français

with date_range as (
    -- Générer toutes les dates entre 2015-01-01 et 2030-12-31
    select 
        cast(unnest(generate_series(
            date '2015-01-01',
            date '2030-12-31',
            interval '1 day'
        )) as date) as date_complete
),

-- Jours fériés français (fixes)
jours_feries_fixes as (
    select date_val as date_ferie, nom_ferie
    from (values
        -- 2015-2030 : jours fériés fixes
        ('2015-01-01'::date, 'Nouvel An'), ('2015-05-01'::date, 'Fête du Travail'), ('2015-05-08'::date, 'Victoire 1945'),
        ('2015-07-14'::date, 'Fête Nationale'), ('2015-08-15'::date, 'Assomption'), ('2015-11-01'::date, 'Toussaint'),
        ('2015-11-11'::date, 'Armistice 1918'), ('2015-12-25'::date, 'Noël'),
        
        ('2016-01-01'::date, 'Nouvel An'), ('2016-05-01'::date, 'Fête du Travail'), ('2016-05-08'::date, 'Victoire 1945'),
        ('2016-07-14'::date, 'Fête Nationale'), ('2016-08-15'::date, 'Assomption'), ('2016-11-01'::date, 'Toussaint'),
        ('2016-11-11'::date, 'Armistice 1918'), ('2016-12-25'::date, 'Noël'),
        
        ('2017-01-01'::date, 'Nouvel An'), ('2017-05-01'::date, 'Fête du Travail'), ('2017-05-08'::date, 'Victoire 1945'),
        ('2017-07-14'::date, 'Fête Nationale'), ('2017-08-15'::date, 'Assomption'), ('2017-11-01'::date, 'Toussaint'),
        ('2017-11-11'::date, 'Armistice 1918'), ('2017-12-25'::date, 'Noël'),
        
        ('2018-01-01'::date, 'Nouvel An'), ('2018-05-01'::date, 'Fête du Travail'), ('2018-05-08'::date, 'Victoire 1945'),
        ('2018-07-14'::date, 'Fête Nationale'), ('2018-08-15'::date, 'Assomption'), ('2018-11-01'::date, 'Toussaint'),
        ('2018-11-11'::date, 'Armistice 1918'), ('2018-12-25'::date, 'Noël'),
        
        ('2019-01-01'::date, 'Nouvel An'), ('2019-05-01'::date, 'Fête du Travail'), ('2019-05-08'::date, 'Victoire 1945'),
        ('2019-07-14'::date, 'Fête Nationale'), ('2019-08-15'::date, 'Assomption'), ('2019-11-01'::date, 'Toussaint'),
        ('2019-11-11'::date, 'Armistice 1918'), ('2019-12-25'::date, 'Noël'),
        
        ('2020-01-01'::date, 'Nouvel An'), ('2020-05-01'::date, 'Fête du Travail'), ('2020-05-08'::date, 'Victoire 1945'),
        ('2020-07-14'::date, 'Fête Nationale'), ('2020-08-15'::date, 'Assomption'), ('2020-11-01'::date, 'Toussaint'),
        ('2020-11-11'::date, 'Armistice 1918'), ('2020-12-25'::date, 'Noël'),
        
        ('2021-01-01'::date, 'Nouvel An'), ('2021-05-01'::date, 'Fête du Travail'), ('2021-05-08'::date, 'Victoire 1945'),
        ('2021-07-14'::date, 'Fête Nationale'), ('2021-08-15'::date, 'Assomption'), ('2021-11-01'::date, 'Toussaint'),
        ('2021-11-11'::date, 'Armistice 1918'), ('2021-12-25'::date, 'Noël'),
        
        ('2022-01-01'::date, 'Nouvel An'), ('2022-05-01'::date, 'Fête du Travail'), ('2022-05-08'::date, 'Victoire 1945'),
        ('2022-07-14'::date, 'Fête Nationale'), ('2022-08-15'::date, 'Assomption'), ('2022-11-01'::date, 'Toussaint'),
        ('2022-11-11'::date, 'Armistice 1918'), ('2022-12-25'::date, 'Noël'),
        
        ('2023-01-01'::date, 'Nouvel An'), ('2023-05-01'::date, 'Fête du Travail'), ('2023-05-08'::date, 'Victoire 1945'),
        ('2023-07-14'::date, 'Fête Nationale'), ('2023-08-15'::date, 'Assomption'), ('2023-11-01'::date, 'Toussaint'),
        ('2023-11-11'::date, 'Armistice 1918'), ('2023-12-25'::date, 'Noël'),
        
        ('2024-01-01'::date, 'Nouvel An'), ('2024-05-01'::date, 'Fête du Travail'), ('2024-05-08'::date, 'Victoire 1945'),
        ('2024-07-14'::date, 'Fête Nationale'), ('2024-08-15'::date, 'Assomption'), ('2024-11-01'::date, 'Toussaint'),
        ('2024-11-11'::date, 'Armistice 1918'), ('2024-12-25'::date, 'Noël'),
        
        ('2025-01-01'::date, 'Nouvel An'), ('2025-05-01'::date, 'Fête du Travail'), ('2025-05-08'::date, 'Victoire 1945'),
        ('2025-07-14'::date, 'Fête Nationale'), ('2025-08-15'::date, 'Assomption'), ('2025-11-01'::date, 'Toussaint'),
        ('2025-11-11'::date, 'Armistice 1918'), ('2025-12-25'::date, 'Noël')
    ) as t(date_val, nom_ferie)
),

-- Jours fériés mobiles (Pâques, Ascension, Pentecôte) - années principales
jours_feries_mobiles as (
    select date_val as date_ferie, nom_ferie
    from (values
        -- 2015
        ('2015-04-06'::date, 'Lundi de Pâques'), ('2015-05-14'::date, 'Ascension'), ('2015-05-25'::date, 'Lundi de Pentecôte'),
        -- 2016
        ('2016-03-28'::date, 'Lundi de Pâques'), ('2016-05-05'::date, 'Ascension'), ('2016-05-16'::date, 'Lundi de Pentecôte'),
        -- 2017
        ('2017-04-17'::date, 'Lundi de Pâques'), ('2017-05-25'::date, 'Ascension'), ('2017-06-05'::date, 'Lundi de Pentecôte'),
        -- 2018
        ('2018-04-02'::date, 'Lundi de Pâques'), ('2018-05-10'::date, 'Ascension'), ('2018-05-21'::date, 'Lundi de Pentecôte'),
        -- 2019
        ('2019-04-22'::date, 'Lundi de Pâques'), ('2019-05-30'::date, 'Ascension'), ('2019-06-10'::date, 'Lundi de Pentecôte'),
        -- 2020
        ('2020-04-13'::date, 'Lundi de Pâques'), ('2020-05-21'::date, 'Ascension'), ('2020-06-01'::date, 'Lundi de Pentecôte'),
        -- 2021
        ('2021-04-05'::date, 'Lundi de Pâques'), ('2021-05-13'::date, 'Ascension'), ('2021-05-24'::date, 'Lundi de Pentecôte'),
        -- 2022
        ('2022-04-18'::date, 'Lundi de Pâques'), ('2022-05-26'::date, 'Ascension'), ('2022-06-06'::date, 'Lundi de Pentecôte'),
        -- 2023
        ('2023-04-10'::date, 'Lundi de Pâques'), ('2023-05-18'::date, 'Ascension'), ('2023-05-29'::date, 'Lundi de Pentecôte'),
        -- 2024
        ('2024-04-01'::date, 'Lundi de Pâques'), ('2024-05-09'::date, 'Ascension'), ('2024-05-20'::date, 'Lundi de Pentecôte'),
        -- 2025
        ('2025-04-21'::date, 'Lundi de Pâques'), ('2025-05-29'::date, 'Ascension'), ('2025-06-09'::date, 'Lundi de Pentecôte')
    ) as t(date_val, nom_ferie)
),

-- Union de tous les jours fériés
tous_jours_feries as (
    select * from jours_feries_fixes
    union all
    select * from jours_feries_mobiles
),

-- Construction de la dimension temps complète
dimension_temps as (
    select
        -- Clé primaire : format YYYYMMDD (ex: 20241207)
        cast(strftime(d.date_complete, '%Y%m%d') as bigint) as sk_temps,
        
        -- Date complète
        d.date_complete,
        
        -- Décompositions temporelles
        extract(day from d.date_complete) as jour,
        extract(month from d.date_complete) as mois,
        cast(ceil(extract(month from d.date_complete) / 3.0) as integer) as trimestre,
        cast(ceil(extract(month from d.date_complete) / 6.0) as integer) as semestre,
        extract(year from d.date_complete) as annee,
        extract(week from d.date_complete) as semaine_annee,
        -- jour_semaine : 1=Lundi ... 7=Dimanche (selon db.sql ligne 186)
        case 
            when extract(dayofweek from d.date_complete) = 0 then 7  -- Dimanche = 7
            else extract(dayofweek from d.date_complete)  -- Lundi=1 ... Samedi=6
        end as jour_semaine,
        
        -- Libellés
        case 
            when extract(dayofweek from d.date_complete) = 0 then 'Dimanche'
            when extract(dayofweek from d.date_complete) = 1 then 'Lundi'
            when extract(dayofweek from d.date_complete) = 2 then 'Mardi'
            when extract(dayofweek from d.date_complete) = 3 then 'Mercredi'
            when extract(dayofweek from d.date_complete) = 4 then 'Jeudi'
            when extract(dayofweek from d.date_complete) = 5 then 'Vendredi'
            when extract(dayofweek from d.date_complete) = 6 then 'Samedi'
        end as nom_jour,
        
        case extract(month from d.date_complete)
            when 1 then 'Janvier'
            when 2 then 'Fevrier'
            when 3 then 'Mars'
            when 4 then 'Avril'
            when 5 then 'Mai'
            when 6 then 'Juin'
            when 7 then 'Juillet'
            when 8 then 'Aout'
            when 9 then 'Septembre'
            when 10 then 'Octobre'
            when 11 then 'Novembre'
            when 12 then 'Decembre'
        end as nom_mois,
        
        -- Indicateurs booléens
        extract(dayofweek from d.date_complete) in (0, 6) as est_weekend,
        case when jf.date_ferie is not null then true else false end as est_ferie,
        
        -- Saison
        case
            when extract(month from d.date_complete) in (3, 4, 5) then 'Printemps'
            when extract(month from d.date_complete) in (6, 7, 8) then 'Ete'
            when extract(month from d.date_complete) in (9, 10, 11) then 'Automne'
            else 'Hiver'
        end as saison,
        
        -- Métadonnées
        current_timestamp as date_chargement
        
    from date_range d
    left join tous_jours_feries jf on d.date_complete = jf.date_ferie
)

select * from dimension_temps
order by sk_temps

