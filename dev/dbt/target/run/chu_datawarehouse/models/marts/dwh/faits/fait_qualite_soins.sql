
  
    
    

    create  table
      "staging"."dwh"."fait_qualite_soins__dbt_tmp"
  
    as (
      

-- Table de fait : Qualité des Soins
-- Grain : 1 ligne = 1 établissement × 1 année × 1 indicateur qualité
-- Source : ods_qualite_soins_unifie avec lookups vers dimensions

with qualite_source as (
    select * from "staging"."ods"."ods_qualite_soins_unifie"
),

-- Dimensions pour lookups
dim_etablissement as (
    select * from "staging"."dwh"."dim_etablissement"
),

dim_temps as (
    select * from "staging"."dwh"."dim_temps"
),

dim_localisation as (
    select * from "staging"."dwh"."dim_localisation"
),

-- Construction de la table de fait
fait_qualite_soins as (
    select
        -- Clé substitut du fait
        row_number() over (order by q.finess, q.annee_enquete) as sk_fait_qualite,
        
        -- Clés étrangères vers dimensions (LOOKUPS)
        de.sk_etablissement,
        dt.sk_temps,
        coalesce(dl.sk_localisation, -1) as sk_localisation,  -- -1 = Localisation inconnue
        
        -- MESURES (indicateurs qualité IPAQSS)
        q.ratio_ete_ortho,
        q.alerte_ete,
        
        -- TODO: Ajouter ratio_iso_ortho et alerte_iso quand données disponibles
        null::decimal(10,6) as ratio_iso_ortho,
        null::integer as alerte_iso,
        
        -- Dimensions dégénérées
        null as evolution_ete,  -- TODO: À calculer avec données historiques
        
        -- Métadonnées
        q.loaded_at as date_chargement
        
    from qualite_source q
    
    -- Lookup établissement
    inner join dim_etablissement de on q.finess = de.finess
    
    -- Lookup temps (1er janvier de l'année d'enquête)
    inner join dim_temps dt 
        on dt.date_complete = cast(q.annee_enquete || '-01-01' as date)
    
    -- Lookup localisation via région établissement
    left join dim_localisation dl
        on dl.region = case
            when de.departement in ('75', '77', '78', '91', '92', '93', '94', '95') then 'Ile-de-France'
            when de.departement in ('04', '05', '06', '13', '83', '84') then 'Provence-Alpes-Cote d''Azur'
            when de.departement in ('01', '03', '07', '15', '26', '38', '42', '43', '63', '69', '73', '74') then 'Auvergne-Rhone-Alpes'
            when de.departement in ('16', '17', '19', '23', '24', '33', '40', '47', '64', '79', '86', '87') then 'Nouvelle-Aquitaine'
            when de.departement in ('09', '11', '12', '30', '31', '32', '34', '46', '48', '65', '66', '81', '82') then 'Occitanie'
            when de.departement in ('02', '59', '60', '62', '80') then 'Hauts-de-France'
            when de.departement in ('14', '27', '50', '61', '76') then 'Normandie'
            when de.departement in ('08', '10', '51', '52', '54', '55', '57', '67', '68', '88') then 'Grand Est'
            when de.departement in ('21', '25', '39', '58', '70', '71', '89', '90') then 'Bourgogne-Franche-Comte'
            when de.departement in ('44', '49', '53', '72', '85') then 'Pays de la Loire'
            when de.departement in ('22', '29', '35', '56') then 'Bretagne'
            when de.departement in ('18', '28', '36', '37', '41', '45') then 'Centre-Val de Loire'
            when de.departement in ('2A', '2B', '20') then 'Corse'
            else 'Non renseigne'
        end
        and dl.type_lieu like '%Etablissement%'
        limit 1
)

select * from fait_qualite_soins
order by sk_fait_qualite
    );
  
  