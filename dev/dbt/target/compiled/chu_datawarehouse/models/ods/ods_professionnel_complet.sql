

-- Professionnel enrichi avec établissement et spécialité
-- Prépare les données pour dim_professionnel (SCD Type 2)
with professionnels as (
    select * from "staging"."staging"."stg_professionnel_sante"
),

etablissements_pro as (
    select * from "staging"."staging"."stg_etablissement_professionnel"
),

specialites as (
    select * from "staging"."staging"."stg_specialites"
),

-- Agréger les informations par professionnel avec spécialité
professionnel_avec_etablissement as (
    select
        p.*,
        
        -- Informations établissement (prendre le plus récent ou un au hasard)
        max(ep.commune) as commune_exercice,
        max(ep.specialite) as specialite_exercice_etab,
        
        -- Compter nombre d'établissements
        count(distinct ep.commune) as nb_etablissements
        
    from professionnels p
    left join etablissements_pro ep on p.identifiant = ep.identifiant
    group by
        p.identifiant,
        p.civilite,
        p.nom,
        p.prenom,
        p.profession,
        p.categorie_professionnelle,
        p.code_specialite,
        p.type_identifiant,
        p.loaded_at
),

-- Enrichir avec les informations de spécialité depuis stg_specialites
professionnel_enrichi as (
    select
        p.*,
        
        -- Informations spécialité (fonction et catégorie depuis stg_specialites)
        s.fonction as specialite_fonction,
        s.specialite as specialite_libelle,
        s.categorie as specialite_categorie,
        
        -- Déterminer mode d'exercice depuis categorie_professionnelle
        case
            when p.categorie_professionnelle like '%Libéral%' or p.categorie_professionnelle like '%Liberal%' then 'Libéral'
            when p.categorie_professionnelle like '%Salarié%' or p.categorie_professionnelle like '%Salarie%' then 'Salarié'
            when p.categorie_professionnelle like '%Mixte%' then 'Mixte'
            else 'Non renseigné'
        end as mode_exercice
        
    from professionnel_avec_etablissement p
    left join specialites s on p.code_specialite = s.code_specialite
)

select * from professionnel_enrichi