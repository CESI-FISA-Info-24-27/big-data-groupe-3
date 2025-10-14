
  
    
    

    create  table
      "staging"."staging"."stg_patient__dbt_tmp"
  
    as (
      

-- Nettoyage et standardisation des données patients
-- Prépare les données pour dim_patient
with source as (
    select * from "staging"."raw"."patient"
),

cleaned as (
    select
        -- Business Key
        cast("Id_patient" as integer) as id_patient,
        
        -- Informations personnelles
        trim(upper("Nom")) as nom,
        trim(upper("Prenom")) as prenom,
        upper("Sexe") as sexe,
        
        -- Parse date avec format personnalisé (m/d/Y ou d/m/Y)
        -- Raw contient format mixte: "4/6/1980", "7/25/2013", etc.
        coalesce(
            try_strptime("Date", '%m/%d/%Y'),
            try_strptime("Date", '%d/%m/%Y'),
            try_cast("Date" as date)
        ) as date_naissance,
        
        -- Âge depuis la table (déjà calculé) + recalcul pour cohérence
        cast("Age" as integer) as age_source,
        coalesce(
            date_part('year', age(current_date, coalesce(
                try_strptime("Date", '%m/%d/%Y'),
                try_strptime("Date", '%d/%m/%Y'),
                try_cast("Date" as date)
            ))),
            cast("Age" as integer)
        ) as age,
        case
            when coalesce(date_part('year', age(current_date, coalesce(
                try_strptime("Date", '%m/%d/%Y'),
                try_strptime("Date", '%d/%m/%Y'),
                try_cast("Date" as date)
            ))), cast("Age" as integer)) < 18 then '0-18'
            when coalesce(date_part('year', age(current_date, coalesce(
                try_strptime("Date", '%m/%d/%Y'),
                try_strptime("Date", '%d/%m/%Y'),
                try_cast("Date" as date)
            ))), cast("Age" as integer)) between 19 and 30 then '19-30'
            when coalesce(date_part('year', age(current_date, coalesce(
                try_strptime("Date", '%m/%d/%Y'),
                try_strptime("Date", '%d/%m/%Y'),
                try_cast("Date" as date)
            ))), cast("Age" as integer)) between 31 and 50 then '31-50'
            when coalesce(date_part('year', age(current_date, coalesce(
                try_strptime("Date", '%m/%d/%Y'),
                try_strptime("Date", '%d/%m/%Y'),
                try_cast("Date" as date)
            ))), cast("Age" as integer)) between 51 and 65 then '51-65'
            else '66+'
        end as tranche_age,
        
        -- Informations médicales
        upper("Groupe_sanguin") as groupe_sanguin,
        -- Poid et Taille sont VARCHAR dans raw, besoin de cast explicit
        try_cast("Poid" as decimal(5,2)) as poids,
        try_cast("Taille" as integer) as taille,
        
        -- Localisation
        trim("Code_postal") as code_postal,
        trim(upper("Ville")) as ville,
        coalesce("Pays", 'FR') as pays,
        trim("Adresse") as adresse,
        
        -- Contact
        trim("EMail") as email,
        trim("Tel") as telephone,
        
        -- Sécurité sociale (à pseudonymiser dans dim_patient)
        "Num_Secu" as num_secu,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where "Id_patient" is not null  -- Filtrer les lignes sans ID
)

select * from cleaned
    );
  
  