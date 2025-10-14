

-- Table de fait : Hospitalisation
-- Grain : 1 ligne = 1 séjour hospitalier
-- Source : ods_hospitalisation_enrichie avec lookups vers dimensions

with hospitalisations_source as (
    select * from "staging"."ods"."ods_hospitalisation_enrichie"
),

-- Dimensions pour lookups
dim_patient as (
    select * from "staging"."dwh"."dim_patient"
),

dim_etablissement as (
    select * from "staging"."dwh"."dim_etablissement"
),

dim_diagnostic as (
    select * from "staging"."dwh"."dim_diagnostic"
),

dim_temps as (
    select * from "staging"."dwh"."dim_temps"
),

dim_localisation as (
    select * from "staging"."dwh"."dim_localisation"
),

-- Construction de la table de fait
fait_hospitalisation as (
    select
        -- Clé substitut du fait
        row_number() over (order by h.num_hospitalisation) as sk_fait_hospitalisation,
        
        -- Clés étrangères vers dimensions (LOOKUPS)
        dp.sk_patient,
        coalesce(de.sk_etablissement, -1) as sk_etablissement,  -- -1 = Etablissement inconnu
        coalesce(dd.sk_diagnostic, -1) as sk_diagnostic,        -- -1 = Diagnostic inconnu
        dt.sk_temps,
        coalesce(dl.sk_localisation, -1) as sk_localisation,    -- -1 = Localisation inconnue
        
        -- Dimensions dégénérées
        h.num_hospitalisation,
        
        -- MESURES
        h.jour_hospitalisation,
        1 as nombre_hospitalisations,  -- Constante pour COUNT
        
        -- Métadonnées
        h.loaded_at as date_chargement
        
    from hospitalisations_source h
    
    -- Lookups obligatoires
    inner join dim_patient dp on h.id_patient = dp.id_patient
    inner join dim_temps dt on h.date_entree = dt.date_complete
    
    -- Lookups optionnels (LEFT JOIN permet de gérer les valeurs manquantes avec COALESCE)
    left join dim_etablissement de on h.finess_site = cast(de.finess as bigint)
    left join dim_diagnostic dd on h.code_diagnostic = dd.code_diagnostic
    
    -- Localisation via établissement
    left join dim_localisation dl 
        on de.code_postal = dl.code_lieu 
        and dl.type_lieu like '%Etablissement%'
)

select * from fait_hospitalisation
order by sk_fait_hospitalisation