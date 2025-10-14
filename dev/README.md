# CHU Data Warehouse 🏥

**Projet** : Entrepôt de données pour le Centre Hospitalier Universitaire  
**Architecture** : Modèle en Constellation (ELT)  
**Stack** : DuckDB + dbt + PostgreSQL + Power BI  
**Statut** : ✅ **COMPLET** - Prêt pour déploiement

---

## 📋 Vue d'ensemble

Ce projet implémente un **Data Warehouse moderne** pour analyser les données de santé d'un CHU :

- 🏥 **1M consultations** médicales
- 👨‍⚕️ **1M professionnels** de santé (93 spécialités)
- 📊 **Indicateurs de satisfaction** e-Satis (2014-2020)
- 💀 **25M décès** en France (INSEE)
- 🏢 **416k établissements** de santé (FINESS)
- 🏥 **2.5k hospitalisations**
- 📈 **Indicateurs qualité** IPAQSS

**Volume total** : ~30 millions de lignes

---

## 🏗️ Architecture technique

### Modèle en Constellation (5 étoiles + 8 dimensions partagées)

```
┌────────────────────────────────────────────────────────────┐
│ SOURCES                                                     │
│ ├─ PostgreSQL (base opérationnelle CHU - 13 tables)        │
│ └─ CSV (décès INSEE, établissements FINESS, satisfaction)  │
└─────────────────────────┬──────────────────────────────────┘
                          ↓
                  [Scripts Python]
                          ↓
┌────────────────────────────────────────────────────────────┐
│ DUCKDB - staging.duckdb                                    │
│                                                             │
│ 📁 RAW (44 tables, 30M+ lignes)                            │
│    └─ Données brutes sans transformation                   │
│                                                             │
│ 📁 STAGING (16 tables) - dbt ✅                            │
│    ├─ Nettoyage et normalisation                           │
│    ├─ Typage correct                                       │
│    └─ 30+ catégories spécialités                           │
│                                                             │
│ 📁 ODS (9 tables) - dbt ✅                                 │
│    ├─ Jointures métier                                     │
│    ├─ Enrichissements                                      │
│    └─ Règles de gestion                                    │
│                                                             │
│ 📁 DWH (13 tables) - dbt ✅                                │
│    ├─ 8 dimensions avec clés substituts (sk_*)             │
│    └─ 5 tables de faits en constellation                   │
└─────────────────────────┬──────────────────────────────────┘
                          ↓
                [Script d'export Python]
                          ↓
┌────────────────────────────────────────────────────────────┐
│ POSTGRESQL - Base dwh                                       │
│                                                             │
│ 📁 Schema: datawarehouse ✅                                │
│    ├─ dim_temps (5,844 jours 2015-2030)                    │
│    ├─ dim_patient (100k patients, SHA-256 RGPD)            │
│    ├─ dim_professionnel (1M pros, SCD Type 2)              │
│    ├─ dim_specialite (93 spécialités, 30+ catégories)      │
│    ├─ dim_diagnostic (15k codes, 21 chapitres CIM-10)      │
│    ├─ dim_etablissement (416k établissements)              │
│    ├─ dim_localisation (50k lieux, 13 régions)             │
│    ├─ dim_mutuelle (254 mutuelles)                         │
│    ├─ fait_consultation (1M consultations)                 │
│    ├─ fait_hospitalisation (2.5k séjours)                  │
│    ├─ fait_deces (25M décès)                               │
│    ├─ fait_satisfaction (5k enquêtes)                      │
│    └─ fait_qualite_soins (3k indicateurs)                  │
│                                                             │
│ 📁 Schema: datamart (à venir)                              │
│    └─ Vues matérialisées pour Power BI                     │
└─────────────────────────┬──────────────────────────────────┘
                          ↓
                      Power BI
```

---

## 🚀 Démarrage rapide

### 1️⃣ Installation

```powershell
# Cloner le projet
git clone <votre-repo>
cd chu-datawarehouse

# Installer les dépendances Python
pip install -r requirements.txt

# Installer les packages dbt
cd dbt
python -m dbt deps
cd ..
```

### 2️⃣ Configuration PostgreSQL

Créer la base de données :

```sql
CREATE DATABASE dwh;
CREATE USER admin WITH PASSWORD 'admin';
GRANT ALL PRIVILEGES ON DATABASE dwh TO admin;
```

Configurer les variables d'environnement (optionnel) :

```powershell
$env:DWH_POSTGRES_HOST="localhost"
$env:DWH_POSTGRES_PORT="5432"
$env:DWH_POSTGRES_DB="dwh"
$env:DWH_POSTGRES_USER="admin"
$env:DWH_POSTGRES_PASSWORD="admin"
```

### 3️⃣ Exécution du pipeline complet

**Option 1 : Script automatisé** ⭐ **RECOMMANDÉ**

Double-cliquez sur : `scripts\export_dwh_to_postgres.bat`

**Option 2 : Commandes manuelles**

```powershell
# Charger les données sources dans RAW
python scripts/load_all_to_staging.py

# Exécuter le pipeline dbt complet
cd dbt
python -m dbt run

# Exporter vers PostgreSQL
cd ..
python scripts/export_dwh_to_postgres.py
```

**Temps d'exécution** : ~10 minutes

---

## 📂 Structure du projet

```
chu-datawarehouse/
├── data/
│   ├── csv/                           # Fichiers sources CSV
│   │   ├── DECES EN FRANCE/
│   │   ├── Etablissement de SANTE/
│   │   ├── Hospitalisation/
│   │   └── Satisfaction/
│   └── duckdb/
│       ├── staging.duckdb            # Base DuckDB principale
│       └── ods.duckdb                # Base DuckDB ODS (optionnel)
│
├── dbt/
│   ├── models/
│   │   ├── staging/                  # 16 modèles de nettoyage ✅
│   │   │   ├── stg_patient.sql
│   │   │   ├── stg_consultation.sql
│   │   │   ├── stg_specialites.sql  ⭐ REFAIT
│   │   │   └── ...
│   │   │
│   │   ├── ods/                      # 9 modèles d'enrichissement ✅
│   │   │   ├── ods_patient_complet.sql
│   │   │   ├── ods_professionnel_complet.sql ⭐ AMÉLIORÉ
│   │   │   ├── ods_consultation_enrichie.sql
│   │   │   └── ...
│   │   │
│   │   └── marts/
│   │       └── dwh/                  # 13 modèles DWH ⭐ NOUVEAU
│   │           ├── dimensions/       # 8 dimensions
│   │           │   ├── dim_temps.sql
│   │           │   ├── dim_patient.sql
│   │           │   ├── dim_professionnel.sql
│   │           │   └── ...
│   │           └── faits/            # 5 tables de faits
│   │               ├── fait_consultation.sql
│   │               ├── fait_hospitalisation.sql
│   │               └── ...
│   │
│   ├── dbt_project.yml               # Configuration dbt
│   └── profiles.yml                  # Connexions (DuckDB + PostgreSQL)
│
├── scripts/
│   ├── load_all_to_staging.py       # Chargement RAW
│   ├── export_dwh_to_postgres.py    # Export DuckDB → PostgreSQL ⭐
│   └── export_dwh_to_postgres.bat   # Script batch Windows ⭐
│
├── GUIDE_COMPLET_DWH.md              # Guide d'utilisation complet ⭐
├── ANALYSE_CONFORMITE_DWH.md         # Analyse conformité
├── SCHEMA_RAW_columns.md             # Export schéma RAW complet
├── livrable1.md                      # Spécifications projet
└── db_final.sql                      # Schéma cible PostgreSQL
```

---

## 📊 Contenu du Data Warehouse

### 🔷 8 Dimensions

| Dimension | Lignes | Clé substitut | Business key | Points clés |
|-----------|--------|---------------|--------------|-------------|
| **dim_temps** | 5,844 | sk_temps (YYYYMMDD) | date_complete | Générée 2015-2030, jours fériés FR |
| **dim_patient** | ~100k | sk_patient | id_patient | SHA-256 num_secu (RGPD) |
| **dim_professionnel** | ~1M | sk_professionnel | identifiant | SCD Type 2, RPPS/ADELI |
| **dim_specialite** | 93 | sk_specialite | code_specialite | 30+ catégories auto |
| **dim_diagnostic** | ~15k | sk_diagnostic | code_diagnostic | 21 chapitres CIM-10 |
| **dim_etablissement** | ~416k | sk_etablissement | finess | FINESS, 13 régions |
| **dim_localisation** | ~50k | sk_localisation | code_lieu | Corse 2A/2B, GPS |
| **dim_mutuelle** | 254 | sk_mutuelle | id_mut | CMU/Assurance/Mutuelle |

### ⭐ 5 Tables de Faits

| Fait | Lignes | Grain | Mesures principales |
|------|--------|-------|---------------------|
| **fait_consultation** | ~1M | 1 consultation | duree_consultation, nb_consultations |
| **fait_hospitalisation** | ~2.5k | 1 séjour | jour_hospitalisation, nb_hospitalisations |
| **fait_deces** | ~25M | 1 décès | age_deces, nb_deces |
| **fait_satisfaction** | ~5k | 1 établissement × 1 an | scores satisfaction, taux_recommandation |
| **fait_qualite_soins** | ~3k | 1 établissement × 1 an | ratios qualité, alertes |

---

## 🎯 Cas d'usage analytiques

### Analyse des consultations

```sql
-- Top 10 spécialités par volume de consultations
SELECT 
    s.categorie,
    COUNT(*) as nb_consultations,
    AVG(f.duree_consultation) as duree_moyenne_min
FROM datawarehouse.fait_consultation f
JOIN datawarehouse.dim_professionnel p ON f.sk_professionnel = p.sk_professionnel
JOIN datawarehouse.dim_specialite s ON p.fk_specialite = s.sk_specialite
GROUP BY s.categorie
ORDER BY nb_consultations DESC
LIMIT 10;
```

### Analyse des hospitalisations

```sql
-- Durée moyenne de séjour par région
SELECT 
    l.region,
    AVG(f.jour_hospitalisation) as dms,
    COUNT(*) as nb_sejours
FROM datawarehouse.fait_hospitalisation f
JOIN datawarehouse.dim_localisation l ON f.sk_localisation = l.sk_localisation
GROUP BY l.region
ORDER BY dms DESC;
```

### Analyse de satisfaction

```sql
-- Évolution satisfaction par région
SELECT 
    l.region,
    t.annee,
    AVG(f.score_global) as score_moyen,
    COUNT(*) as nb_etablissements
FROM datawarehouse.fait_satisfaction f
JOIN datawarehouse.dim_localisation l ON f.sk_localisation = l.sk_localisation
JOIN datawarehouse.dim_temps t ON f.sk_temps = t.sk_temps
GROUP BY l.region, t.annee
ORDER BY l.region, t.annee;
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| 📘 **GUIDE_COMPLET_DWH.md** | Guide complet d'utilisation et d'exécution |
| 📗 **ANALYSE_CONFORMITE_DWH.md** | Analyse détaillée conformité vs db_final.sql |
| 📕 **livrable1.md** | Spécifications et justifications architecturales |
| 📙 **dbt/models/staging/STATUS_STAGING.md** | Documentation couche STAGING |
| 📒 **dbt/models/ods/STATUS_ODS_REVISE.md** | Documentation couche ODS |
| 📔 **dbt/models/marts/dwh/STATUS_DWH.md** | Documentation couche DWH |
| 📓 **SCHEMA_RAW_columns.md** | Export complet schéma RAW (45 tables) |

---

## 🎓 Points clés de l'implémentation

### Conformité au cahier des charges

✅ **Modèle en constellation** : 5 étoiles métier avec dimensions partagées  
✅ **Stack moderne** : DuckDB (transformations) + PostgreSQL (stockage)  
✅ **Architecture ELT** : Extract-Load-Transform  
✅ **Clés substituts** : Toutes dimensions avec sk_*  
✅ **SCD Type 2** : dim_professionnel historisée  
✅ **RGPD** : num_secu hashé SHA-256  
✅ **Jours fériés** : dim_temps avec fériés français 2015-2025  
✅ **Mapping CIM-10** : 21 chapitres de diagnostics  
✅ **Régions françaises** : 13 régions + Outre-mer + Corse 2A/2B  

### Améliorations vs version initiale

⭐ **stg_specialites** : 30+ catégories médicales auto-détectées  
⭐ **Gestion Corse** : Départements 2A/2B correctement calculés  
⭐ **Parsing dates robuste** : Format mixte m/d/Y et d/m/Y  
⭐ **Types de données corrects** : Pas de VARCHAR où il faut DATE/INT  
⭐ **Aucun SELECT *** sans transformation  
⭐ **dim_temps générée** : 5,844 jours pré-calculés  
⭐ **Fuzzy matching** : Décès matchés avec patients  

---

## ⚙️ Configuration

### DuckDB (transformations)

Configuré dans `dbt/profiles.yml` - target `dev` :

```yaml
dev:
  type: duckdb
  path: ../data/duckdb/staging.duckdb
  schema: staging
  threads: 4
```

### PostgreSQL (stockage final)

Configuré dans `dbt/profiles.yml` - target `prod` :

```yaml
prod:
  type: postgres
  host: localhost
  port: 5432
  user: admin
  password: admin
  dbname: dwh
  schema: dwh
  threads: 4
```

---

## 🚀 Commandes principales

### Chargement des données sources

```powershell
python scripts/load_all_to_staging.py
```

### Exécution du pipeline dbt

```powershell
cd dbt

# Pipeline complet (STAGING → ODS → DWH)
python -m dbt run

# Par zone
python -m dbt run --select tag:staging
python -m dbt run --select tag:ods
python -m dbt run --select marts.dwh

# Par table
python -m dbt run --select dim_temps
python -m dbt run --select fait_consultation
```

### Export vers PostgreSQL

```powershell
# Depuis la racine
python scripts/export_dwh_to_postgres.py

# Ou avec le script batch
scripts\export_dwh_to_postgres.bat
```

### Tests de qualité

```powershell
cd dbt
python -m dbt test
```

---

## 📈 Volumétrie et performance

| Zone | Tables | Lignes | Taille | Temps exec |
|------|--------|--------|--------|------------|
| RAW | 44 | 30M+ | ~3 GB | 5 min (chargement) |
| STAGING | 16 | 30M+ | ~3 GB | 15s |
| ODS | 9 | 29M+ | ~2.5 GB | 20s |
| DWH | 13 | 27M+ | ~2.5 GB | 30s |
| Export PostgreSQL | 13 | 27M+ | ~2.5 GB | 3 min |
| **TOTAL** | | | | **~10 min** |

---

## 🧪 Tests et validation

### Tests automatiques dbt

```powershell
cd dbt

# Tous les tests
python -m dbt test

# Par zone
python -m dbt test --select tag:staging
python -m dbt test --select tag:ods
python -m dbt test --select marts.dwh
```

### Validation manuelle

```sql
-- Dans DuckDB
SELECT COUNT(*) FROM dwh.dim_temps;        -- Attendu: 5,844
SELECT COUNT(*) FROM dwh.dim_patient;      -- Attendu: ~100,000
SELECT COUNT(*) FROM dwh.fait_consultation; -- Attendu: ~1,027,000
SELECT COUNT(*) FROM dwh.fait_deces;       -- Attendu: ~25,088,000

-- Dans PostgreSQL
SELECT COUNT(*) FROM datawarehouse.dim_temps;
SELECT COUNT(*) FROM datawarehouse.fait_consultation;
```

---

## 🛠️ Maintenance

### Rafraîchissement des données

```powershell
# Rafraîchissement complet (quotidien recommandé)
python scripts/load_all_to_staging.py
cd dbt
python -m dbt run
cd ..
python scripts/export_dwh_to_postgres.py
```

### Nettoyage

```powershell
cd dbt
python -m dbt clean     # Supprimer fichiers temporaires
python -m dbt deps      # Réinstaller packages
```

---

## 🎯 Prochaines étapes

### Phase 4 : Datamarts (vues agrégées)

Créer des vues matérialisées optimisées pour Power BI :
- Synthèses consultations par période/spécialité
- KPI hospitaliers (DMS, taux occupation)
- Analyses mortalité géographiques
- Évolution satisfaction temporelle
- Benchmarking qualité inter-établissements

### Phase 5 : Power BI

1. Connexion à PostgreSQL
2. Import tables DWH
3. Relations automatiques
4. Row-Level Security (RLS)
5. Dashboards interactifs

### Phase 6 : Optimisations PostgreSQL

1. Index sur FK
2. Contraintes d'intégrité référentielle
3. Partitionnement fait_deces (25M lignes)
4. Statistiques (ANALYZE)

---

## 🐛 Dépannage

Voir `GUIDE_COMPLET_DWH.md` section Dépannage pour :
- Problèmes de connexion PostgreSQL
- Erreurs dbt
- Problèmes de performance
- Validation des données

---

## 📞 Livrables

### Livrable 1 ✅ **COMPLÉTÉ**
- ✅ Planification projet (Gantt)
- ✅ Stack technologique justifiée
- ✅ Modélisation conceptuelle (constellation)
- ✅ Description dimensions et faits
- ✅ Gestion environnements

### Livrable 2 🔄 **EN COURS**
- ✅ Modèle physique implémenté
- ✅ Chargement initial des données
- 🔄 Tests de validation métier
- 🔄 Optimisation performances

### Livrable 3 🔲 **À VENIR**
- 🔲 Définition KPI
- 🔲 Tableaux de bord Power BI
- 🔲 Row-Level Security
- 🔲 Présentation finale

---

## 👥 Équipe

**Projet** : CHU Data Warehouse  
**Client** : Groupe CHU  
**Durée** : 4 semaines  
**Technologies** : Python, DuckDB, dbt, PostgreSQL, Power BI  

---

## 📜 Licence

Projet académique - CESI 2025

---

**Dernière mise à jour** : 2025-10-13  
**Version** : 3.0 - DWH Complet

🚀 **Prêt pour déploiement !**
