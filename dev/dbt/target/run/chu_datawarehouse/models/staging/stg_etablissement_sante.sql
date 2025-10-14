
  
    
    

    create  table
      "staging"."staging"."stg_etablissement_sante__dbt_tmp"
  
    as (
      

-- Nettoyage et standardisation des établissements de santé
-- Prépare les données pour dim_etablissement
with source as (
    select * from "staging"."raw"."etablissement_de_sante_etablissement_sante"
),

cleaned as (
    select
        -- Business Keys
        cast(finess_site as bigint) as finess_site,
        trim(finess_etablissement_juridique) as finess_etablissement_juridique,
        trim(identifiant_organisation) as identifiant_organisation,
        
        -- Informations établissement
        trim(raison_sociale_site) as raison_sociale_site,
        trim(enseigne_commerciale_site) as enseigne_commerciale_site,
        
        -- SIREN/SIRET
        trim(siren_site) as siren_site,
        trim(siret_site) as siret_site,
        
        -- Adresse complète
        trim(numero_voie) as numero_voie,
        trim(indice_repetition_voie) as indice_repetition_voie,
        trim(type_voie) as type_voie,
        trim(voie) as voie,
        trim(complement_destinataire) as complement_destinataire,
        trim(complement_point_geographique) as complement_point_geographique,
        trim(mention_distribution) as mention_distribution,
        trim(adresse) as adresse,
        
        -- Localisation
        trim(code_postal) as code_postal,
        trim(code_commune) as code_commune,
        trim(commune) as commune,
        trim(cedex) as cedex,
        trim(pays) as pays,
        
        -- Département calculé (gérer Corse 2A/2B)
        case
            when substring(trim(code_postal), 1, 2) = '20' and length(trim(code_postal)) >= 3 then
                case
                    when try_cast(substring(trim(code_postal), 3, 1) as integer) < 2 then '2A'
                    else '2B'
                end
            when length(trim(code_postal)) >= 2 then substring(trim(code_postal), 1, 2)
            else null
        end as departement,
        
        -- Contact
        trim(telephone) as telephone,
        trim(telephone_2) as telephone_2,
        trim(telecopie) as telecopie,
        trim(email) as email,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where finess_site is not null
)

select * from cleaned
    );
  
  