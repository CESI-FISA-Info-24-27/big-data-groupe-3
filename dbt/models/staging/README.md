# Staging - Nettoyage et Normalisation

## 📋 Description

Le **staging** est la première couche de transformation où on nettoie et normalise les données brutes.

## 🎯 Objectif

- **Input** : Données brutes du schéma `raw` (chargées depuis PostgreSQL et CSV)
- **Output** : Données nettoyées et normalisées dans le schéma `staging`
- **Transformations SIMPLES uniquement** :
  - ✅ Renommer les colonnes (standardisation)
  - ✅ Caster les types de données
  - ✅ Gérer les valeurs nulles basiques
  - ✅ Supprimer les doublons exacts
  - ✅ Ajouter des métadonnées (timestamps)
  - ❌ **PAS de jointures**
  - ❌ **PAS de logique métier complexe**

## 🏗️ Architecture

```
raw (brut)                     →    staging (nettoyé)
─────────────────────────────────────────────────────────
patient                        →    stg_patient
professionnel_de_sante         →    stg_professionnel_sante
consultation                   →    stg_consultation
prescription                   →    stg_prescription
medicaments                    →    stg_medicaments
deces_en_france_deces          →    stg_deces
etablissement_...              →    stg_etablissement_sante
hospitalisation_...            →    stg_hospitalisation
```

## 📐 Règle : 1 modèle = 1 table raw

**Principe** : Chaque modèle staging correspond à **UNE SEULE** table raw.

- ✅ `stg_patient` ← `raw.patient`
- ✅ `stg_consultation` ← `raw.consultation`
- ❌ **PAS** `stg_patient_consultation` (jointure = ODS)

## 📝 Convention de nommage

- **Préfixe** : `stg_` pour tous les modèles staging
- **Nom** : Version simplifiée du nom de la table source
- **Matérialisation** : `table` (pour performances)
- **Schéma** : `staging`

## ✅ Exemple de bon modèle staging

```sql
-- stg_patient.sql
{{
    config(
        materialized='table',
        tags=['staging', 'patient']
    )
}}

with source as (
    select * from {{ source('raw', 'patient') }}
),

cleaned as (
    select
        -- Standardisation des noms de colonnes
        id as patient_id,
        nom as last_name,
        prenom as first_name,
        
        -- Cast des types
        cast(date_naissance as date) as birth_date,
        cast(code_postal as varchar) as postal_code,
        
        -- Nettoyage basique
        trim(upper(nom)) as last_name_clean,
        coalesce(email, 'non_renseigne@chu.fr') as email,
        
        -- Métadonnées
        current_timestamp as loaded_at
        
    from source
    where id is not null  -- Supprimer les lignes invalides
)

select * from cleaned
```

## ❌ Ce qu'on NE fait PAS ici

```sql
-- ❌ MAUVAIS : Pas de jointures dans staging !
select
    p.*,
    m.nom_mutuelle  -- ← Jointure = ODS !
from {{ source('raw', 'patient') }} p
left join {{ source('raw', 'mutuelle') }} m
    on p.mutuelle_id = m.id

-- ❌ MAUVAIS : Pas de logique métier complexe !
case
    when age > 65 and pathologie = 'cardiaque'
    then 'RISQUE_ELEVE'  -- ← Règle métier = ODS !
end as risque_patient
```

## ✅ Transformations autorisées

| Type | ✅/❌ | Exemple |
|------|-------|---------|
| Renommer | ✅ | `id → patient_id` |
| Cast | ✅ | `cast(age as integer)` |
| Trim/Upper/Lower | ✅ | `trim(upper(nom))` |
| Coalesce simple | ✅ | `coalesce(email, 'N/A')` |
| WHERE simple | ✅ | `where id is not null` |
| Dédoublonnage exact | ✅ | `qualify row_number() over(...) = 1` |
| **Jointure** | ❌ | → ODS |
| **Agrégation** | ❌ | → ODS |
| **Règle métier** | ❌ | → ODS |
| **CASE complexe** | ❌ | → ODS |

## 🚀 Utilisation

### Exécuter tous les modèles staging
```bash
cd dbt
dbt run --select tag:staging
```

### Exécuter un modèle spécifique
```bash
dbt run --select stg_patient
```

### Tester les modèles
```bash
dbt test --select tag:staging
```

## 📊 Modèles existants

| Modèle | Source | Lignes | Description |
|--------|--------|--------|-------------|
| `stg_patient` | `raw.patient` | 100k | Patients |
| `stg_professionnel_sante` | `raw.professionnel_de_sante` | 1M+ | Professionnels |
| `stg_consultation` | `raw.consultation` | 1M+ | Consultations |
| `stg_prescription` | `raw.prescription` | 2M+ | Prescriptions |
| `stg_medicaments` | `raw.medicaments` | 15k | Médicaments |
| `stg_deces` | `raw.deces_en_france_deces` | 25M+ | Décès |
| `stg_etablissement_sante` | `raw.etablissement_de_sante_etablissement_sante` | 416k | Établissements |
| `stg_hospitalisation` | `raw.hospitalisation_hospitalisations` | 2.5k | Hospitalisations |

## 🔄 Prochaine étape : ODS

Une fois le staging créé, on passe à **ODS** (Operational Data Store) où on pourra :
- ✅ Faire des jointures
- ✅ Appliquer des règles métier
- ✅ Enrichir les données
- ✅ Créer des vues métier intégrées

Voir `models/ods/README.md` pour la suite.

## ✨ Créer un nouveau modèle

1. **Ajouter la source** dans `sources.yml` (si pas déjà fait)

2. **Créer le fichier** `stg_ma_table.sql` :

```sql
{{
    config(
        materialized='table',
        tags=['staging', 'ma_categorie']
    )
}}

with source as (
    select * from {{ source('raw', 'ma_table') }}
),

cleaned as (
    select
        -- Nettoyage simple ici
        *,
        current_timestamp as loaded_at
    from source
)

select * from cleaned
```

3. **Exécuter** :
```bash
dbt run --select stg_ma_table
```