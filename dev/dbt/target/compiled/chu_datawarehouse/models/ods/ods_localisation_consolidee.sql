

-- Consolidation de toutes les localisations géographiques
-- Prépare les données pour dim_localisation
with localisation_patients as (
    select distinct
        code_postal as code_lieu,
        ville as nom_lieu,
        code_postal,
        ville,
        -- Département avec gestion Corse (2A/2B)
        case
            when substring(code_postal, 1, 2) = '20' and length(code_postal) >= 3 then
                case
                    when try_cast(substring(code_postal, 3, 1) as integer) < 2 then '2A'
                    else '2B'
                end
            when length(code_postal) >= 2 then substring(code_postal, 1, 2)
            else null
        end as departement,
        pays,
        'Patient' as type_lieu,
        null::decimal(10,8) as latitude,
        null::decimal(11,8) as longitude
    from "staging"."staging"."stg_patient"
    where code_postal is not null
),

localisation_etablissements as (
    select distinct
        code_postal as code_lieu,
        commune as nom_lieu,
        code_postal,
        commune as ville,
        departement,  -- Déjà calculé dans stg_etablissement_sante avec gestion Corse
        pays,
        'Etablissement' as type_lieu,
        null::decimal(10,8) as latitude,
        null::decimal(11,8) as longitude
    from "staging"."staging"."stg_etablissement_sante"
    where code_postal is not null
),

localisation_deces as (
    select distinct
        code_lieu_deces as code_lieu,
        code_lieu_deces as nom_lieu,
        null as code_postal,
        null as ville,
        null as departement,
        'FR' as pays,
        'Deces' as type_lieu,
        null::decimal(10,8) as latitude,
        null::decimal(11,8) as longitude
    from "staging"."staging"."stg_deces"
    where code_lieu_deces is not null
),

-- Union de toutes les localisations
all_localisations as (
    select * from localisation_patients
    union all
    select * from localisation_etablissements
    union all
    select * from localisation_deces
),

-- Dédoublonnage et enrichissement
localisations_uniques as (
    select
        code_lieu,
        max(nom_lieu) as nom_lieu,
        max(code_postal) as code_postal,
        max(ville) as ville,
        max(departement) as departement,
        max(pays) as pays,
        
        -- Concaténer les types de lieux (peut être Patient + Etablissement)
        string_agg(distinct type_lieu, ', ' order by type_lieu) as types_lieu,
        
        max(latitude) as latitude,
        max(longitude) as longitude,
        
        count(*) as nb_occurrences,
        current_timestamp as loaded_at
        
    from all_localisations
    group by code_lieu
)

select * from localisations_uniques