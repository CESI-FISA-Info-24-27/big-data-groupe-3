
  
    
    

    create  table
      "staging"."staging"."stg_professionnel_sante__dbt_tmp"
  
    as (
      

-- Nettoyage et standardisation des professionnels de santé
-- Prépare les données pour dim_professionnel (SCD Type 2)
with source as (
    select * from "staging"."raw"."professionnel_de_sante"
),

cleaned as (
    select
        -- Business Key (RPPS/ADELI)
        trim("Identifiant") as identifiant,
        
        -- Informations personnelles
        upper("Civilite") as civilite,
        trim(upper("Nom")) as nom,
        trim(upper("Prenom")) as prenom,
        
        -- Informations professionnelles
        trim("Profession") as profession,
        trim("Categorie_professionnelle") as categorie_professionnelle,
        trim("Code_specialite") as code_specialite,
        trim("Type_identifiant") as type_identifiant,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where "Identifiant" is not null  -- Filtrer les lignes sans identifiant
)

select * from cleaned
    );
  
  