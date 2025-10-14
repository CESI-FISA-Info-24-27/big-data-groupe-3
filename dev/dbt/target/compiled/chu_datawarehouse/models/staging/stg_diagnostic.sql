

-- Nettoyage et standardisation des diagnostics CIM-10
-- Prépare les données pour dim_diagnostic
with source as (
    select * from "staging"."raw"."diagnostic"
),

cleaned as (
    select
        -- Business Key (Code CIM-10)
        trim(upper("Code_diag")) as code_diagnostic,
        
        -- Libellé
        trim("Diagnostic") as libelle_diagnostic,
        
        -- Classification CIM-10 (3 premiers caractères)
        substring(trim(upper("Code_diag")), 1, 3) as categorie_cim10,
        
        -- Source
        'PostgreSQL' as source_donnee,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where "Code_diag" is not null
)

select * from cleaned