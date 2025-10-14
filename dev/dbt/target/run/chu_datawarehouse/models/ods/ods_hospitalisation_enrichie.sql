
  
    
    

    create  table
      "staging"."ods"."ods_hospitalisation_enrichie__dbt_tmp"
  
    as (
      

-- Hospitalisation enrichie avec patient, établissement et diagnostic
-- Prépare les données pour fait_hospitalisation
with hospitalisations as (
    select * from "staging"."staging"."stg_hospitalisation"
),

patients as (
    select * from "staging"."ods"."ods_patient_complet"
),

etablissements as (
    select * from "staging"."staging"."stg_etablissement_sante"
),

diagnostics as (
    select * from "staging"."staging"."stg_diagnostic"
),

hospitalisation_complete as (
    select
        -- Identifiants hospitalisation
        h.num_hospitalisation,
        h.date_entree,
        h.jour_hospitalisation,
        
        -- Clés pour jointures DWH
        h.id_patient,
        h.identifiant_organisation,
        h.code_diagnostic,
        
        -- Informations patient
        p.nom as patient_nom,
        p.prenom as patient_prenom,
        p.sexe as patient_sexe,
        p.age as patient_age,
        p.tranche_age as patient_tranche_age,
        
        -- Informations établissement
        e.finess_site,
        e.raison_sociale_site as etablissement_nom,
        e.commune as etablissement_commune,
        e.departement as etablissement_departement,
        
        -- Informations diagnostic
        d.libelle_diagnostic,
        d.categorie_cim10,
        h.suite_diagnostic_consultation,
        
        -- Classification métier
        case
            when h.jour_hospitalisation < 3 then 'COURT_SEJOUR'
            when h.jour_hospitalisation between 3 and 7 then 'MOYEN_SEJOUR'
            when h.jour_hospitalisation > 7 then 'LONG_SEJOUR'
            else 'NON_RENSEIGNE'
        end as type_sejour,
        
        case
            when p.age < 18 then 'PEDIATRIE'
            when p.age > 65 then 'GERIATRIE'
            else 'ADULTE'
        end as categorie_patient,
        
        -- Métadonnées
        h.loaded_at
        
    from hospitalisations h
    inner join patients p on h.id_patient = p.id_patient
    left join etablissements e on try_cast(h.identifiant_organisation as bigint) = e.finess_site
    left join diagnostics d on h.code_diagnostic = d.code_diagnostic
)

select * from hospitalisation_complete
    );
  
  