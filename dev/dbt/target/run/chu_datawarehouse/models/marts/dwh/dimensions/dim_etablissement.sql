
  
    
    

    create  table
      "staging"."dwh"."dim_etablissement__dbt_tmp"
  
    as (
      

-- Dimension Etablissement
-- Source : stg_etablissement_sante (416k établissements)
-- Clé substitut : sk_etablissement (auto-incrémenté via row_number)

with etablissements_source as (
    select * from "staging"."staging"."stg_etablissement_sante"
),

dimension_etablissement as (
    select
        -- Clé substitut (génération séquentielle)
        row_number() over (order by finess_site) as sk_etablissement,
        
        -- Business key (FINESS site)
        cast(finess_site as varchar) as finess,  -- Convertir BIGINT en VARCHAR pour conformité
        
        -- Informations établissement
        raison_sociale_site as nom_etablissement,
        
        -- Type et catégorie (à enrichir si disponible dans les sources)
        'Non renseigne' as type_etablissement,  -- TODO: À enrichir si données disponibles
        'Non renseigne' as categorie,           -- TODO: À enrichir si données disponibles
        
        -- Mapping région par département
        case
            when departement in ('75', '77', '78', '91', '92', '93', '94', '95') then 'Ile-de-France'
            when departement in ('04', '05', '06', '13', '83', '84') then 'Provence-Alpes-Cote d''Azur'
            when departement in ('01', '03', '07', '15', '26', '38', '42', '43', '63', '69', '73', '74') then 'Auvergne-Rhone-Alpes'
            when departement in ('16', '17', '19', '23', '24', '33', '40', '47', '64', '79', '86', '87') then 'Nouvelle-Aquitaine'
            when departement in ('09', '11', '12', '30', '31', '32', '34', '46', '48', '65', '66', '81', '82') then 'Occitanie'
            when departement in ('02', '59', '60', '62', '80') then 'Hauts-de-France'
            when departement in ('14', '27', '50', '61', '76') then 'Normandie'
            when departement in ('08', '10', '51', '52', '54', '55', '57', '67', '68', '88') then 'Grand Est'
            when departement in ('21', '25', '39', '58', '70', '71', '89', '90') then 'Bourgogne-Franche-Comte'
            when departement in ('44', '49', '53', '72', '85') then 'Pays de la Loire'
            when departement in ('22', '29', '35', '56') then 'Bretagne'
            when departement in ('18', '28', '36', '37', '41', '45') then 'Centre-Val de Loire'
            when departement in ('2A', '2B', '20') then 'Corse'
            when departement in ('971', '97', '972', '973', '974', '976') then 'Outre-mer'
            else 'Non renseigne'
        end as region,
        
        departement,
        adresse,
        code_postal,
        commune as ville,
        
        -- Métadonnées
        loaded_at as date_chargement
        
    from etablissements_source
)

select * from dimension_etablissement
order by sk_etablissement
    );
  
  