{{
    config(
        materialized='table',
        tags=['dimension', 'dwh', 'patient']
    )
}}

-- Dimension Patient
-- Source : ods_patient_complet (100k patients avec mutuelle)
-- Clé substitut : sk_patient (auto-incrémenté via row_number)
-- RGPD : num_secu hashé en SHA-256

with patients_source as (
    select * from {{ ref('ods_patient_complet') }}
),

-- Dédoublonner les patients (un patient peut avoir plusieurs mutuelles)
patients_dedupliques as (
    select
        id_patient,
        nom,
        prenom,
        sexe,
        date_naissance,
        age,
        tranche_age,
        groupe_sanguin,
        poids,
        taille,
        code_postal,
        ville,
        pays,
        num_secu,
        loaded_at,
        -- Garder seulement la première adhésion mutuelle (ou NULL si aucune)
        max(case when a_mutuelle_active then 1 else 0 end) as a_mutuelle_active
    from patients_source
    group by 
        id_patient, nom, prenom, sexe, date_naissance, age, tranche_age,
        groupe_sanguin, poids, taille, code_postal, ville, pays, num_secu, loaded_at
),

dimension_patient as (
    select
        -- Clé substitut (génération séquentielle)
        row_number() over (order by id_patient) as sk_patient,
        
        -- Business key
        id_patient,
        
        -- Informations personnelles
        nom,
        prenom,
        sexe,
        date_naissance,
        age,
        tranche_age,
        
        -- Informations médicales
        groupe_sanguin,
        poids,
        taille,
        
        -- Localisation
        code_postal,
        ville,
        pays,
        
        -- RGPD : Numéro de sécurité sociale hashé en SHA-256 (64 caractères hex)
        case
            when num_secu is not null then 
                lower(cast(sha256(cast(num_secu as varchar)) as varchar))
            else null
        end as num_secu_hash,
        
        -- Métadonnées
        loaded_at as date_chargement,
        loaded_at as date_modification  -- Pour SCD, initialement = date_chargement
        
    from patients_dedupliques
)

select * from dimension_patient
order by sk_patient

