{{
    config(
        materialized='table',
        tags=['fait', 'dwh', 'deces']
    )
}}

-- Table de fait : Décès
-- Grain : 1 ligne = 1 décès enregistré
-- Source : ods_deces_enrichi (25M décès) avec fuzzy matching vers dim_patient

with deces_source as (
    select * from {{ ref('ods_deces_enrichi') }}
),

-- Dimensions pour lookups
dim_patient as (
    select * from {{ ref('dim_patient') }}
),

dim_localisation as (
    select * from {{ ref('dim_localisation') }}
),

dim_temps as (
    select * from {{ ref('dim_temps') }}
),

-- ANONYMISATION des décès pour matching avec dim_patient
deces_anonymise as (
    select 
        *,
        -- Anonymiser avec SHA256 comme dans dim_patient
        substring(lower(cast(sha256(cast(nom as varchar)) as varchar)), 1, 8) as nom_anonyme,
        substring(lower(cast(sha256(cast(prenom as varchar)) as varchar)), 1, 8) as prenom_anonyme,
        -- Convertir date en timestamp pour matcher le format de dim_patient
        cast(date_naissance as timestamp) as date_naissance_ts
    from deces_source
),

-- Construction de la table de fait
fait_deces as (
    select
        -- Clé substitut du fait
        row_number() over (order by d.numero_acte_deces) as sk_fait_deces,
        
        -- Clés étrangères vers dimensions (LOOKUPS)
        -- SK_PATIENT : Matching via noms/prénoms anonymisés + date de naissance
        coalesce(dp.sk_patient, -1) as sk_patient,  -- -1 = Patient inconnu
        
        -- SK_LOCALISATION : Lieu du décès
        coalesce(dl.sk_localisation, -1) as sk_localisation,  -- -1 = Localisation inconnue
        
        -- SK_TEMPS : Date du décès
        dt.sk_temps,
        
        -- Dimensions dégénérées
        d.code_lieu_deces,
        d.numero_acte_deces,
        
        -- MESURES
        d.age_deces,
        1 as nombre_deces,  -- Constante pour COUNT
        
        -- Métadonnées
        d.loaded_at as date_chargement
        
    from deces_anonymise d
    
    -- Lookups obligatoires
    inner join dim_temps dt on d.date_deces = dt.date_complete
    
    -- Lookup localisation (LEFT car peut ne pas être dans référentiel)
    left join dim_localisation dl 
        on d.code_lieu_deces = dl.code_lieu
        and dl.type_lieu like '%Deces%'
    
    -- Fuzzy matching patient avec NOMS ANONYMISÉS + DATE
    left join dim_patient dp
        on d.nom_anonyme = dp.nom_anonyme
        and d.prenom_anonyme = dp.prenom_anonyme
        and d.date_naissance_ts = dp.date_naissance
)

select * from fait_deces
order by sk_fait_deces


