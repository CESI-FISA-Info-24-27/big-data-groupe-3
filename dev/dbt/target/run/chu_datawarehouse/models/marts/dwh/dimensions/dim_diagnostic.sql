
  
    
    

    create  table
      "staging"."dwh"."dim_diagnostic__dbt_tmp"
  
    as (
      

-- Dimension Diagnostic
-- Source : stg_diagnostic (15k diagnostics CIM-10)
-- Clé substitut : sk_diagnostic (auto-incrémenté via row_number)
-- Mapping CIM-10 : Chapitres par catégorie

with diagnostics_source as (
    select * from "staging"."staging"."stg_diagnostic"
),

dimension_diagnostic as (
    select
        -- Clé substitut (génération séquentielle)
        row_number() over (order by code_diagnostic) as sk_diagnostic,
        
        -- Business key
        code_diagnostic,
        
        -- Attributs descriptifs
        libelle_diagnostic,
        categorie_cim10,  -- 3 premiers caractères (ex: A00, I21, J44)
        
        -- Mapping des chapitres CIM-10 (classification niveau 1)
        case
            when categorie_cim10 between 'A00' and 'B99' then 'Maladies infectieuses et parasitaires'
            when categorie_cim10 between 'C00' and 'D48' then 'Tumeurs'
            when categorie_cim10 between 'D50' and 'D89' then 'Maladies du sang et organes hematopoietiques'
            when categorie_cim10 between 'E00' and 'E90' then 'Maladies endocriniennes, nutritionnelles et metaboliques'
            when categorie_cim10 between 'F00' and 'F99' then 'Troubles mentaux et du comportement'
            when categorie_cim10 between 'G00' and 'G99' then 'Maladies du systeme nerveux'
            when categorie_cim10 between 'H00' and 'H59' then 'Maladies de l''oeil et annexes'
            when categorie_cim10 between 'H60' and 'H95' then 'Maladies de l''oreille et apophyse mastoide'
            when categorie_cim10 between 'I00' and 'I99' then 'Maladies de l''appareil circulatoire'
            when categorie_cim10 between 'J00' and 'J99' then 'Maladies de l''appareil respiratoire'
            when categorie_cim10 between 'K00' and 'K93' then 'Maladies de l''appareil digestif'
            when categorie_cim10 between 'L00' and 'L99' then 'Maladies de la peau et du tissu cellulaire sous-cutane'
            when categorie_cim10 between 'M00' and 'M99' then 'Maladies du systeme osteo-articulaire et musculaire'
            when categorie_cim10 between 'N00' and 'N99' then 'Maladies de l''appareil genito-urinaire'
            when categorie_cim10 between 'O00' and 'O99' then 'Grossesse, accouchement et puerperalite'
            when categorie_cim10 between 'P00' and 'P96' then 'Affections perinatales'
            when categorie_cim10 between 'Q00' and 'Q99' then 'Malformations congenitales'
            when categorie_cim10 between 'R00' and 'R99' then 'Symptomes, signes et resultats anormaux'
            when categorie_cim10 between 'S00' and 'T98' then 'Lesions traumatiques, empoisonnements'
            when categorie_cim10 between 'V01' and 'Y98' then 'Causes externes de morbidite et de mortalite'
            when categorie_cim10 between 'Z00' and 'Z99' then 'Facteurs influant sur l''etat de sante'
            else 'Autre ou non classe'
        end as chapitre_cim10,
        
        source_donnee,  -- Source de la donnée (PostgreSQL, Hospitalisation, etc.)
        
        -- Métadonnées
        loaded_at as date_chargement
        
    from diagnostics_source
)

select * from dimension_diagnostic
order by sk_diagnostic
    );
  
  