{{
    config(
        materialized='table',
        tags=['ods', 'core', 'patient']
    )
}}

-- Patient enrichi avec informations mutuelle
-- Prépare les données pour dim_patient
with patients as (
    select * from {{ ref('stg_patient') }}
),

adhesions as (
    select * from {{ ref('stg_adher') }}
),

mutuelles as (
    select * from {{ ref('stg_mutuelle') }}
),

patient_mutuelle as (
    select
        p.*,
        
        -- Informations mutuelle (LEFT JOIN car tous les patients n'ont pas forcément de mutuelle)
        m.id_mut,
        m.nom_mutuelle,
        m.type_mutuelle,
        a.statut_adhesion,
        
        -- Calcul si patient a une mutuelle active
        case
            when m.id_mut is not null and a.statut_adhesion = 'ACTIF' then true
            else false
        end as a_mutuelle_active
        
    from patients p
    left join adhesions a on p.id_patient = a.id_patient
    left join mutuelles m on a.id_mut = m.id_mut
)

select * from patient_mutuelle





