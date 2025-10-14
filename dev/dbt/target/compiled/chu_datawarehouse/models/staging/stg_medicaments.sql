

-- Nettoyage et standardisation des médicaments
with source as (
    select * from "staging"."raw"."medicaments"
),

cleaned as (
    select
        -- Identifiant
        trim("Code_CIS") as code_cis,
        
        -- Informations médicament
        trim("Denomination") as denomination,
        trim("Forme_pharmaceutique") as forme_pharmaceutique,
        trim("Voies_d_administration") as voies_administration,
        
        -- Statuts
        trim("Statut_administratif") as statut_administratif,
        trim("Type_de_procedure") as type_procedure,
        trim("Etat_de_commercialisation") as etat_commercialisation,
        trim("StatutBdm") as statut_bdm,
        
        -- Autorisation
        trim("Date_AMM") as date_amm,
        trim("Num_autorisation_europeenne") as num_autorisation_europeenne,
        
        -- Fabricant
        trim("Titulaire") as titulaire,
        
        -- Surveillance
        trim("Surveillance_renforcee") as surveillance_renforcee,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where "Code_CIS" is not null
)

select * from cleaned