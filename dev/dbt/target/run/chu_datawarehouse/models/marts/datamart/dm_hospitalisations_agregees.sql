
  
    
    

    create  table
      "staging"."datamart"."dm_hospitalisations_agregees__dbt_tmp"
  
    as (
      

-- Data Mart : Hospitalisations agrégées
-- Optimisé pour Power BI avec pré-calculs des taux d'hospitalisation
-- Grain : 1 ligne = 1 combinaison (établissement, diagnostic, période, profil patient)

with hospitalisations_base as (
    select 
        fh.sk_temps,
        fh.sk_etablissement,
        fh.sk_diagnostic,
        fh.sk_patient,
        
        -- Dimensions descriptives
        dt.date_complete,
        dt.annee,
        dt.trimestre,
        dt.mois,
        
        de.nom_etablissement,
        de.region as region_etablissement,
        de.departement as departement_etablissement,
        
        dd.code_diagnostic,
        dd.libelle_diagnostic,
        dd.chapitre_cim10,
        dd.categorie_cim10,
        
        dp.sexe,
        dp.tranche_age,
        dp.age,
        
        -- Mesures
        fh.nombre_hospitalisations,
        fh.jour_hospitalisation
        
    from "staging"."dwh"."fait_hospitalisation" fh
    left join "staging"."dwh"."dim_temps" dt on fh.sk_temps = dt.sk_temps
    left join "staging"."dwh"."dim_etablissement" de on fh.sk_etablissement = de.sk_etablissement
    left join "staging"."dwh"."dim_diagnostic" dd on fh.sk_diagnostic = dd.sk_diagnostic
    left join "staging"."dwh"."dim_patient" dp on fh.sk_patient = dp.sk_patient
),

-- Agrégations par établissement
agreg_etablissement as (
    select 
        sk_temps,
        sk_etablissement,
        nom_etablissement,
        region_etablissement,
        departement_etablissement,
        annee,
        trimestre,
        mois,
        date_complete,
        
        sum(nombre_hospitalisations) as nb_hospitalisations_etablissement,
        sum(jour_hospitalisation) as duree_totale_etablissement,
        count(distinct sk_patient) as nb_patients_uniques_etablissement,
        avg(jour_hospitalisation) as duree_moyenne_etablissement
        
    from hospitalisations_base
    group by 1,2,3,4,5,6,7,8,9
),

-- Agrégations par diagnostic
agreg_diagnostic as (
    select 
        sk_temps,
        sk_etablissement,
        sk_diagnostic,
        code_diagnostic,
        libelle_diagnostic,
        chapitre_cim10,
        categorie_cim10,
        annee,
        trimestre,
        mois,
        date_complete,
        
        sum(nombre_hospitalisations) as nb_hospitalisations_diagnostic,
        sum(jour_hospitalisation) as duree_totale_diagnostic,
        count(distinct sk_patient) as nb_patients_uniques_diagnostic,
        avg(jour_hospitalisation) as duree_moyenne_diagnostic
        
    from hospitalisations_base
    group by 1,2,3,4,5,6,7,8,9,10,11
),

-- Agrégations par profil patient (sexe/âge)
agreg_patient as (
    select 
        sk_temps,
        sexe,
        tranche_age,
        age,
        annee,
        trimestre,
        mois,
        date_complete,
        
        sum(nombre_hospitalisations) as nb_hospitalisations_profil,
        sum(jour_hospitalisation) as duree_totale_profil,
        count(distinct sk_patient) as nb_patients_uniques_profil,
        count(distinct sk_etablissement) as nb_etablissements_profil,
        avg(jour_hospitalisation) as duree_moyenne_profil
        
    from hospitalisations_base
    where sexe != 'I' and tranche_age != 'Non renseigne'  -- Exclure les valeurs inconnues
    group by 1,2,3,4,5,6,7,8
),

-- Agrégations par région (pour analyse territoriale)
agreg_region as (
    select 
        sk_temps,
        region_etablissement,
        annee,
        trimestre,
        mois,
        date_complete,
        
        sum(nombre_hospitalisations) as nb_hospitalisations_region,
        sum(jour_hospitalisation) as duree_totale_region,
        count(distinct sk_patient) as nb_patients_uniques_region,
        count(distinct sk_etablissement) as nb_etablissements_region,
        avg(jour_hospitalisation) as duree_moyenne_region
        
    from hospitalisations_base
    where region_etablissement is not null and region_etablissement != 'Non renseigne'
    group by 1,2,3,4,5,6
),

-- Jointure finale avec toutes les agrégations
final as (
    select 
        -- Clés temporelles
        hb.sk_temps,
        hb.date_complete,
        hb.annee,
        hb.trimestre,
        hb.mois,
        
        -- Clés et libellés établissement
        hb.sk_etablissement,
        hb.nom_etablissement,
        hb.region_etablissement,
        hb.departement_etablissement,
        
        -- Clés et libellés diagnostic
        hb.sk_diagnostic,
        hb.code_diagnostic,
        hb.libelle_diagnostic,
        hb.chapitre_cim10,
        hb.categorie_cim10,
        
        -- Profil patient
        hb.sexe,
        hb.tranche_age,
        hb.age,
        
        -- Mesures agrégées par établissement
        coalesce(ae.nb_hospitalisations_etablissement, 0) as nb_hospitalisations_etablissement,
        coalesce(ae.duree_totale_etablissement, 0) as duree_totale_etablissement,
        coalesce(ae.nb_patients_uniques_etablissement, 0) as nb_patients_uniques_etablissement,
        coalesce(ae.duree_moyenne_etablissement, 0) as duree_moyenne_etablissement,
        
        -- Mesures agrégées par diagnostic
        coalesce(ad.nb_hospitalisations_diagnostic, 0) as nb_hospitalisations_diagnostic,
        coalesce(ad.duree_totale_diagnostic, 0) as duree_totale_diagnostic,
        coalesce(ad.nb_patients_uniques_diagnostic, 0) as nb_patients_uniques_diagnostic,
        coalesce(ad.duree_moyenne_diagnostic, 0) as duree_moyenne_diagnostic,
        
        -- Mesures agrégées par profil patient
        coalesce(apat.nb_hospitalisations_profil, 0) as nb_hospitalisations_profil,
        coalesce(apat.duree_totale_profil, 0) as duree_totale_profil,
        coalesce(apat.nb_patients_uniques_profil, 0) as nb_patients_uniques_profil,
        coalesce(apat.duree_moyenne_profil, 0) as duree_moyenne_profil,
        
        -- Mesures agrégées par région
        coalesce(areg.nb_hospitalisations_region, 0) as nb_hospitalisations_region,
        coalesce(areg.duree_totale_region, 0) as duree_totale_region,
        coalesce(areg.nb_patients_uniques_region, 0) as nb_patients_uniques_region,
        coalesce(areg.duree_moyenne_region, 0) as duree_moyenne_region,
        
        -- Métadonnées
        current_timestamp as date_chargement
        
    from hospitalisations_base hb
    left join agreg_etablissement ae on hb.sk_temps = ae.sk_temps and hb.sk_etablissement = ae.sk_etablissement
    left join agreg_diagnostic ad on hb.sk_temps = ad.sk_temps and hb.sk_etablissement = ad.sk_etablissement and hb.sk_diagnostic = ad.sk_diagnostic
    left join agreg_patient apat on hb.sk_temps = apat.sk_temps and hb.sexe = apat.sexe and hb.tranche_age = apat.tranche_age
    left join agreg_region areg on hb.sk_temps = areg.sk_temps and hb.region_etablissement = areg.region_etablissement
)

select * from final
    );
  
  