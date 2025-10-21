# 📚 Index des Transformations - Pipeline CHU DWH

## 🎯 Vue d'Ensemble

Ce guide contient la documentation complète des transformations appliquées à chaque couche du Data Warehouse.

---

## 📖 Documentations Disponibles

### 0️⃣ **SOURCES → RAW** (Chargement Initial)

📄 **Fichier** : [`CHARGEMENT_SOURCES_TO_RAW.md`](./CHARGEMENT_SOURCES_TO_RAW.md)

**Principe** : **Chargement brut sans transformation**

**Sources** :
- 📂 **CSV** : 35 fichiers (~27M lignes)
  - Décès INSEE (25M)
  - Établissements FINESS (416K)
  - Hospitalisations (2.5K)
  - Satisfaction (31 fichiers)
- 💾 **PostgreSQL** : 11 tables (~3.5M lignes)
  - Patients, Professionnels, Consultations
  - Prescriptions, Diagnostics, Mutuelles

**Transformations** :
- ✅ **Chargement 1:1** (aucune modification)
- ✅ **Auto-détection types** par DuckDB
- ✅ **Normalisation noms** tables
- ✅ **Traçabilité** (métadonnées)
- ✅ **Parallélisation** (CSV + PostgreSQL simultanés)
- ❌ **AUCUNE transformation** sur les données

**Scripts** :
- `load_all_to_staging.py` - Orchestrateur principal
- `load_csv_to_staging.py` - Chargement CSV
- `load_postgres_to_staging.py` - Chargement PostgreSQL

**Résultat** : **46 tables RAW, ~30M lignes, ~3.5 GB**

**Temps** : ~3 minutes (parallèle)

---

### 1️⃣ **RAW → STAGING** (Nettoyage)

📄 **Fichier** : [`TRANSFORMATIONS_RAW_TO_STAGING.md`](./TRANSFORMATIONS_RAW_TO_STAGING.md)

**Principe** : **Nettoyage basique sans jointures**

**Transformations** :
- ✅ Renommage colonnes
- ✅ Cast types de données
- ✅ Nettoyage texte (TRIM, UPPER)
- ✅ Parsing dates multi-format
- ✅ Valeurs par défaut
- ✅ Calculs simples
- ✅ Filtrage lignes invalides
- ❌ **PAS de jointures**
- ❌ **PAS de règles métier complexes**

**Exemples clés** :
- `stg_patient` : Parsing dates robuste, Cast poids/taille, Calcul âge
- `stg_specialites` : Classification 30+ catégories médicales
- `stg_etablissement_sante` : Gestion Corse 2A/2B
- `stg_consultation` : Calcul durée consultation (minutes)

**Volume** : 16 modèles, ~30M+ lignes

---

### 2️⃣ **STAGING → ODS** (Intégration)

📄 **Fichier** : [`TRANSFORMATIONS_STAGING_TO_ODS.md`](./TRANSFORMATIONS_STAGING_TO_ODS.md)

**Principe** : **Jointures et enrichissements métier**

**Transformations** :
- ✅ **Jointures** entre tables
- ✅ **Règles métier** (statut actif/inactif)
- ✅ **Calculs dérivés** (age au moment consultation)
- ✅ **Agrégations** (nombre d'établissements par pro)
- ✅ **Classifications** métier (pédiatrie/adulte/gériatrie)
- ✅ **Enrichissements** (libellés, descriptions)
- ✅ **Consolidations** multi-sources
- ❌ **PAS encore de dimensions** (pas de sk_*)

**Exemples clés** :
- `ods_patient_complet` : Patient + Mutuelle + Adher (3 jointures)
- `ods_professionnel_complet` : Pro + Établissement + Spécialité (agrégations)
- `ods_consultation_enrichie` : 4 jointures + classifications métier
- `ods_localisation_consolidee` : Consolidation 3 sources

**Volume** : 9 modèles, ~29M+ lignes

---

### 3️⃣ **ODS → DWH** (Modélisation Dimensionnelle)

📄 **Fichier** : [`TRANSFORMATIONS_ODS_TO_DWH.md`](./TRANSFORMATIONS_ODS_TO_DWH.md)

**Principe** : **Architecture en étoile (star schema)**

**Transformations** :
- ✅ **Clés substituts** (sk_*) générées
- ✅ **Dimensions** créées (8 dimensions)
- ✅ **Faits** avec métriques (5 faits)
- ✅ **SCD Type 2** pour historisation
- ✅ **Anonymisation** RGPD (SHA-256)
- ✅ **Ligne "Inconnu"** (sk=-1)
- ✅ **Dénormalisation** pour performance
- ❌ **PAS d'agrégations complexes** (→ DATAMART)

**Exemples clés** :
- `dim_patient` : Clé substitut, Anonymisation SHA-256
- `dim_professionnel` : SCD Type 2 (historisation)
- `dim_temps` : Génération dates 2015-2030, Jours fériés FR
- `dim_etablissement` : Classification auto (CHU/Hôpital/Clinique)
- `fait_consultation` : Lookup clés substituts, Métriques
- `fait_deces` : 25M+ lignes optimisées

**Volume** : 13 modèles (8 dims + 5 faits), ~27M+ lignes

---

### 4️⃣ **DWH → DATAMART** (Optimisation BI)

📄 **Fichier** : [`TRANSFORMATIONS_DWH_TO_DATAMART.md`](./TRANSFORMATIONS_DWH_TO_DATAMART.md)

**Principe** : **Agrégations pré-calculées pour Power BI**

**Transformations** :
- ✅ **Agrégations complexes** pré-calculées
- ✅ **Dénormalisation complète** (tout dans une table)
- ✅ **Indicateurs métier** (KPI : DMS, taux satisfaction)
- ✅ **Ventilations** (sexe, âge, région)
- ✅ **Classements** (TOP N, RANK)
- ✅ **Consolidations** multi-faits
- ✅ **Vue plate** pour Power BI (pas de jointures)

**Exemples clés** :
- `dm_consultations_agregees` : 4 niveaux d'agrégation, 45M lignes
- `dm_hospitalisations_agregees` : KPI DMS (Durée Moyenne Séjour)
- `dm_analyse_territoriale` : Consolidation décès + satisfaction

**Volume** : 3 modèles, ~45M lignes agrégées

---

## 🔄 Workflow Complet

```
┌─────────────────────────────────────────────────────────────┐
│                    PIPELINE COMPLET                         │
└─────────────────────────────────────────────────────────────┘

0. SOURCES (données externes)
   ├── CSV (35 fichiers)
   │   ├── Décès INSEE (~25M lignes)
   │   ├── Établissements FINESS (~416K)
   │   ├── Hospitalisations (~2.5K)
   │   └── Satisfaction (31 fichiers)
   └── PostgreSQL (11 tables, ~3.5M lignes)
       ├── Patients, Consultations
       ├── Professionnels, Prescriptions
       └── Diagnostics, Mutuelles
   
   ↓ [scripts/load_all_to_staging.py] (parallèle)
   
1. RAW (données brutes)
   ├─ CSV (décès, établissements, satisfaction)
   └─ PostgreSQL (consultations, patients, professionnels)
   
   ↓ [Chargement] scripts/load_all_to_staging.py
   
2. STAGING (nettoyage simple)
   ├─ 16 tables nettoyées
   ├─ Types corrects, Nulls gérés
   └─ Transformations : TRIM, UPPER, CAST, Parsing dates
   
   ↓ [dbt run --select tag:staging]
   
3. ODS (intégration métier)
   ├─ 9 tables enrichies
   ├─ Jointures appliquées
   └─ Transformations : JOIN, Règles métier, Agrégations
   
   ↓ [dbt run --select tag:ods]
   
4. DWH (modèle dimensionnel)
   ├─ 8 dimensions (sk_*)
   ├─ 5 faits (métriques)
   └─ Transformations : Clés substituts, SCD Type 2, Anonymisation
   
   ↓ [dbt run --select marts.dwh]
   
5. PostgreSQL (stockage)
   ├─ Schéma dwh (dimensions + faits)
   └─ Schéma datamart (vues agrégées)
   
   ↓ [scripts/push_dwh_to_postgres.py]
   
6. DATAMART (optimisation BI)
   ├─ 3 tables agrégées
   ├─ KPI pré-calculés
   └─ Transformations : Agrégations complexes, Dénormalisation
   
   ↓ [scripts/build_datamart_via_postgres.py]
   
7. POWER BI (visualisation)
   └─ Connexion directe PostgreSQL
```

---

## 📊 Résumé des Transformations par Couche

| Couche | Principe | Transformations Clés | Volumétrie |
|--------|----------|---------------------|------------|
| **SOURCES → RAW** | Chargement brut | Auto-détection types, Normalisation noms, Parallélisation | 46 tables, ~30M lignes |
| **RAW → STAGING** | Nettoyage basique | TRIM, CAST, Parsing dates, Filtrage | 16 modèles, ~30M lignes |
| **STAGING → ODS** | Intégration | Jointures, Règles métier, Enrichissements | 9 modèles, ~29M lignes |
| **ODS → DWH** | Modélisation | Clés substituts, Dimensions/Faits, SCD Type 2 | 13 modèles, ~27M lignes |
| **DWH → DATAMART** | Optimisation | Agrégations, KPI, Dénormalisation | 3 modèles, ~45M lignes |

---

## 🎯 Règles d'Or par Couche

### RAW
> "Chargement brut 1:1, zéro transformation"
- ✅ Charger données exactement comme dans la source
- ✅ Laisser DuckDB auto-détecter les types
- ❌ Aucune transformation (même pas TRIM)

### STAGING
> "Nettoyage simple, 1 table source = 1 table staging"
- ✅ Renommer, caster, filtrer
- ❌ Pas de jointures, pas de logique métier

### ODS
> "Intégration métier, N tables → 1 vue enrichie"
- ✅ Jointures, règles métier, agrégations
- ❌ Pas encore de modèle dimensionnel

### DWH
> "Architecture en étoile, dimensions + faits"
- ✅ Clés substituts, SCD, anonymisation
- ❌ Pas d'agrégations complexes pour BI

### DATAMART
> "Pré-calculs pour BI, tout en une vue"
- ✅ Agrégations, KPI, dénormalisation
- ❌ Plus de transformations après (connecter Power BI)

---

## 📚 Exemples de Transformations Complètes

### Exemple 1 : Patient (de RAW à DATAMART)

**RAW** :
```
Id | Nom    | Date       | Poid | Taille
---|--------|------------|------|-------
1  | dupont | 4/6/1980   | 54.3 | 162
```

**STAGING** :
```
id_patient | nom    | date_naissance | poids | taille | age | tranche_age
-----------|--------|----------------|-------|--------|-----|------------
1          | DUPONT | 1980-06-04     | 54.30 | 162    | 44  | 31-50
```

**ODS** :
```
id_patient | nom    | age | nom_mutuelle | type_mutuelle | a_mutuelle_active
-----------|--------|-----|--------------|---------------|------------------
1          | DUPONT | 44  | Mutuelle AXA | Mutuelle      | TRUE
```

**DWH (dim_patient)** :
```
sk_patient | id_patient | nom_anonyme | age | num_secu_hash
-----------|------------|-------------|-----|---------------
1          | 1          | a3f2d1c8    | 44  | 5e884898da280...
```

**DATAMART (agrégé)** :
```
tranche_age | sexe | nb_consultations | duree_moyenne
------------|------|------------------|---------------
31-50       | M    | 1500             | 25.5
```

---

### Exemple 2 : Consultation (de RAW à DATAMART)

**RAW** :
```
num | id_patient | heure_debut | heure_fin
----|------------|-------------|----------
1   | 1          | 09:00       | 09:25
```

**STAGING** :
```
num_consultation | id_patient | heure_debut | heure_fin | duree_consultation_minutes
-----------------|------------|-------------|-----------|---------------------------
1                | 1          | 09:00:00    | 09:25:00  | 25
```

**ODS** :
```
num_consultation | patient_nom | patient_age | professionnel_nom | categorie_patient | duree_categorie
-----------------|-------------|-------------|-------------------|-------------------|----------------
1                | DUPONT      | 44          | MARTIN            | ADULTE            | NORMALE
```

**DWH (fait_consultation)** :
```
id_consultation | sk_temps | sk_patient | sk_professionnel | nombre_consultations | duree_consultation
----------------|----------|------------|------------------|---------------------|-------------------
1               | 20230515 | 1          | 1                | 1                   | 25
```

**DATAMART** :
```
annee | mois | specialite | nb_consultations | duree_moyenne | nb_patients_uniques
------|------|------------|------------------|---------------|--------------------
2023  | 5    | Cardio     | 150              | 27.5          | 120
```

---

## 🔍 Navigation Rapide

### 📖 Documentations des Transformations

- **Chargement sources** → [`CHARGEMENT_SOURCES_TO_RAW.md`](./CHARGEMENT_SOURCES_TO_RAW.md)
- **Nettoyage données** → [`TRANSFORMATIONS_RAW_TO_STAGING.md`](./TRANSFORMATIONS_RAW_TO_STAGING.md)
- **Intégration métier** → [`TRANSFORMATIONS_STAGING_TO_ODS.md`](./TRANSFORMATIONS_STAGING_TO_ODS.md)
- **Modèle dimensionnel** → [`TRANSFORMATIONS_ODS_TO_DWH.md`](./TRANSFORMATIONS_ODS_TO_DWH.md)
- **Optimisation BI** → [`TRANSFORMATIONS_DWH_TO_DATAMART.md`](./TRANSFORMATIONS_DWH_TO_DATAMART.md)

### 📚 Références Techniques

- **Dictionnaire de données DWH** → [`DICTIONNAIRE_DONNEES_DWH.md`](./DICTIONNAIRE_DONNEES_DWH.md)
  - Description complète de toutes les tables DWH
  - Structure détaillée (colonnes, types, contraintes)
  - Index et relations
  - Exemples de requêtes
  - Glossaire technique

---

## 🛠️ Scripts Associés

| Étape | Script | Description |
|-------|--------|-------------|
| **Chargement SOURCES → RAW** | `scripts/load_all_to_staging.py` | Charger CSV + Postgres dans DuckDB (parallèle) |
| | `scripts/load_csv_to_staging.py` | Charger fichiers CSV |
| | `scripts/load_postgres_to_staging.py` | Charger tables PostgreSQL |
| **STAGING → ODS → DWH** | `dbt run` | Exécuter tous les modèles dbt |
| **Push DWH** | `scripts/push_dwh_to_postgres.py` | Pousser DWH vers PostgreSQL |
| **Créer DATAMART** | `scripts/build_datamart_via_postgres.py` | Créer datamart directement dans PostgreSQL (optimisé) |
| **Pipeline Complet** | `scripts/admin_pipeline.py --full` | Tout automatiser |

---

## 📈 Métriques de Performance

| Couche | Temps Exécution | Volumétrie | Optimisation |
|--------|----------------|------------|--------------|
| SOURCES → RAW | ~3 min | 30M lignes | Parallélisation CSV + PostgreSQL |
| RAW → STAGING | ~15s | 30M lignes | Filtrage précoce |
| STAGING → ODS | ~20s | 29M lignes | Jointures optimisées |
| ODS → DWH | ~30s | 27M lignes | Clés substituts, index |
| Push vers Postgres | ~3 min | 27M lignes | COPY bulk |
| DWH → DATAMART | ~8 min | 45M lignes | Agrégations pré-calculées |
| **TOTAL** | **~15 min** | **30M → 45M** | Pipeline complet (avec chargement) |

---

## 📝 Conventions de Nommage

| Couche | Préfixe | Exemple | Matérialisation |
|--------|---------|---------|-----------------|
| STAGING | `stg_` | `stg_patient` | `table` |
| ODS | `ods_` | `ods_patient_complet` | `table` |
| DWH Dimensions | `dim_` | `dim_patient` | `table` |
| DWH Faits | `fait_` | `fait_consultation` | `table` |
| DATAMART | `dm_` | `dm_consultations_agregees` | `table` |

---

## ✅ Tests de Qualité

Chaque couche a ses tests :

```bash
# Tests STAGING
dbt test --select tag:staging

# Tests ODS
dbt test --select tag:ods

# Tests DWH
dbt test --select marts.dwh

# Tests DATAMART
dbt test --select tag:datamart
```

---

**Auteur** : Équipe Big Data Groupe 3  
**Version** : 1.0  
**Date** : 2025-10-21

