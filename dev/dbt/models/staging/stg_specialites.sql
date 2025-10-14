{{
    config(
        materialized='table',
        tags=['staging', 'specialite']
    )
}}

-- Nettoyage et standardisation des spécialités médicales
-- Prépare les données pour dim_specialite
with source as (
    select * from {{ source('raw', 'specialites') }}
),

cleaned as (
    select
        -- Business Key
        trim(upper(Code_specialite)) as code_specialite,
        
        -- Informations spécialité
        trim(Fonction) as fonction,
        trim(Specialite) as specialite,
        
        -- Classification automatique par catégorie
        case
            when lower(Fonction) like '%medecin generaliste%' or lower(Fonction) like '%medecine generale%' then 'Medecine generale'
            when lower(Fonction) like '%medecin%' and Specialite is not null and trim(Specialite) != '' then 'Medecine specialisee'
            when lower(Fonction) like '%infirmier%' or lower(Fonction) like '%ide%' then 'Soins infirmiers'
            when lower(Fonction) like '%aide-soignant%' or lower(Fonction) like '%as %' then 'Aide soignant'
            when lower(Fonction) like '%kinesitherapeute%' or lower(Fonction) like '%masseur-kine%' or lower(Fonction) like '%mkde%' then 'Reeducation'
            when lower(Fonction) like '%osteopathe%' or lower(Fonction) like '%chiropracteur%' or lower(Fonction) like '%etiopathe%' then 'Medecine alternative'
            when lower(Fonction) like '%sage-femme%' or lower(Fonction) like '%maieuticien%' then 'Obstetrique'
            when lower(Fonction) like '%dentiste%' or lower(Fonction) like '%chirurgien-dentiste%' or lower(Fonction) like '%odontolog%' then 'Dentaire'
            when lower(Fonction) like '%pharmacien%' then 'Pharmacie'
            when lower(Fonction) like '%psychologue%' or lower(Fonction) like '%psychotherapeute%' or lower(Fonction) like '%psychiatre%' then 'Sante mentale'
            when lower(Fonction) like '%radiologue%' or lower(Fonction) like '%imagerie%' then 'Imagerie medicale'
            when lower(Fonction) like '%biologiste%' or lower(Fonction) like '%laborantin%' then 'Biologie medicale'
            when lower(Fonction) like '%anesthes%' then 'Anesthesie'
            when lower(Fonction) like '%chirurg%' then 'Chirurgie'
            when lower(Fonction) like '%cardio%' then 'Cardiologie'
            when lower(Fonction) like '%pediatr%' then 'Pediatrie'
            when lower(Fonction) like '%gyneco%' then 'Gynecologie'
            when lower(Fonction) like '%ophtalmolog%' then 'Ophtalmologie'
            when lower(Fonction) like '%orl%' or lower(Fonction) like '%oto-rhino%' then 'ORL'
            when lower(Fonction) like '%dermato%' then 'Dermatologie'
            when lower(Fonction) like '%orthoped%' or lower(Fonction) like '%traumatolog%' then 'Orthopedie'
            when lower(Fonction) like '%neurologue%' or lower(Fonction) like '%neuro-%' then 'Neurologie'
            when lower(Fonction) like '%radiotherap%' or lower(Fonction) like '%oncolog%' then 'Oncologie'
            when lower(Fonction) like '%urgentiste%' or lower(Fonction) like '%urgence%' then 'Medecine d''urgence'
            when lower(Fonction) like '%geriatre%' or lower(Fonction) like '%gerontolog%' then 'Geriatrie'
            when lower(Fonction) like '%reeducateur%' or lower(Fonction) like '%readaptation%' then 'Readaptation'
            when lower(Fonction) like '%dieteticien%' or lower(Fonction) like '%nutritionniste%' then 'Dietetique'
            when lower(Fonction) like '%ergotherapeute%' then 'Ergotherapie'
            when lower(Fonction) like '%orthophoniste%' then 'Orthophonie'
            when lower(Fonction) like '%orthoptiste%' then 'Orthoptie'
            when lower(Fonction) like '%podologue%' or lower(Fonction) like '%pedicure%' then 'Podologie'
            when lower(Fonction) like '%manipulateur%' or lower(Fonction) like '%technicien radiolog%' then 'Techniques medicales'
            when lower(Fonction) like '%ambulancier%' then 'Transport sanitaire'
            when lower(Fonction) like '%preparateur%' then 'Preparation pharmaceutique'
            else 'Autre'
        end as categorie,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where Code_specialite is not null  -- Filtrer les lignes sans code
)

select * from cleaned
