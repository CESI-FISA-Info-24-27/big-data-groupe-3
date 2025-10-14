{{
    config(
        materialized='table',
        tags=['fait', 'dwh', 'consultation']
    )
}}

-- Table de fait : Consultation
-- Grain : 1 ligne = 1 consultation médicale
-- Source : ods_consultation_enrichie avec lookups vers toutes les dimensions

with consultations_source as (
    select * from {{ ref('ods_consultation_enrichie') }}
),

-- Dimensions pour lookups
dim_patient as (
    select * from {{ ref('dim_patient') }}
),

dim_professionnel as (
    select * from {{ ref('dim_professionnel') }}
    where est_actuel = true  -- Prendre la version actuelle seulement
),

dim_diagnostic as (
    select * from {{ ref('dim_diagnostic') }}
),

dim_mutuelle as (
    select * from {{ ref('dim_mutuelle') }}
),

dim_temps as (
    select * from {{ ref('dim_temps') }}
),

dim_etablissement as (
    select * from {{ ref('dim_etablissement') }}
),

-- Construction de la table de fait
fait_consultation as (
    select
        -- Clé substitut du fait
        row_number() over (order by c.num_consultation) as sk_fait_consultation,
        
        -- Clés étrangères vers dimensions (LOOKUPS)
        -- NOTE: sk_etablissement PAS dans db.sql ligne 226-245
        dp.sk_patient,
        dpr.sk_professionnel,
        dd.sk_diagnostic,
        coalesce(dm.sk_mutuelle, -1) as sk_mutuelle,  -- -1 = Mutuelle inconnue
        dt.sk_temps,
        
        -- Dimensions dégénérées (attributs gardés dans le fait)
        c.num_consultation,
        c.heure_debut,
        c.heure_fin,
        c.motif,
        
        -- MESURES (métriques agrégables)
        c.duree_consultation_minutes as duree_consultation,
        1 as nombre_consultations,  -- Constante pour COUNT
        
        -- Métadonnées
        c.loaded_at as date_chargement
        
    from consultations_source c
    
    -- Lookups vers dimensions (INNER JOIN pour clés obligatoires)
    inner join dim_patient dp on c.id_patient = dp.id_patient
    inner join dim_professionnel dpr on c.id_professionnel = dpr.identifiant
    inner join dim_diagnostic dd on c.code_diagnostic = dd.code_diagnostic
    inner join dim_temps dt on c.date_consultation = dt.date_complete
    
    -- Lookups optionnels (LEFT JOIN)
    left join dim_mutuelle dm on c.id_mut = dm.id_mut
)

select * from fait_consultation
order by sk_fait_consultation

