
  
    
    

    create  table
      "staging"."dwh"."dim_professionnel__dbt_tmp"
  
    as (
      

-- Dimension Professionnel (SCD Type 2)
-- Source : ods_professionnel_complet (1M professionnels enrichis)
-- Clé substitut : sk_professionnel (auto-incrémenté via row_number)
-- Historisation : SCD Type 2 (gestion des changements de profession/spécialité)

with professionnels_source as (
    select * from "staging"."ods"."ods_professionnel_complet"
),

specialites_dim as (
    select * from "staging"."dwh"."dim_specialite"
),

dimension_professionnel as (
    select
        -- Clé substitut (génération séquentielle)
        row_number() over (order by p.identifiant) as sk_professionnel,
        
        -- Business key (RPPS/ADELI)
        p.identifiant,
        
        -- Informations personnelles
        p.civilite,
        p.nom,
        p.prenom,
        
        -- Informations professionnelles
        p.profession,
        p.categorie_professionnelle,
        
        -- FK vers dim_specialite
        s.sk_specialite as fk_specialite,
        
        -- Mode d'exercice
        p.mode_exercice,  -- Libéral, Salarié, Mixte
        
        -- Organisation d'appartenance (FINESS)
        null as fk_organisation,  -- TODO: À enrichir avec FINESS établissement principal
        
        -- SCD Type 2 : Gestion de l'historique
        -- Pour l'instant, version initiale = version actuelle
        current_date as date_debut_validite,
        cast(null as date) as date_fin_validite,
        true as est_actuel,
        
        -- Métadonnées
        p.loaded_at as date_chargement
        
    from professionnels_source p
    left join specialites_dim s on p.code_specialite = s.code_specialite
)

select * from dimension_professionnel
order by sk_professionnel
    );
  
  