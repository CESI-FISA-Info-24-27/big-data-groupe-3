{{
    config(
        materialized='table',
        tags=['staging', 'hospitalisation']
    )
}}

-- Nettoyage et standardisation des hospitalisations
-- Prépare les données pour fait_hospitalisation
with source as (
    select * from {{ source('raw', 'hospitalisation_hospitalisations') }}
),

cleaned as (
    select
        -- Identifiants
        cast("Num_Hospitalisation" as integer) as num_hospitalisation,
        cast("Id_patient" as integer) as id_patient,
        trim("identifiant_organisation") as identifiant_organisation,
        
        -- Date entrée (pas de date de sortie dans raw !)
        cast("Date_Entree" as date) as date_entree,
        
        -- Durée séjour (déjà dans raw)
        cast("Jour_Hospitalisation" as integer) as jour_hospitalisation,
        
        -- Diagnostic
        trim("Code_diagnostic") as code_diagnostic,
        trim("Suite_diagnostic_consultation") as suite_diagnostic_consultation,
        
        -- Note: pas de id_salle dans raw !
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where "Num_Hospitalisation" is not null
      and "Id_patient" is not null
      and "Date_Entree" is not null
)

select * from cleaned
