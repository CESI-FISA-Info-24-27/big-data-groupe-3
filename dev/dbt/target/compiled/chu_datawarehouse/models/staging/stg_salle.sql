

-- Nettoyage et standardisation des salles
-- Prépare les données pour référentiel salles
with source as (
    select * from "staging"."raw"."salle"
),

cleaned as (
    select
        -- Identifiant salle
        trim(Id_salle) as id_salle,
        
        -- Lien consultation
        cast(Num_consultation as bigint) as num_consultation,
        
        -- Localisation salle
        trim(Code_bloc) as code_bloc,
        trim(Num_etage) as num_etage,
        trim(Num_salle) as num_salle,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where Id_salle is not null  -- Filtrer les lignes sans ID
)

select * from cleaned