# 🔄 Chargement SOURCES → RAW

## 📋 Vue d'Ensemble

Le chargement **SOURCES → RAW** est la **toute première étape** du pipeline. Elle consiste à extraire les données des sources externes (CSV et PostgreSQL) et les charger **sans transformation** dans DuckDB.

### Principe Fondamental

> **SOURCES = Données externes** (CSV + PostgreSQL)
> 
> **RAW = Données brutes** (chargement 1:1, aucune transformation)
> 
> ✅ **Chargement brut** sans modification  
> ✅ **Préservation types** auto-détectés  
> ✅ **Traçabilité** complète (métadonnées)  
> ❌ **AUCUNE transformation** (même pas TRIM)

---

## 🎯 Sources de Données

### 📂 Source 1 : Fichiers CSV

**Localisation** : `data/csv/`

**Contenu** :
- **Décès** : `DECES EN FRANCE/deces.csv` (~25M lignes)
- **Établissements** : `Etablissement de SANTE/` (3 fichiers, ~2M lignes)
- **Hospitalisations** : `Hospitalisation/Hospitalisations.csv` (~2.5K lignes)
- **Satisfaction** : `Satisfaction/` (31 fichiers sur 2014-2020)

**Format** :
- Encodage : UTF-8 (auto-détecté)
- Délimiteur : `,` ou `;` (auto-détecté par DuckDB)
- Headers : Première ligne = noms de colonnes
- Types : Auto-détectés par DuckDB

### 💾 Source 2 : Base PostgreSQL

**Localisation** : PostgreSQL opérationnel CHU

**Contenu** :
- **Patients** : `patient` (~100K lignes)
- **Professionnels** : `professionnel_de_sante` (~1M lignes)
- **Consultations** : `consultation` (~1M lignes)
- **Prescriptions** : `prescription` (~2M lignes)
- **Diagnostics** : `diagnostic` (~15K lignes)
- **Mutuelles** : `mutuelle` (254 lignes)
- **Adhérents** : `adher` (~193K lignes)
- **Médicaments** : `medicaments` (~15K lignes)
- **Spécialités** : `specialites` (93 lignes)
- **Salles** : `salle` (~201K lignes)
- **Laboratoires** : `laboratoire` (677 lignes)

**Connexion** :
```env
SOURCE_POSTGRES_HOST=localhost
SOURCE_POSTGRES_PORT=5432
SOURCE_POSTGRES_DB=chu_operationnel
SOURCE_POSTGRES_USER=postgres
SOURCE_POSTGRES_PASSWORD=password
```

---

## 🔧 Scripts de Chargement

### 1️⃣ Script Principal : `load_all_to_staging.py`

**Rôle** : Orchestrer le chargement complet

**Fonctionnement** :
```python
# Lance les 2 chargements EN PARALLÈLE
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
    futures = [
        executor.submit(run_script, 'load_csv_to_staging.py'),
        executor.submit(run_script, 'load_postgres_to_staging.py')
    ]
```

**Avantages** :
- ✅ **Parallélisation** : CSV et PostgreSQL chargés simultanément
- ✅ **Gestion erreurs** : Continue même si un script échoue
- ✅ **Résumé** : Statistiques consolidées

**Utilisation** :
```bash
# Lancer le chargement complet
python scripts/load_all_to_staging.py
```

---

### 2️⃣ Script CSV : `load_csv_to_staging.py`

**Rôle** : Charger tous les fichiers CSV dans DuckDB

#### Processus de Chargement

```python
# 1. DÉCOUVERTE : Trouver tous les CSV récursivement
csv_files = list(csv_base_path.rglob('*.csv'))

# 2. NORMALISATION : Créer nom de table depuis chemin
# Exemple : data/csv/DECES EN FRANCE/deces.csv
#        → deces_en_france_deces
table_name = get_relative_path_for_table(csv_file, csv_base_path)

# 3. CHARGEMENT : DuckDB auto-détecte tout
CREATE TABLE raw.{table_name} AS 
SELECT * FROM read_csv_auto('{csv_path}',
    header=true,           -- Première ligne = colonnes
    ignore_errors=true,    -- Continuer si erreurs
    sample_size=-1         -- Scanner tout le fichier pour types
)
```

#### Normalisation Noms de Tables

**Règles** :
1. Supprimer extension `.csv`
2. Remplacer espaces/caractères spéciaux → `_`
3. Convertir en minuscules
4. Inclure chemin parent si dans sous-dossier

**Exemples** :
```
AVANT (fichier)                              → APRÈS (table)
──────────────────────────────────────────────────────────────────
DECES EN FRANCE/deces.csv                    → deces_en_france_deces
Etablissement de SANTE/etablissement_sante.csv → etablissement_de_sante_etablissement_sante
Satisfaction/2014/hpp_mco_2014.csv           → satisfaction_2014_hpp_mco_2014
Hospitalisation/Hospitalisations.csv         → hospitalisation_hospitalisations
```

#### Auto-Détection DuckDB

**DuckDB détecte automatiquement** :
- ✅ **Délimiteur** : `,`, `;`, `\t`, `|`
- ✅ **Encodage** : UTF-8, Latin1, etc.
- ✅ **Types de données** : INTEGER, VARCHAR, DATE, DECIMAL
- ✅ **Formats dates** : `YYYY-MM-DD`, `DD/MM/YYYY`, etc.
- ✅ **Valeurs NULL** : `NULL`, `NA`, vide, etc.

**Exemple d'auto-détection** :
```csv
Id,Nom,Date,Poid,Taille
1,Dupont,4/6/1980,54.3,162
2,Martin,07/25/2013,72,175
```

DuckDB détecte :
- `Id` → INTEGER
- `Nom` → VARCHAR
- `Date` → VARCHAR (format mixte, géré dans STAGING)
- `Poid` → VARCHAR (contient "54.3", géré dans STAGING)
- `Taille` → INTEGER

---

### 3️⃣ Script PostgreSQL : `load_postgres_to_staging.py`

**Rôle** : Charger toutes les tables PostgreSQL dans DuckDB

#### Processus de Chargement

```python
# 1. CONNEXION : Se connecter à PostgreSQL source
pg_conn = psycopg2.connect(
    host='localhost',
    database='chu_operationnel',
    user='postgres'
)

# 2. DÉCOUVERTE : Lister toutes les tables du schéma public
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public'

# 3. EXTRACTION : Pour chaque table
SELECT * FROM public."{table_name}"

# 4. CHARGEMENT : Créer table dans DuckDB via pandas
df = pd.DataFrame(rows, columns=column_names)
CREATE TABLE raw.{table_name} AS SELECT * FROM df
```

#### Mapping des Types

**PostgreSQL → DuckDB** :

| Type PostgreSQL | Type DuckDB | Exemple |
|----------------|-------------|---------|
| `INTEGER` | `INTEGER` | 123 |
| `BIGINT` | `BIGINT` | 123456789012 |
| `NUMERIC` | `DECIMAL` | 54.30 |
| `VARCHAR(n)` | `VARCHAR` | "Dupont" |
| `TEXT` | `VARCHAR` | Texte long |
| `TIMESTAMP` | `TIMESTAMP` | 2023-05-15 14:30:00 |
| `DATE` | `DATE` | 2023-05-15 |
| `BOOLEAN` | `BOOLEAN` | true/false |
| `JSON` | `JSON` | {...} |

#### Gestion des Tables Vides

```python
# Si table vide, créer quand même la structure
if not rows:
    # Récupérer les types de colonnes depuis PostgreSQL
    SELECT column_name, data_type 
    FROM information_schema.columns 
    WHERE table_name = 'ma_table'
    
    # Créer table vide avec la bonne structure
    CREATE TABLE raw.ma_table (
        id INTEGER,
        nom VARCHAR,
        date_creation DATE
    )
```

---

## 📊 Schéma RAW Résultant

### Structure DuckDB

```
staging.duckdb
├── raw/                           ← Schéma RAW (données brutes)
│   ├── patient                    ← Depuis PostgreSQL
│   ├── professionnel_de_sante     ← Depuis PostgreSQL
│   ├── consultation               ← Depuis PostgreSQL
│   ├── prescription               ← Depuis PostgreSQL
│   ├── diagnostic                 ← Depuis PostgreSQL
│   ├── mutuelle                   ← Depuis PostgreSQL
│   ├── adher                      ← Depuis PostgreSQL
│   ├── medicaments                ← Depuis PostgreSQL
│   ├── specialites                ← Depuis PostgreSQL
│   ├── salle                      ← Depuis PostgreSQL
│   ├── laboratoire                ← Depuis PostgreSQL
│   ├── deces_en_france_deces      ← Depuis CSV
│   ├── etablissement_de_sante_etablissement_sante  ← Depuis CSV
│   ├── etablissement_de_sante_professionnel_sante  ← Depuis CSV
│   ├── etablissement_de_sante_activite_professionnel_sante ← Depuis CSV
│   ├── hospitalisation_hospitalisations  ← Depuis CSV
│   └── satisfaction_*             ← 31 fichiers CSV (2014-2020)
│
└── metadata/                      ← Schéma métadonnées
    └── load_history               ← Historique des chargements
```

### Table de Métadonnées

**`metadata.load_history`** :
```sql
CREATE TABLE metadata.load_history (
    history_id INTEGER PRIMARY KEY,   -- ID unique du chargement
    load_id INTEGER,                   -- ID de la session de chargement
    source_name VARCHAR,               -- Chemin du fichier source
    table_name VARCHAR,                -- Nom de la table créée
    load_timestamp TIMESTAMP,          -- Date/heure du chargement
    row_count INTEGER,                 -- Nombre de lignes chargées
    status VARCHAR                     -- SUCCESS ou ERROR
)
```

**Exemple de contenu** :
```
history_id | load_id | source_name                        | table_name                  | row_count | status
-----------|---------|------------------------------------|-----------------------------|-----------|--------
1          | 1       | data/csv/deces.csv                 | deces_en_france_deces       | 25088000  | SUCCESS
2          | 1       | data/csv/etablissement_sante.csv   | etablissement_de_sante_*    | 416000    | SUCCESS
3          | 1       | PostgreSQL:patient                 | patient                     | 100000    | SUCCESS
```

---

## 📊 Transformations Appliquées (ou plutôt NON appliquées)

### ❌ CE QU'ON NE FAIT PAS (RAW = Brut)

| Transformation | Raison | Où le faire ? |
|----------------|--------|---------------|
| **TRIM()** | Garder données brutes | → **STAGING** |
| **UPPER()** | Garder casse originale | → **STAGING** |
| **CAST types** | Auto-détection DuckDB | → **STAGING** (correction) |
| **Filtrage** | Garder toutes les lignes | → **STAGING** |
| **Renommage colonnes** | Garder noms originaux | → **STAGING** |
| **Jointures** | 1 source = 1 table | → **ODS** |
| **Règles métier** | Aucune logique | → **ODS** |

### ✅ CE QU'ON FAIT (Minimal)

| Action | Description | Exemple |
|--------|-------------|---------|
| **Normalisation nom table** | Créer nom valide | `DECES EN FRANCE` → `deces_en_france_deces` |
| **Création schéma** | Créer `raw` si absent | `CREATE SCHEMA IF NOT EXISTS raw` |
| **Auto-détection types** | Laisser DuckDB deviner | DuckDB analyse le fichier |
| **Métadonnées** | Tracer le chargement | `load_history` |
| **Gestion erreurs** | Ignorer erreurs de parsing | `ignore_errors=true` |

---

## 📊 Exemples de Chargement

### Exemple 1 : CSV Simple

**Fichier** : `data/csv/Hospitalisation/Hospitalisations.csv`

```csv
Num_hospitalisation,Id_patient,Date_admission,Date_sortie,Finess,Code_diagnostic
1,1001,2023-01-15,2023-01-18,180036014,J06.9
2,1002,2023-01-20,2023-01-25,200009181,I10
```

**Chargement** :
```python
# Auto-détection par DuckDB
table_name = "hospitalisation_hospitalisations"

CREATE TABLE raw.hospitalisation_hospitalisations AS 
SELECT * FROM read_csv_auto('data/csv/Hospitalisation/Hospitalisations.csv',
    header=true,
    ignore_errors=true,
    sample_size=-1
)
```

**Résultat RAW** :
```sql
SELECT * FROM raw.hospitalisation_hospitalisations LIMIT 2;

Num_hospitalisation | Id_patient | Date_admission | Date_sortie | Finess    | Code_diagnostic
--------------------|------------|----------------|-------------|-----------|----------------
1                   | 1001       | 2023-01-15     | 2023-01-18  | 180036014 | J06.9
2                   | 1002       | 2023-01-20     | 2023-01-25  | 200009181 | I10
```

**Types détectés** :
- `Num_hospitalisation` → INTEGER
- `Id_patient` → INTEGER
- `Date_admission` → DATE
- `Date_sortie` → DATE
- `Finess` → BIGINT
- `Code_diagnostic` → VARCHAR

---

### Exemple 2 : PostgreSQL

**Table source** : `public.patient`

```sql
-- Dans PostgreSQL
SELECT * FROM public.patient LIMIT 2;

Id | Nom    | Prenom | Date       | Sexe | Ville
---|--------|--------|------------|------|-------
1  | Dupont | Jean   | 4/6/1980   | M    | Paris
2  | Martin | Marie  | 07/25/2013 | F    | Lyon
```

**Chargement** :
```python
# Extraction depuis PostgreSQL
pg_cursor.execute('SELECT * FROM public."patient"')
rows = pg_cursor.fetchall()
column_names = [desc[0] for desc in pg_cursor.description]

# Chargement dans DuckDB via pandas
df = pd.DataFrame(rows, columns=column_names)
CREATE TABLE raw.patient AS SELECT * FROM df
```

**Résultat RAW** :
```sql
SELECT * FROM raw.patient LIMIT 2;

Id | Nom    | Prenom | Date       | Sexe | Ville
---|--------|--------|------------|------|-------
1  | Dupont | Jean   | 4/6/1980   | M    | Paris
2  | Martin | Marie  | 07/25/2013 | F    | Lyon
```

**Note** : Les données sont **EXACTEMENT identiques** à la source PostgreSQL (aucune transformation).

---

### Exemple 3 : CSV avec Erreurs

**Fichier** : `data/csv/satisfaction_2014.csv` (avec lignes corrompues)

```csv
Id,Etablissement,Score
1,CHU Paris,85.5
2,Hôpital Lyon,92.3
CORRUPTED LINE WITH WRONG COLUMNS
3,Clinique Nice,78.0
```

**Chargement avec `ignore_errors=true`** :
```python
CREATE TABLE raw.satisfaction_2014 AS 
SELECT * FROM read_csv_auto('data/csv/satisfaction_2014.csv',
    header=true,
    ignore_errors=true,  -- ✅ Ignore la ligne corrompue
    sample_size=-1
)
```

**Résultat** :
```sql
SELECT * FROM raw.satisfaction_2014;

Id | Etablissement  | Score
---|----------------|------
1  | CHU Paris      | 85.5
2  | Hôpital Lyon   | 92.3
3  | Clinique Nice  | 78.0
-- Ligne corrompue ignorée
```

---

## 📋 Sortie Console

### Exemple de Sortie Complète

```
================================================================================
CHARGEMENT COMPLET DU STAGING
================================================================================
Début: 2025-10-21 14:30:00
================================================================================

================================================================================
Lancement de load_csv_to_staging.py...
================================================================================

================================================================================
CHARGEMENT DES CSV DANS LA BASE STAGING
================================================================================
Base de données: data/duckdb/staging.duckdb
Dossier source: data/csv

Load ID: 1

[INFO] 35 fichiers CSV trouvés

  Chargement de deces.csv -> raw.deces_en_france_deces
    [OK] 25,088,000 lignes chargées
  
  Chargement de etablissement_sante.csv -> raw.etablissement_de_sante_etablissement_sante
    [OK] 416,000 lignes chargées
  
  Chargement de Hospitalisations.csv -> raw.hospitalisation_hospitalisations
    [OK] 2,500 lignes chargées
  
  ... (autres fichiers)

================================================================================
RÉSUMÉ
================================================================================
[OK] Fichiers chargés avec succès: 35
[ERREUR] Fichiers en erreur: 0
[INFO] Total de lignes chargées: 27,500,000

Tables créées dans le schéma 'raw':
  - deces_en_france_deces: 25,088,000 lignes, 28 colonnes
  - etablissement_de_sante_etablissement_sante: 416,000 lignes, 24 colonnes
  - hospitalisation_hospitalisations: 2,500 lignes, 8 colonnes
  ... (autres tables)

[SUCCÈS] Chargement terminé!

================================================================================
Lancement de load_postgres_to_staging.py...
================================================================================

================================================================================
CHARGEMENT DES TABLES POSTGRESQL DANS LA BASE STAGING
================================================================================
Base de données DuckDB: data/duckdb/staging.duckdb
PostgreSQL: localhost:5432/chu_operationnel

Connexion à PostgreSQL...
  [OK] Connecté à PostgreSQL
Connexion à DuckDB...
  [OK] Connecté à DuckDB

[INFO] 11 tables trouvées dans PostgreSQL

  Chargement de patient depuis PostgreSQL...
    [OK] 100,000 lignes chargées
  
  Chargement de professionnel_de_sante depuis PostgreSQL...
    [OK] 1,048,575 lignes chargées
  
  Chargement de consultation depuis PostgreSQL...
    [OK] 1,027,000 lignes chargées
  
  ... (autres tables)

================================================================================
RÉSUMÉ
================================================================================
[OK] Tables chargées avec succès: 11
[ERREUR] Tables en erreur: 0
[INFO] Total de lignes chargées: 3,500,000

Tables créées dans le schéma 'raw':
  - patient: 100,000 lignes, 15 colonnes
  - professionnel_de_sante: 1,048,575 lignes, 8 colonnes
  - consultation: 1,027,000 lignes, 10 colonnes
  ... (autres tables)

[SUCCÈS] Chargement terminé!

================================================================================
RÉSUMÉ FINAL
================================================================================
✓ SUCCESS load_csv_to_staging.py (durée: 180.5s)
✓ SUCCESS load_postgres_to_staging.py (durée: 120.3s)
================================================================================
Durée totale: 180.5s  ← Grâce au parallélisme !
Fin: 2025-10-21 14:33:01

✓ Tous les chargements ont réussi!
```

---

## 📊 Volumétrie

| Source | Type | Tables | Lignes | Taille | Temps |
|--------|------|--------|--------|--------|-------|
| **CSV** | Fichiers | 35 | ~27M | ~3 GB | ~3 min |
| **PostgreSQL** | Base de données | 11 | ~3.5M | ~500 MB | ~2 min |
| **TOTAL RAW** | DuckDB | **46** | **~30M** | **~3.5 GB** | **~3 min** ⚡ |

**Note** : Temps parallèle (CSV + Postgres simultanés) = temps du plus lent

---

## 📋 Checklist Qualité RAW

### ✅ Après chargement, vérifier :

- [ ] **Toutes les sources chargées** (46 tables attendues)
- [ ] **Aucune table vide** (sauf si source vide)
- [ ] **Volumétrie cohérente** (~30M lignes total)
- [ ] **Types auto-détectés** corrects (vérifier échantillon)
- [ ] **Métadonnées** présentes (`load_history`)
- [ ] **Schéma `raw`** créé dans DuckDB
- [ ] **Fichier `staging.duckdb`** existe et accessible

### 🔍 Requêtes de Validation

```sql
-- Compter les tables RAW
SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'raw';
-- Attendu: 46 tables

-- Volumétrie totale
SELECT 
    table_name,
    (SELECT COUNT(*) FROM raw.|| table_name) as row_count
FROM information_schema.tables
WHERE table_schema = 'raw'
ORDER BY row_count DESC;

-- Vérifier métadonnées
SELECT * FROM metadata.load_history WHERE load_id = 1;

-- Tables les plus volumineuses
SELECT table_name, row_count 
FROM (
    SELECT table_name, (SELECT COUNT(*) FROM raw.|| table_name) as row_count
    FROM information_schema.tables WHERE table_schema = 'raw'
) ORDER BY row_count DESC LIMIT 10;
```

---

## 🚫 Anti-Patterns (À Éviter)

### ❌ MAUVAIS : Transformer dans RAW

```python
# ❌ PAS BON !
CREATE TABLE raw.patient AS 
SELECT 
    Id,
    TRIM(UPPER(Nom)) as Nom,  -- ← Transformation !
    Date::DATE as Date        -- ← Cast !
FROM read_csv_auto('patient.csv')
```

**Correct** : RAW = données brutes

```python
# ✅ BON !
CREATE TABLE raw.patient AS 
SELECT * FROM read_csv_auto('patient.csv')
-- Aucune transformation, données exactement comme dans le CSV
```

### ❌ MAUVAIS : Filtrer dans RAW

```sql
-- ❌ PAS BON !
CREATE TABLE raw.patient AS 
SELECT * FROM read_csv_auto('patient.csv')
WHERE Id IS NOT NULL  -- ← Filtrage !
```

**Correct** : Filtrer dans STAGING

---

## 🎯 Prochaine Étape : STAGING

Une fois le **RAW** chargé, on passe au **STAGING** où on va :

✅ **Nettoyer** les données (TRIM, UPPER)  
✅ **Caster** les types corrects  
✅ **Filtrer** les lignes invalides  
✅ **Parser** les dates  
✅ **Calculer** des champs basiques

Voir `docs/TRANSFORMATIONS_RAW_TO_STAGING.md`

---

## 🔄 Workflow Complet

```
SOURCES EXTERNES
├── CSV (data/csv/)
│   ├── 35 fichiers
│   └── ~27M lignes
└── PostgreSQL (chu_operationnel)
    ├── 11 tables
    └── ~3.5M lignes

    ↓ [load_all_to_staging.py]
    ↓ (parallèle : CSV + PostgreSQL)
    
RAW (staging.duckdb)
├── 46 tables
├── ~30M lignes
└── Données BRUTES (aucune transformation)

    ↓ [dbt run --select tag:staging]
    
STAGING (suite du pipeline...)
```

---

**Auteur** : Équipe Big Data Groupe 3  
**Version** : 1.0  
**Date** : 2025-10-21

