

-- Data Mart : Analyse territoriale
-- Optimisé pour Power BI avec focus sur décès et satisfaction par région
-- Grain : 1 ligne = 1 combinaison (région, période, indicateur)

with deces_base as (
    select 
        fd.sk_temps,
        fd.sk_localisation,
        fd.sk_patient,
        
        -- Dimensions descriptives
        dt.date_complete,
        dt.annee,
        dt.trimestre,
        dt.mois,
        
        dl.region,
        dl.departement,
        dl.ville,
        dl.code_postal,
        
        dp.sexe,
        dp.tranche_age,
        dp.age,
        
        -- Mesures
        fd.nombre_deces
        
    from "staging"."dwh"."fait_deces" fd
    left join "staging"."dwh"."dim_temps" dt on fd.sk_temps = dt.sk_temps
    left join "staging"."dwh"."dim_localisation" dl on fd.sk_localisation = dl.sk_localisation
    left join "staging"."dwh"."dim_patient" dp on fd.sk_patient = dp.sk_patient
    where dl.region is not null and dl.region != 'Non renseigne'
),

satisfaction_base as (
    select 
        fs.sk_temps,
        fs.sk_etablissement,
        fs.sk_localisation,
        
        -- Dimensions descriptives
        dt.date_complete,
        dt.annee,
        dt.trimestre,
        dt.mois,
        
        de.region as region_etablissement,
        de.departement as departement_etablissement,
        de.nom_etablissement,
        
        -- Pas de sk_patient dans fait_satisfaction, on utilise des valeurs par défaut
        'I' as sexe,
        'Non renseigne' as tranche_age,
        0 as age,
        
        -- Mesures satisfaction (adaptées selon le modèle fait_satisfaction)
        fs.score_global as note_satisfaction,
        fs.nombre_reponses
        
    from "staging"."dwh"."fait_satisfaction" fs
    left join "staging"."dwh"."dim_temps" dt on fs.sk_temps = dt.sk_temps
    left join "staging"."dwh"."dim_etablissement" de on fs.sk_etablissement = de.sk_etablissement
    where de.region is not null and de.region != 'Non renseigne'
),

-- Agrégations décès par région
agreg_deces_region as (
    select 
        sk_temps,
        region,
        annee,
        trimestre,
        mois,
        date_complete,
        
        sum(nombre_deces) as nb_deces_region,
        count(distinct sk_patient) as nb_patients_deces_region,
        
        -- Détail par sexe
        sum(case when sexe = 'M' then nombre_deces else 0 end) as nb_deces_hommes,
        sum(case when sexe = 'F' then nombre_deces else 0 end) as nb_deces_femmes,
        
        -- Détail par tranche d'âge
        sum(case when tranche_age = '0-18' then nombre_deces else 0 end) as nb_deces_0_18,
        sum(case when tranche_age = '19-30' then nombre_deces else 0 end) as nb_deces_19_30,
        sum(case when tranche_age = '31-50' then nombre_deces else 0 end) as nb_deces_31_50,
        sum(case when tranche_age = '51-65' then nombre_deces else 0 end) as nb_deces_51_65,
        sum(case when tranche_age = '66+' then nombre_deces else 0 end) as nb_deces_66_plus
        
    from deces_base
    group by 1,2,3,4,5,6
),

-- Agrégations décès par département
agreg_deces_departement as (
    select 
        sk_temps,
        region,
        departement,
        annee,
        trimestre,
        mois,
        date_complete,
        
        sum(nombre_deces) as nb_deces_departement,
        count(distinct sk_patient) as nb_patients_deces_departement
        
    from deces_base
    group by 1,2,3,4,5,6,7
),

-- Agrégations satisfaction par région
agreg_satisfaction_region as (
    select 
        sk_temps,
        region_etablissement,
        annee,
        trimestre,
        mois,
        date_complete,
        
        sum(nombre_reponses) as nb_reponses_satisfaction,
        avg(note_satisfaction) as note_moyenne_satisfaction,
        0 as nb_patients_satisfaction,  -- Pas de sk_patient dans fait_satisfaction
        count(distinct sk_etablissement) as nb_etablissements_satisfaction,
        
        -- Détail par sexe
        sum(case when sexe = 'M' then nombre_reponses else 0 end) as nb_reponses_hommes,
        sum(case when sexe = 'F' then nombre_reponses else 0 end) as nb_reponses_femmes,
        avg(case when sexe = 'M' then note_satisfaction end) as note_moyenne_hommes,
        avg(case when sexe = 'F' then note_satisfaction end) as note_moyenne_femmes
        
    from satisfaction_base
    group by 1,2,3,4,5,6
),

-- Jointure finale pour analyse territoriale
final as (
    select 
        -- Clés temporelles
        coalesce(dr.sk_temps, sr.sk_temps) as sk_temps,
        coalesce(dr.date_complete, sr.date_complete) as date_complete,
        coalesce(dr.annee, sr.annee) as annee,
        coalesce(dr.trimestre, sr.trimestre) as trimestre,
        coalesce(dr.mois, sr.mois) as mois,
        
        -- Géographie
        coalesce(dr.region, sr.region_etablissement) as region,
        
        -- Indicateurs décès
        coalesce(dr.nb_deces_region, 0) as nb_deces_region,
        coalesce(dr.nb_patients_deces_region, 0) as nb_patients_deces_region,
        coalesce(dr.nb_deces_hommes, 0) as nb_deces_hommes,
        coalesce(dr.nb_deces_femmes, 0) as nb_deces_femmes,
        coalesce(dr.nb_deces_0_18, 0) as nb_deces_0_18,
        coalesce(dr.nb_deces_19_30, 0) as nb_deces_19_30,
        coalesce(dr.nb_deces_31_50, 0) as nb_deces_31_50,
        coalesce(dr.nb_deces_51_65, 0) as nb_deces_51_65,
        coalesce(dr.nb_deces_66_plus, 0) as nb_deces_66_plus,
        
        -- Indicateurs satisfaction
        coalesce(sr.nb_reponses_satisfaction, 0) as nb_reponses_satisfaction,
        coalesce(sr.note_moyenne_satisfaction, 0) as note_moyenne_satisfaction,
        0 as nb_patients_satisfaction,  -- Pas de sk_patient dans fait_satisfaction
        coalesce(sr.nb_etablissements_satisfaction, 0) as nb_etablissements_satisfaction,
        coalesce(sr.nb_reponses_hommes, 0) as nb_reponses_hommes,
        coalesce(sr.nb_reponses_femmes, 0) as nb_reponses_femmes,
        coalesce(sr.note_moyenne_hommes, 0) as note_moyenne_hommes,
        coalesce(sr.note_moyenne_femmes, 0) as note_moyenne_femmes,
        
        -- Métadonnées
        current_timestamp as date_chargement
        
    from agreg_deces_region dr
    full outer join agreg_satisfaction_region sr 
        on dr.sk_temps = sr.sk_temps and dr.region = sr.region_etablissement
    
    union all
    
    -- Ajouter les départements pour plus de granularité
    select 
        dd.sk_temps,
        dd.date_complete,
        dd.annee,
        dd.trimestre,
        dd.mois,
        dd.region,
        dd.nb_deces_departement as nb_deces_region,
        dd.nb_patients_deces_departement as nb_patients_deces_region,
        0 as nb_deces_hommes,
        0 as nb_deces_femmes,
        0 as nb_deces_0_18,
        0 as nb_deces_19_30,
        0 as nb_deces_31_50,
        0 as nb_deces_51_65,
        0 as nb_deces_66_plus,
        0 as nb_reponses_satisfaction,
        0 as note_moyenne_satisfaction,
        0 as nb_patients_satisfaction,
        0 as nb_etablissements_satisfaction,
        0 as nb_reponses_hommes,
        0 as nb_reponses_femmes,
        0 as note_moyenne_hommes,
        0 as note_moyenne_femmes,
        current_timestamp as date_chargement
        
    from agreg_deces_departement dd
)

select * from final