{{
    config(
        materialized='table',
        tags=['ods', 'core', 'prescription']
    )
}}

-- Prescriptions enrichies avec médicaments et consultations
with prescriptions as (
    select * from {{ ref('stg_prescription') }}
),

medicaments as (
    select * from {{ ref('stg_medicaments') }}
),

consultations as (
    select * from {{ ref('ods_consultation_enrichie') }}
),

prescription_enrichie as (
    select
        -- Identifiants
        p.num_consultation,
        p.code_cis,
        
        -- Informations médicament
        m.denomination as medicament_nom,
        m.forme_pharmaceutique,
        m.voies_administration,
        m.statut_administratif,
        m.etat_commercialisation,
        m.titulaire as laboratoire,
        
        -- Informations consultation
        c.date_consultation,
        c.id_patient,
        c.patient_nom,
        c.patient_prenom,
        c.id_professionnel,
        c.professionnel_nom,
        c.code_diagnostic,
        
        -- Métadonnées
        p.loaded_at
        
    from prescriptions p
    left join medicaments m on p.code_cis = m.code_cis
    left join consultations c on p.num_consultation = c.num_consultation
)

select * from prescription_enrichie





