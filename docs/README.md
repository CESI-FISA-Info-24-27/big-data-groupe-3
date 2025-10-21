# 📚 Documentation Complète - CHU Data Warehouse

## 🎯 Vue d'Ensemble

Cette documentation couvre **l'intégralité du pipeline** CHU Data Warehouse, depuis les sources externes jusqu'aux tableaux de bord Power BI.

---

## 📖 Documentation Disponible

### 🎓 Guide Principal

📘 **[INDEX_TRANSFORMATIONS.md](./INDEX_TRANSFORMATIONS.md)** ⭐ **POINT D'ENTRÉE**
- Vue d'ensemble complète du pipeline
- Navigation vers toutes les documentations
- Workflow bout-en-bout
- Métriques de performance

---

### 🔄 Documentation des Transformations

#### Étape 0 : Chargement Initial

📄 **[CHARGEMENT_SOURCES_TO_RAW.md](./CHARGEMENT_SOURCES_TO_RAW.md)**
- Chargement CSV + PostgreSQL → DuckDB RAW
- Parallélisation (CSV + PostgreSQL simultanés)
- Auto-détection types
- Aucune transformation (données brutes)
- **Temps** : ~3 minutes
- **Résultat** : 46 tables RAW, ~30M lignes

#### Étape 1 : Nettoyage

📄 **[TRANSFORMATIONS_RAW_TO_STAGING.md](./TRANSFORMATIONS_RAW_TO_STAGING.md)**
- RAW → STAGING : Nettoyage basique
- Transformations : TRIM, CAST, Parsing dates, Filtrage
- Principe : 1 table RAW = 1 table STAGING
- ❌ Pas de jointures
- **Temps** : ~15 secondes
- **Résultat** : 16 modèles, ~30M lignes

#### Étape 2 : Intégration

📄 **[TRANSFORMATIONS_STAGING_TO_ODS.md](./TRANSFORMATIONS_STAGING_TO_ODS.md)**
- STAGING → ODS : Jointures et enrichissements
- Transformations : Jointures, Règles métier, Agrégations
- Principe : N tables → 1 vue métier enrichie
- ✅ Jointures autorisées
- **Temps** : ~20 secondes
- **Résultat** : 9 modèles, ~29M lignes

#### Étape 3 : Modélisation

📄 **[TRANSFORMATIONS_ODS_TO_DWH.md](./TRANSFORMATIONS_ODS_TO_DWH.md)**
- ODS → DWH : Architecture en étoile
- Transformations : Clés substituts, Dimensions/Faits, SCD Type 2, Anonymisation
- Principe : Modèle dimensionnel (star schema)
- ✅ Clés substituts (sk_*)
- **Temps** : ~30 secondes
- **Résultat** : 13 modèles (8 dims + 5 faits), ~27M lignes

#### Étape 4 : Optimisation BI

📄 **[TRANSFORMATIONS_DWH_TO_DATAMART.md](./TRANSFORMATIONS_DWH_TO_DATAMART.md)**
- DWH → DATAMART : Agrégations pré-calculées
- Transformations : Agrégations complexes, KPI, Dénormalisation
- Principe : Vues optimisées pour Power BI
- ✅ Tout pré-calculé
- **Temps** : ~8 minutes (optimisé via extension Postgres)
- **Résultat** : 3 modèles, ~45M lignes agrégées

---

### 📚 Référence Technique

📕 **[DICTIONNAIRE_DONNEES_DWH.md](./DICTIONNAIRE_DONNEES_DWH.md)**
- Description complète de toutes les tables DWH
- Structure détaillée :
  - 8 Dimensions (colonnes, types, contraintes, index)
  - 5 Faits (grain, mesures, FK)
  - 4 Vues analytiques
- Diagramme de relations
- Volumétrie détaillée
- Exemples de requêtes
- Glossaire technique

---

## 🚀 Pipeline Complet

```
SOURCES (CSV + PostgreSQL)
    ↓ ~3 min (parallèle)
RAW (46 tables, ~30M lignes)
    ↓ ~15s (nettoyage)
STAGING (16 modèles)
    ↓ ~20s (jointures)
ODS (9 modèles)
    ↓ ~30s (modélisation)
DWH (13 modèles : 8 dims + 5 faits)
    ↓ ~3 min (push)
PostgreSQL DWH (schéma dwh)
    ↓ ~8 min (agrégations optimisées)
DATAMART (3 modèles, schéma datamart)
    ↓
POWER BI (connexion directe)

TOTAL : ~15 minutes
```

---

## 📊 Architecture Technique

### Couches de Données

| Couche | Outil | Schéma | Tables | Volumétrie | Principe |
|--------|-------|--------|--------|------------|----------|
| **RAW** | DuckDB | `raw` | 46 | ~30M | Données brutes (0 transformation) |
| **STAGING** | DuckDB | `staging` | 16 | ~30M | Nettoyage basique |
| **ODS** | DuckDB | `ods` | 9 | ~29M | Intégration métier |
| **DWH** | DuckDB → PostgreSQL | `dwh` | 13 | ~27M | Modèle dimensionnel |
| **DATAMART** | PostgreSQL | `datamart` | 3 | ~45M | Agrégations pré-calculées |

### Technologies

- **DuckDB** : Transformations (STAGING → ODS → DWH)
- **dbt** : Orchestration des transformations
- **PostgreSQL** : Stockage final (DWH + DATAMART)
- **Python** : Scripts de chargement et export
- **Power BI** : Visualisation (connexion PostgreSQL)

---

## 📋 Tables du DWH

### 🔷 Dimensions (8)

| Dimension | Business Key | Volumétrie | Type SCD | Description |
|-----------|--------------|------------|----------|-------------|
| `dim_patient` | `id_patient` | ~100K | Type 1 | Patients (RGPD : noms hashés) |
| `dim_professionnel` | `identifiant` (RPPS/ADELI) | ~1M | **Type 2** | Professionnels historisés |
| `dim_temps` | `date_complete` | 5,845 | - | Calendrier 2015-2030, jours fériés FR |
| `dim_specialite` | `code_specialite` | 94 | Type 1 | 30+ catégories médicales |
| `dim_diagnostic` | `code_diagnostic` (CIM-10) | ~15K | Type 1 | 21 chapitres CIM-10 |
| `dim_etablissement` | `finess` | 201 | Type 1 | CHU/Hôpitaux/Cliniques (classification auto) |
| `dim_localisation` | `code_lieu` | ~40K | Type 1 | Consolidation géographique (13 régions) |
| `dim_mutuelle` | `id_mut` | 255 | Type 1 | CMU/Assurance/Mutuelle |

### ⭐ Faits (5)

| Fait | Grain | Volumétrie | Mesures | Rafraîchissement |
|------|-------|------------|---------|------------------|
| `fait_consultation` | 1 consultation | ~2M | duree_consultation, nb_consultations | Quotidien |
| `fait_hospitalisation` | 1 séjour | ~5K | jour_hospitalisation (DMS), nb_hospitalisations | Mensuel |
| `fait_deces` | 1 décès | ~25M | age_deces, nb_deces | Annuel |
| `fait_satisfaction` | 1 établissement × 1 an | ~5K | scores satisfaction, taux_recommandation | Annuel |
| `fait_qualite_soins` | 1 établissement × 1 an | ~3K | ratios IPAQSS, alertes | Annuel |

---

## 🎯 Cas d'Usage

### Analyses Consultations

```sql
-- Consultations par spécialité
SELECT 
    s.categorie,
    t.annee,
    COUNT(*) AS nb_consultations
FROM fait_consultation fc
JOIN dim_professionnel p ON fc.sk_professionnel = p.sk_professionnel
JOIN dim_specialite s ON p.fk_specialite = s.sk_specialite
JOIN dim_temps t ON fc.sk_temps = t.sk_temps
GROUP BY s.categorie, t.annee;
```

### Analyses Hospitalisations

```sql
-- DMS par région
SELECT 
    e.region,
    AVG(fh.jour_hospitalisation) AS dms
FROM fait_hospitalisation fh
JOIN dim_etablissement e ON fh.sk_etablissement = e.sk_etablissement
GROUP BY e.region;
```

### Analyses Territoriales

```sql
-- Mortalité et satisfaction par région
SELECT 
    l.region,
    COUNT(DISTINCT fd.sk_fait_deces) AS nb_deces,
    AVG(fs.score_global) AS satisfaction_moyenne
FROM fait_deces fd
JOIN dim_localisation l ON fd.sk_localisation = l.sk_localisation
LEFT JOIN fait_satisfaction fs ON l.region = (...)
GROUP BY l.region;
```

---

## 🛠️ Utilisation

### Lecture Recommandée (Par Ordre)

1. **Débutant** : Commencer par [`INDEX_TRANSFORMATIONS.md`](./INDEX_TRANSFORMATIONS.md)
2. **Développeur** : Lire les transformations dans l'ordre (RAW → STAGING → ODS → DWH → DATAMART)
3. **Analyste** : Consulter [`DICTIONNAIRE_DONNEES_DWH.md`](./DICTIONNAIRE_DONNEES_DWH.md)
4. **Architecte** : Tout lire 😊

### Par Besoin

| Besoin | Documentation |
|--------|---------------|
| "Comment les données sont chargées ?" | `CHARGEMENT_SOURCES_TO_RAW.md` |
| "Quelles transformations dans STAGING ?" | `TRANSFORMATIONS_RAW_TO_STAGING.md` |
| "Comment sont faites les jointures ?" | `TRANSFORMATIONS_STAGING_TO_ODS.md` |
| "Qu'est-ce qu'une clé substitut ?" | `TRANSFORMATIONS_ODS_TO_DWH.md` |
| "Pourquoi le datamart est agrégé ?" | `TRANSFORMATIONS_DWH_TO_DATAMART.md` |
| "Quelle est la structure de dim_patient ?" | `DICTIONNAIRE_DONNEES_DWH.md` |
| "Vue d'ensemble complète ?" | `INDEX_TRANSFORMATIONS.md` |

---

## 📈 Métriques Clés

### Performance

| Étape | Temps | Volume | Outil |
|-------|-------|--------|-------|
| Chargement sources | 3 min | 30M lignes | Python (parallèle) |
| Transformations dbt | 1 min | 30M → 27M | dbt + DuckDB |
| Push PostgreSQL | 3 min | 27M lignes | Python + COPY |
| Création datamart | 8 min | 45M lignes | DuckDB + Extension Postgres |
| **TOTAL** | **~15 min** | **30M → 45M** | - |

### Volumétrie

- **Sources** : 46 fichiers/tables, ~30M lignes
- **RAW** : 46 tables, ~30M lignes, ~3.5 GB
- **STAGING** : 16 modèles, ~30M lignes
- **ODS** : 9 modèles, ~29M lignes
- **DWH** : 13 modèles (8 dims + 5 faits), ~27M lignes, ~3 GB
- **DATAMART** : 3 modèles, ~45M lignes agrégées

---

## 🎓 Concepts Clés

### Glossaire

| Terme | Définition |
|-------|------------|
| **RAW** | Données brutes sans transformation |
| **STAGING** | Nettoyage basique (1:1 avec RAW) |
| **ODS** | Operational Data Store (intégration métier) |
| **DWH** | Data Warehouse (modèle dimensionnel) |
| **DATAMART** | Vues agrégées optimisées pour BI |
| **Clé substitut (sk_*)** | Clé technique auto-générée |
| **Business key** | Clé métier source (ID original) |
| **SCD Type 2** | Historisation complète des changements |
| **Grain** | Niveau de détail d'un fait |
| **Mesure** | Métrique numérique (COUNT, SUM, AVG) |

### Principes par Couche

```
RAW      : "Données brutes, 0 transformation"
STAGING  : "Nettoyage simple, 1:1 avec RAW"
ODS      : "Intégration métier, jointures autorisées"
DWH      : "Modèle dimensionnel, star schema"
DATAMART : "Pré-calculs BI, tout agrégé"
```

---

## 🔄 Workflow Recommandé

### Full Build (Premier Déploiement)

```bash
# Mode automatique
python scripts/admin_pipeline.py --full

# Ou étape par étape
python scripts/load_all_to_staging.py          # 1. Sources → RAW
cd dbt && dbt run && cd ..                      # 2. RAW → STAGING → ODS → DWH
python scripts/push_dwh_to_postgres.py          # 3. DWH → PostgreSQL
python scripts/build_datamart_via_postgres.py   # 4. DWH → DATAMART (optimisé)
```

### Rafraîchissement Quotidien

```bash
# Recharger nouvelles données
python scripts/admin_pipeline.py --step 1,2,3,4

# Ou seulement datamart (si DWH déjà à jour)
python scripts/admin_pipeline.py --step 4
```

---

## 📊 Structure de la Documentation

```
docs/
├── README.md                                    ← Vous êtes ici
├── INDEX_TRANSFORMATIONS.md                     ← Point d'entrée principal
│
├── Transformations (5 documents)
│   ├── CHARGEMENT_SOURCES_TO_RAW.md            ← Étape 0
│   ├── TRANSFORMATIONS_RAW_TO_STAGING.md       ← Étape 1
│   ├── TRANSFORMATIONS_STAGING_TO_ODS.md       ← Étape 2
│   ├── TRANSFORMATIONS_ODS_TO_DWH.md           ← Étape 3
│   └── TRANSFORMATIONS_DWH_TO_DATAMART.md      ← Étape 4
│
└── Références
    └── DICTIONNAIRE_DONNEES_DWH.md             ← Référence technique
```

---

## 🎯 Par Profil Utilisateur

### 👨‍💼 Chef de Projet / Product Owner

**À lire** :
1. `INDEX_TRANSFORMATIONS.md` - Vue d'ensemble
2. `DICTIONNAIRE_DONNEES_DWH.md` - Comprendre les données disponibles

**Temps de lecture** : ~30 minutes

---

### 👨‍💻 Développeur / Data Engineer

**À lire** (dans l'ordre) :
1. `INDEX_TRANSFORMATIONS.md`
2. `CHARGEMENT_SOURCES_TO_RAW.md`
3. `TRANSFORMATIONS_RAW_TO_STAGING.md`
4. `TRANSFORMATIONS_STAGING_TO_ODS.md`
5. `TRANSFORMATIONS_ODS_TO_DWH.md`
6. `TRANSFORMATIONS_DWH_TO_DATAMART.md`
7. `DICTIONNAIRE_DONNEES_DWH.md`

**Temps de lecture** : ~2-3 heures (lecture complète)

---

### 📊 Analyste / Data Analyst

**À lire** :
1. `DICTIONNAIRE_DONNEES_DWH.md` - Structure des tables
2. `TRANSFORMATIONS_DWH_TO_DATAMART.md` - Comprendre les agrégations
3. `INDEX_TRANSFORMATIONS.md` - Vue d'ensemble

**Temps de lecture** : ~1 heure

---

### 🎨 Développeur BI / Power BI

**À lire** :
1. `DICTIONNAIRE_DONNEES_DWH.md` - Tables disponibles
2. `TRANSFORMATIONS_DWH_TO_DATAMART.md` - Tables DATAMART optimisées
3. Exemples de requêtes dans chaque document

**Temps de lecture** : ~45 minutes

---

## 🎓 Formation

### Parcours d'Apprentissage

#### Niveau 1 : Débutant (2h)
1. Lire `INDEX_TRANSFORMATIONS.md`
2. Comprendre le workflow global
3. Exécuter le pipeline avec `admin_pipeline.py`

#### Niveau 2 : Intermédiaire (1 jour)
1. Lire toutes les transformations (5 documents)
2. Comprendre chaque étape en détail
3. Modifier un modèle STAGING
4. Tester avec `dbt run --select mon_modele`

#### Niveau 3 : Avancé (3 jours)
1. Lire toute la documentation
2. Comprendre l'architecture en profondeur
3. Créer un nouveau modèle ODS
4. Implémenter un nouveau KPI dans DATAMART
5. Optimiser les performances

---

## 📚 Documents Complémentaires

Ces documents existent aussi dans le projet :

- `../README.md` - README principal du projet
- `livrable1.md` - Spécifications et justifications
- `dbt/models/staging/STATUS_STAGING.md` - Statut STAGING
- `dbt/models/ods/STATUS_ODS_REVISE.md` - Statut ODS
- `db.sql` - Schéma SQL cible PostgreSQL

---

## ❓ FAQ

**Q: Par où commencer ?**  
R: Lire [`INDEX_TRANSFORMATIONS.md`](./INDEX_TRANSFORMATIONS.md)

**Q: Je cherche la structure d'une table DWH ?**  
R: Consulter [`DICTIONNAIRE_DONNEES_DWH.md`](./DICTIONNAIRE_DONNEES_DWH.md)

**Q: Comment sont nettoyées les données ?**  
R: Voir [`TRANSFORMATIONS_RAW_TO_STAGING.md`](./TRANSFORMATIONS_RAW_TO_STAGING.md)

**Q: Comment sont faites les jointures ?**  
R: Voir [`TRANSFORMATIONS_STAGING_TO_ODS.md`](./TRANSFORMATIONS_STAGING_TO_ODS.md)

**Q: C'est quoi une clé substitut ?**  
R: Voir [`TRANSFORMATIONS_ODS_TO_DWH.md`](./TRANSFORMATIONS_ODS_TO_DWH.md) - Section "Génération Clés Substituts"

**Q: Pourquoi le datamart est si gros ?**  
R: Voir [`TRANSFORMATIONS_DWH_TO_DATAMART.md`](./TRANSFORMATIONS_DWH_TO_DATAMART.md) - Agrégations pré-calculées

---

## ✅ Documentation Complète

- ✅ **6 documents** de transformations
- ✅ **1 dictionnaire** de données complet
- ✅ **1 index** récapitulatif
- ✅ **Exemples SQL** partout
- ✅ **Avant/Après** pour chaque transformation
- ✅ **Anti-patterns** documentés
- ✅ **Checklist qualité** pour chaque couche
- ✅ **Glossaire** technique

**Total** : ~3,000 lignes de documentation ! 📚

---

**Auteur** : Équipe Big Data Groupe 3  
**Version** : 2.0  
**Date** : 2025-10-21  
**Statut** : ✅ Documentation complète

🎉 **Le pipeline CHU DWH est entièrement documenté !**

