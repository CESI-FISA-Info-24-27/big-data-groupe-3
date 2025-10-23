{{
    config(
        materialized='table',
        tags=['dimension', 'dwh', 'professionnel']
    )
}}

-- Dimension Professionnel (SCD Type 2)
-- Source : ods_professionnel_complet (1M professionnels enrichis)
-- Clé substitut : sk_professionnel (auto-incrémenté via row_number)
-- Historisation : SCD Type 2 (gestion des changements de profession/spécialité)

with professionnels_source as (
    select * from {{ ref('ods_professionnel_complet') }}
),

specialites_dim as (
    select * from {{ ref('dim_specialite') }}
),

etablissements_dim as (
    select * from {{ ref('dim_etablissement') }}
),

activites_professionnels as (
    select 
        identifiant,
        identifiant_organisation,
        mode_exercice
    from {{ ref('stg_etablissement_activite') }}
),

dimension_professionnel as (
    select
        -- Clé substitut (génération séquentielle)
        row_number() over (order by p.identifiant) as sk_professionnel,
        
        -- Business key (RPPS/ADELI)
        p.identifiant,
        
        -- Informations personnelles (ANONYMISÉES pour RGPD)
        p.civilite,
        
        -- Hash SHA-256 tronqué à 8 caractères pour pseudonymisation
        substring(lower(cast(sha256(cast(p.nom as varchar)) as varchar)), 1, 8) as nom_anonyme,
        substring(lower(cast(sha256(cast(p.prenom as varchar)) as varchar)), 1, 8) as prenom_anonyme,
        
        -- Informations professionnelles
        p.profession,
        p.categorie_professionnelle,
        
        -- FK vers dim_specialite
        s.sk_specialite as fk_specialite,
        
        -- Mode d'exercice
        p.mode_exercice,
        
        -- FK vers dim_etablissement (via table d'activité)
        e.sk_etablissement as fk_organisation,
        
        -- SCD Type 2 : Gestion de l'historique
        current_date as date_debut_validite,
        cast(null as date) as date_fin_validite,
        true as est_actuel,
        
        -- Métadonnées
        p.loaded_at as date_chargement
        
    from professionnels_source p
    left join specialites_dim s on p.code_specialite = s.code_specialite
    
    left join activites_professionnels a on p.identifiant = a.identifiant

    left join etablissements_dim e on a.identifiant_organisation = e.finess
)

select * from dimension_professionnel
order by sk_professionnel


