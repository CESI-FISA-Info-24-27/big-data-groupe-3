

-- Consolidation des indicateurs qualité soins
-- Prépare les données pour fait_qualite_soins

with ete_ortho_2017_2018 as (
    select
        -- Identifiants établissement
        trim(finess) as finess,
        trim(rs) as nom_etablissement,
        trim(region) as region,
        
        -- Type indicateur
        'ETE ORTHO' as type_indicateur,
        2018 as annee_enquete,
        2017 as annee_donnee,
        
        -- Ratios et alertes (remplacer virgule par point)
        cast(replace(cast(ete_ortho_etbt as varchar), ',', '.') as double) as ratio_ete_ortho,
        case
            when trim(ete_ortho_pos_seuil_etbt) = 'Supérieur au seuil' then 1
            else 0
        end as alerte_ete,
        
        -- Observations
        ete_ortho_cible_etbt as cible,
        ete_ortho_obs_etbt as observations,
        cast(replace(cast(ete_ortho_att_etbt as varchar), ',', '.') as double) as attendu,
        trim(ete_ortho_pos_seuil_etbt) as position_seuil
        
    from "staging"."raw"."satisfaction_2017_2018_ete_ortho_ipaqss_2017_2018_donnees"
    where finess is not null
)

select
    *,
    current_timestamp as loaded_at
from ete_ortho_2017_2018