

-- Consultation enrichie avec patient, professionnel et diagnostic
-- Prépare les données pour fait_consultation
with consultations as (
    select * from "staging"."staging"."stg_consultation"
),

patients as (
    select * from "staging"."ods"."ods_patient_complet"
),

professionnels as (
    select * from "staging"."ods"."ods_professionnel_complet"
),

diagnostics as (
    select * from "staging"."staging"."stg_diagnostic"
),

consultation_complete as (
    select
        -- Identifiants consultation
        c.num_consultation,
        c.date_consultation,
        c.heure_debut,
        c.heure_fin,
        c.duree_consultation_minutes,
        c.motif,
        
        -- Clés pour jointures DWH
        c.id_patient,
        c.id_professionnel,
        c.code_diagnostic,
        c.id_mut,
        
        -- Informations patient enrichies
        p.nom as patient_nom,
        p.prenom as patient_prenom,
        p.sexe as patient_sexe,
        p.age as patient_age,
        p.tranche_age as patient_tranche_age,
        p.ville as patient_ville,
        p.code_postal as patient_code_postal,
        
        -- Informations mutuelle patient
        p.nom_mutuelle as patient_mutuelle,
        p.type_mutuelle as patient_type_mutuelle,
        p.a_mutuelle_active as patient_a_mutuelle,
        
        -- Informations professionnel
        pr.nom as professionnel_nom,
        pr.prenom as professionnel_prenom,
        pr.profession as professionnel_profession,
        pr.code_specialite as professionnel_code_specialite,
        pr.mode_exercice as professionnel_mode_exercice,
        
        -- Informations diagnostic
        d.libelle_diagnostic,
        d.categorie_cim10,
        
        -- Classification métier
        case
            when p.age < 18 then 'PEDIATRIE'
            when p.age > 65 then 'GERIATRIE'
            else 'ADULTE'
        end as categorie_patient,
        
        case
            when c.duree_consultation_minutes < 15 then 'COURTE'
            when c.duree_consultation_minutes between 15 and 30 then 'NORMALE'
            when c.duree_consultation_minutes > 30 then 'LONGUE'
            else 'NON_RENSEIGNEE'
        end as duree_categorie,
        
        -- Métadonnées
        c.loaded_at
        
    from consultations c
    inner join patients p on c.id_patient = p.id_patient
    left join professionnels pr on c.id_professionnel = pr.identifiant
    left join diagnostics d on c.code_diagnostic = d.code_diagnostic
)

select * from consultation_complete