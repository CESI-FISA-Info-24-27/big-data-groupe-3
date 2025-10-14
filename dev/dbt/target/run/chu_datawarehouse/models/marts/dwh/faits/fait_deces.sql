
  
    
    

    create  table
      "staging"."dwh"."fait_deces__dbt_tmp"
  
    as (
      

-- Table de fait : Décès
-- Grain : 1 ligne = 1 décès enregistré
-- Source : ods_deces_enrichi (25M décès) avec fuzzy matching vers dim_patient

with deces_source as (
    select * from "staging"."ods"."ods_deces_enrichi"
),

-- Dimensions pour lookups
dim_patient as (
    select * from "staging"."dwh"."dim_patient"
),

dim_localisation as (
    select * from "staging"."dwh"."dim_localisation"
),

dim_temps as (
    select * from "staging"."dwh"."dim_temps"
),

-- Construction de la table de fait
fait_deces as (
    select
        -- Clé substitut du fait
        row_number() over (order by d.numero_acte_deces) as sk_fait_deces,
        
        -- Clés étrangères vers dimensions (LOOKUPS)
        -- SK_PATIENT : Fuzzy matching sur nom/prenom/date_naissance (PEUT ÊTRE NULL → -1)
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
        
    from deces_source d
    
    -- Lookups obligatoires
    inner join dim_temps dt on d.date_deces = dt.date_complete
    
    -- Lookup localisation (LEFT car peut ne pas être dans référentiel)
    left join dim_localisation dl 
        on d.code_lieu_deces = dl.code_lieu
        and dl.type_lieu like '%Deces%'
    
    -- Fuzzy matching patient (LEFT car tous les décès ne sont pas dans notre base patients)
    left join dim_patient dp
        on d.nom = dp.nom
        and d.prenom = dp.prenom
        and d.date_naissance = dp.date_naissance
)

select * from fait_deces
order by sk_fait_deces
    );
  
  