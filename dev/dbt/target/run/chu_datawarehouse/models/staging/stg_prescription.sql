
  
    
    

    create  table
      "staging"."staging"."stg_prescription__dbt_tmp"
  
    as (
      

-- Nettoyage et standardisation des prescriptions
with source as (
    select * from "staging"."raw"."prescription"
),

cleaned as (
    select
        -- Identifiants
        cast("Num_consultation" as integer) as num_consultation,
        trim("Code_CIS") as code_cis,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where "Num_consultation" is not null
      and "Code_CIS" is not null
)

select * from cleaned
    );
  
  