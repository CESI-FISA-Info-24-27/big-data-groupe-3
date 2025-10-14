{{
    config(
        materialized='table',
        tags=['staging', 'consultation']
    )
}}

-- Nettoyage et standardisation des consultations
-- Prépare les données pour fait_consultation
with source as (
    select * from {{ source('raw', 'consultation') }}
),

cleaned as (
    select
        -- Identifiants
        cast("Num_consultation" as integer) as num_consultation,
        cast("Id_patient" as integer) as id_patient,
        trim("Id_prof_sante") as id_professionnel,
        cast("Id_mut" as integer) as id_mut,
        
        -- Date et heure
        cast("Date" as date) as date_consultation,
        cast("Heure_debut" as time) as heure_debut,
        cast("Heure_fin" as time) as heure_fin,
        
        -- Calcul durée en minutes (convertir TIME en INTERVAL via TIMESTAMP)
        date_part('hour', 
            (current_date + cast("Heure_fin" as time)) - (current_date + cast("Heure_debut" as time))
        ) * 60 +
        date_part('minute', 
            (current_date + cast("Heure_fin" as time)) - (current_date + cast("Heure_debut" as time))
        ) as duree_consultation_minutes,
        
        -- Motif et diagnostic
        trim("Motif") as motif,
        trim("Code_diag") as code_diagnostic,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where "Num_consultation" is not null
      and "Id_patient" is not null
      and "Id_prof_sante" is not null
      and "Date" is not null
)

select * from cleaned
