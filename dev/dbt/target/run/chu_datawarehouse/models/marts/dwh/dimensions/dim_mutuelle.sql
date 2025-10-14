
  
    
    

    create  table
      "staging"."dwh"."dim_mutuelle__dbt_tmp"
  
    as (
      

-- Dimension Mutuelle
-- Source : stg_mutuelle (254 mutuelles)
-- Clé substitut : sk_mutuelle (auto-incrémenté via row_number)

with mutuelles_source as (
    select * from "staging"."staging"."stg_mutuelle"
),

dimension_mutuelle as (
    select
        -- Clé substitut (génération séquentielle)
        row_number() over (order by id_mut) as sk_mutuelle,
        
        -- Business key
        id_mut,
        
        -- Attributs descriptifs
        nom_mutuelle,
        adresse,
        type_mutuelle,  -- CMU, Assurance, Mutuelle (calculé dans staging)
        
        -- Métadonnées
        loaded_at as date_chargement
        
    from mutuelles_source
)

select * from dimension_mutuelle
order by sk_mutuelle
    );
  
  