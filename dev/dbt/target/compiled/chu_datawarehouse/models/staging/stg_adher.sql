

-- Nettoyage et standardisation des adhésions mutuelles
with source as (
    select * from "staging"."raw"."adher"
),

cleaned as (
    select
        -- Identifiants
        cast("Id_patient" as integer) as id_patient,
        cast("Id_mut" as integer) as id_mut,
        
        -- Note: pas de dates dans la table raw adher !
        -- On considère toutes les adhésions comme actives
        'ACTIF' as statut_adhesion,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where "Id_patient" is not null
      and "Id_mut" is not null
)

select * from cleaned