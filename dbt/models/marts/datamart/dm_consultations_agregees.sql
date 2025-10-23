{{
    config(
        materialized='table',
        tags=['datamart', 'consultations', 'agregees']
    )
}}

-- Data Mart : Consultations agrégées
-- Optimisé pour Power BI avec pré-calculs des taux
-- Grain : 1 ligne = 1 combinaison (établissement, diagnostic, période, professionnel)

with consultations_base as (
    select 
        fc.sk_temps,
        fc.sk_diagnostic,
        fc.sk_professionnel,
        fc.sk_patient,
        fc.sk_mutuelle,
        
        -- Dimensions descriptives
        dt.date_complete,
        dt.annee,
        dt.trimestre,
        dt.mois,
        
        -- Pas de sk_etablissement dans fait_consultation, on utilise -1 (Inconnu)
        -1 as sk_etablissement,
        'Etablissement Inconnu' as nom_etablissement,
        'Non renseigne' as region_etablissement,
        '00' as departement_etablissement,
        
        dd.code_diagnostic,
        dd.libelle_diagnostic,
        dd.chapitre_cim10,
        dd.categorie_cim10,
        
        dp.nom_anonyme as nom_professionnel,
        dp.prenom_anonyme as prenom_professionnel,
        ds.specialite,
        ds.fonction,
        
        dp2.sexe,
        dp2.tranche_age,
        dp2.age,
        
        -- Mesures
        fc.nombre_consultations,
        fc.duree_consultation
        
    from {{ ref('fait_consultation') }} fc
    left join {{ ref('dim_temps') }} dt on fc.sk_temps = dt.sk_temps
    left join {{ ref('dim_diagnostic') }} dd on fc.sk_diagnostic = dd.sk_diagnostic
    left join {{ ref('dim_professionnel') }} dp on fc.sk_professionnel = dp.sk_professionnel
    left join {{ ref('dim_specialite') }} ds on dp.fk_specialite = ds.sk_specialite
    left join {{ ref('dim_patient') }} dp2 on fc.sk_patient = dp2.sk_patient
    where dp.est_actuel = true  -- Version actuelle du professionnel
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
        
        sum(nombre_consultations) as nb_consultations_etablissement,
        sum(duree_consultation) as duree_totale_etablissement,
        count(distinct sk_patient) as nb_patients_uniques_etablissement,
        count(distinct sk_professionnel) as nb_professionnels_etablissement
        
    from consultations_base
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
        
        sum(nombre_consultations) as nb_consultations_diagnostic,
        sum(duree_consultation) as duree_totale_diagnostic,
        count(distinct sk_patient) as nb_patients_uniques_diagnostic
        
    from consultations_base
    group by 1,2,3,4,5,6,7,8,9,10,11
),

-- Agrégations par professionnel
agreg_professionnel as (
    select 
        sk_temps,
        sk_professionnel,
        nom_professionnel,
        prenom_professionnel,
        specialite,
        fonction,
        annee,
        trimestre,
        mois,
        date_complete,
        
        sum(nombre_consultations) as nb_consultations_professionnel,
        sum(duree_consultation) as duree_totale_professionnel,
        count(distinct sk_patient) as nb_patients_uniques_professionnel,
        count(distinct sk_etablissement) as nb_etablissements_professionnel
        
    from consultations_base
    group by 1,2,3,4,5,6,7,8,9,10
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
        
        sum(nombre_consultations) as nb_consultations_profil,
        sum(duree_consultation) as duree_totale_profil,
        count(distinct sk_patient) as nb_patients_uniques_profil,
        count(distinct sk_etablissement) as nb_etablissements_profil
        
    from consultations_base
    where sexe != 'I' and tranche_age != 'Non renseigne'  -- Exclure les valeurs inconnues
    group by 1,2,3,4,5,6,7,8
),

-- Jointure finale avec toutes les agrégations
final as (
    select 
        -- Clés temporelles
        cb.sk_temps,
        cb.date_complete,
        cb.annee,
        cb.trimestre,
        cb.mois,
        
        -- Clés et libellés établissement
        cb.sk_etablissement,
        cb.nom_etablissement,
        cb.region_etablissement,
        cb.departement_etablissement,
        
        -- Clés et libellés diagnostic
        cb.sk_diagnostic,
        cb.code_diagnostic,
        cb.libelle_diagnostic,
        cb.chapitre_cim10,
        cb.categorie_cim10,
        
        -- Clés et libellés professionnel
        cb.sk_professionnel,
        cb.nom_professionnel,
        cb.prenom_professionnel,
        cb.specialite,
        cb.fonction,
        
        -- Profil patient
        cb.sexe,
        cb.tranche_age,
        cb.age,
        
        -- Mesures agrégées
        coalesce(ae.nb_consultations_etablissement, 0) as nb_consultations_etablissement,
        coalesce(ae.duree_totale_etablissement, 0) as duree_totale_etablissement,
        coalesce(ae.nb_patients_uniques_etablissement, 0) as nb_patients_uniques_etablissement,
        
        coalesce(ad.nb_consultations_diagnostic, 0) as nb_consultations_diagnostic,
        coalesce(ad.duree_totale_diagnostic, 0) as duree_totale_diagnostic,
        coalesce(ad.nb_patients_uniques_diagnostic, 0) as nb_patients_uniques_diagnostic,
        
        coalesce(aprof.nb_consultations_professionnel, 0) as nb_consultations_professionnel,
        coalesce(aprof.duree_totale_professionnel, 0) as duree_totale_professionnel,
        coalesce(aprof.nb_patients_uniques_professionnel, 0) as nb_patients_uniques_professionnel,
        
        coalesce(apat.nb_consultations_profil, 0) as nb_consultations_profil,
        coalesce(apat.duree_totale_profil, 0) as duree_totale_profil,
        coalesce(apat.nb_patients_uniques_profil, 0) as nb_patients_uniques_profil,
        
        -- Métadonnées
        current_timestamp as date_chargement
        
    from consultations_base cb
    left join agreg_etablissement ae on cb.sk_temps = ae.sk_temps and cb.sk_etablissement = ae.sk_etablissement
    left join agreg_diagnostic ad on cb.sk_temps = ad.sk_temps and cb.sk_etablissement = ad.sk_etablissement and cb.sk_diagnostic = ad.sk_diagnostic
    left join agreg_professionnel aprof on cb.sk_temps = aprof.sk_temps and cb.sk_professionnel = aprof.sk_professionnel
    left join agreg_patient apat on cb.sk_temps = apat.sk_temps and cb.sexe = apat.sexe and cb.tranche_age = apat.tranche_age
)

select * from final
