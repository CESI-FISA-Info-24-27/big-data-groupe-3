
  
    
    

    create  table
      "staging"."dwh"."dim_localisation__dbt_tmp"
  
    as (
      

-- Dimension Localisation
-- Source : ods_localisation_consolidee (~50k localisations uniques)
-- Clé substitut : sk_localisation (auto-incrémenté via row_number)
-- Mapping régions par département

with localisations_source as (
    select * from "staging"."ods"."ods_localisation_consolidee"
),

dimension_localisation as (
    select
        -- Clé substitut (génération séquentielle)
        row_number() over (order by code_lieu, types_lieu) as sk_localisation,
        
        -- Business key (combinaison code_lieu + type)
        code_lieu,
        
        -- Attributs descriptifs
        nom_lieu,
        code_postal,
        ville,
        departement,
        
        -- Mapping région par département
        case
            -- Île-de-France
            when departement in ('75', '77', '78', '91', '92', '93', '94', '95') then 'Ile-de-France'
            -- Provence-Alpes-Côte d''Azur
            when departement in ('04', '05', '06', '13', '83', '84') then 'Provence-Alpes-Cote d''Azur'
            -- Auvergne-Rhône-Alpes
            when departement in ('01', '03', '07', '15', '26', '38', '42', '43', '63', '69', '73', '74') then 'Auvergne-Rhone-Alpes'
            -- Nouvelle-Aquitaine
            when departement in ('16', '17', '19', '23', '24', '33', '40', '47', '64', '79', '86', '87') then 'Nouvelle-Aquitaine'
            -- Occitanie
            when departement in ('09', '11', '12', '30', '31', '32', '34', '46', '48', '65', '66', '81', '82') then 'Occitanie'
            -- Hauts-de-France
            when departement in ('02', '59', '60', '62', '80') then 'Hauts-de-France'
            -- Normandie
            when departement in ('14', '27', '50', '61', '76') then 'Normandie'
            -- Grand Est
            when departement in ('08', '10', '51', '52', '54', '55', '57', '67', '68', '88') then 'Grand Est'
            -- Bourgogne-Franche-Comté
            when departement in ('21', '25', '39', '58', '70', '71', '89', '90') then 'Bourgogne-Franche-Comte'
            -- Pays de la Loire
            when departement in ('44', '49', '53', '72', '85') then 'Pays de la Loire'
            -- Bretagne
            when departement in ('22', '29', '35', '56') then 'Bretagne'
            -- Centre-Val de Loire
            when departement in ('18', '28', '36', '37', '41', '45') then 'Centre-Val de Loire'
            -- Corse
            when departement in ('2A', '2B', '20') then 'Corse'
            -- DOM-TOM
            when departement in ('971', '97', '972', '973', '974', '976') then 'Outre-mer'
            else 'Non renseigne'
        end as region,
        
        -- Pays en code ISO 2 lettres (FR au lieu de France)
        case
            when pays in ('France', 'FR', 'FRANCE') then 'FR'
            when pays is not null then left(pays, 2)
            else 'FR'
        end as pays,
        types_lieu as type_lieu,  -- Patient, Etablissement, Deces
        latitude,
        longitude,
        
        -- Métadonnées
        loaded_at as date_chargement
        
    from localisations_source
)

select * from dimension_localisation
order by sk_localisation
    );
  
  