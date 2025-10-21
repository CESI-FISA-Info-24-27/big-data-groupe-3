# ODS - Operational Data Store (Core)

## 📋 Description

L'ODS est la **couche d'intégration** où on combine et enrichit les données provenant du staging.

## 🎯 Objectif

- **Input** : Tables nettoyées du schéma `staging`
- **Output** : Tables intégrées et enrichies dans le schéma `ods`
- **Transformations** :
  - ✅ Jointures entre plusieurs sources
  - ✅ Règles métier "basiques"
  - ✅ Enrichissements
  - ✅ Dédoublonnage avancé
  - ✅ Création de vues métier unifiées

## 🏗️ Architecture

```
staging (données nettoyées)    →    ods (données intégrées)
─────────────────────────────────────────────────────────────
stg_patient                     →    ods_patient_complet
stg_consultation                     (patient + mutuelle + adher)
stg_mutuelle                    
stg_adher                       

stg_professionnel_sante         →    ods_professionnel_complet
stg_etablissement_sante              (professionnel + établissement)

stg_consultation                →    ods_consultation_enrichie
stg_patient                          (consultation + patient + pro)
stg_professionnel_sante
```

## ❌ Ce qu'on NE fait PAS dans staging

Dans `staging/`, on fait du nettoyage simple **SANS jointures** :
- ✅ Renommer les colonnes
- ✅ Caster les types
- ✅ Gérer les nulls basiques
- ✅ Supprimer les doublons exacts
- ❌ PAS de jointures
- ❌ PAS de logique métier complexe

## ✅ Ce qu'on FAIT dans ODS

Dans `ods/`, on intègre et enrichit :
- ✅ Jointures entre tables
- ✅ Règles métier
- ✅ Calculs dérivés
- ✅ Agrégations
- ✅ Création de vues métier

## 📝 Convention de nommage

- **Préfixe** : `ods_` pour tous les modèles ODS
- **Nom** : Descriptif de l'entité métier (pas forcément 1-1 avec une table source)
- **Matérialisation** : `table`
- **Schéma** : `ods`

## 🚀 Exemples

### Exemple 1 : Patient complet

```sql
-- ods_patient_complet.sql
with patients as (
    select * from {{ ref('stg_patient') }}
),

mutuelles as (
    select * from {{ ref('stg_mutuelle') }}
),

adhesions as (
    select * from {{ ref('stg_adher') }}
)

select
    p.*,
    m.nom_mutuelle,
    m.type_mutuelle,
    a.date_adhesion,
    a.date_fin_adhesion,
    
    -- Règle métier : statut mutuelle
    case
        when a.date_fin_adhesion is null or a.date_fin_adhesion > current_date 
        then 'ACTIF'
        else 'INACTIF'
    end as statut_mutuelle
    
from patients p
left join adhesions a on p.patient_id = a.patient_id
left join mutuelles m on a.mutuelle_id = m.mutuelle_id
```

### Exemple 2 : Consultation enrichie

```sql
-- ods_consultation_enrichie.sql
with consultations as (
    select * from {{ ref('stg_consultation') }}
),

patients as (
    select * from {{ ref('stg_patient') }}
),

professionnels as (
    select * from {{ ref('stg_professionnel_sante') }}
)

select
    c.*,
    p.nom as patient_nom,
    p.prenom as patient_prenom,
    p.age as patient_age,
    pr.nom as medecin_nom,
    pr.specialite as medecin_specialite,
    
    -- Calculs métier
    datediff('year', p.date_naissance, c.date_consultation) as age_consultation,
    
    -- Classification métier
    case
        when datediff('year', p.date_naissance, c.date_consultation) < 18 
        then 'PEDIATRIE'
        when datediff('year', p.date_naissance, c.date_consultation) > 65 
        then 'GERIATRIE'
        else 'ADULTE'
    end as categorie_patient
    
from consultations c
inner join patients p on c.patient_id = p.patient_id
inner join professionnels pr on c.professionnel_id = pr.professionnel_id
```

## 🔄 Workflow

1. **Staging existe** : Les modèles `stg_*` sont créés et fonctionnent
2. **Créer ODS** : Créer les modèles `ods_*` qui référencent les `stg_*`
3. **Exécuter** :
   ```bash
   # D'abord staging
   dbt run --select tag:staging
   
   # Puis ODS (qui dépend de staging)
   dbt run --select tag:ods
   
   # Ou tout en une fois (DBT gère l'ordre)
   dbt run
   ```

## 📊 À créer (exemples)

| Modèle ODS | Sources | Description |
|------------|---------|-------------|
| `ods_patient_complet` | stg_patient + stg_mutuelle + stg_adher | Patient avec info mutuelle |
| `ods_professionnel_complet` | stg_professionnel_sante + stg_etablissement_sante | Pro avec établissement |
| `ods_consultation_enrichie` | stg_consultation + stg_patient + stg_professionnel | Consultation complète |
| `ods_prescription_detail` | stg_prescription + stg_medicaments | Prescription avec détail médicament |
| `ods_hospitalisation_complete` | stg_hospitalisation + stg_patient + stg_salle | Hospitalisation enrichie |

## ⚠️ Important

- L'ODS n'est **PAS encore dimensionnel** (pas d'étoile/flocon)
- C'est une **source de vérité opérationnelle** stable
- Les modèles de DWH (marts) viendront après et utiliseront l'ODS comme source





