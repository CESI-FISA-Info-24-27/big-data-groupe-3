# 🔄 Transformations RAW → STAGING

## 📋 Vue d'Ensemble

La couche **STAGING** est la **première étape de nettoyage** des données brutes (RAW).

### Principe Fondamental

> **1 table RAW = 1 table STAGING**
> 
> ❌ **PAS de jointures** dans STAGING  
> ❌ **PAS de logique métier** complexe  
> ✅ **Nettoyage basique** uniquement

---

## 🎯 Types de Transformations Appliquées

### ✅ CE QU'ON FAIT (Autorisé)

| Type | Description | Exemple |
|------|-------------|---------|
| **Renommage** | Standardiser noms colonnes | `Id` → `id_patient` |
| **Cast** | Convertir types de données | `VARCHAR` → `DATE`, `INTEGER` |
| **Trim/Nettoyage** | Supprimer espaces, standardiser casse | `TRIM(UPPER(nom))` |
| **Valeurs par défaut** | Remplacer NULL par défaut | `COALESCE(pays, 'FR')` |
| **Filtrage simple** | Supprimer lignes invalides | `WHERE id IS NOT NULL` |
| **Calculs simples** | Calculs arithmétiques basiques | `(taille - poids) AS imc` |
| **Parsing dates** | Convertir VARCHAR → DATE | `TRY_STRPTIME(date, '%m/%d/%Y')` |
| **Dédoublonnage** | Supprimer doublons exacts | `QUALIFY ROW_NUMBER() = 1` |
| **Métadonnées** | Ajouter timestamp chargement | `CURRENT_TIMESTAMP AS loaded_at` |

### ❌ CE QU'ON NE FAIT PAS (Interdit)

| Type | Raison | Où le faire ? |
|------|--------|---------------|
| **Jointures** | Combine plusieurs sources | → **ODS** |
| **Agrégations** | GROUP BY, SUM, COUNT | → **ODS** ou **DWH** |
| **Règles métier** | Logique business complexe | → **ODS** |
| **CASE complexe** | Catégorisation métier avancée | → **ODS** |
| **Window functions** | RANK, DENSE_RANK (sauf dédoublonnage) | → **ODS** |

---

## 📊 Exemples Concrets par Table

### 1️⃣ `stg_patient` ⭐ (Exemple Complet)

**Source** : `raw.patient`

#### Transformations Appliquées

```sql
-- ✅ RENOMMAGE
Id → id_patient
Nom → nom
Prenom → prenom

-- ✅ NETTOYAGE
TRIM(UPPER(Nom)) AS nom                    -- Espaces + majuscules
TRIM(UPPER(Prenom)) AS prenom

-- ✅ PARSING DATES (multi-format robuste)
COALESCE(
    TRY_STRPTIME(Date, '%m/%d/%Y'),        -- Format US
    TRY_STRPTIME(Date, '%d/%m/%Y'),        -- Format FR
    TRY_CAST(Date AS DATE)                 -- Fallback
) AS date_naissance

-- ✅ CAST TYPES
TRY_CAST(Poid AS DECIMAL(5,2)) AS poids   -- "54.3" → 54.30
TRY_CAST(Taille AS INTEGER) AS taille     -- "162" → 162
TRY_CAST(Num_secu AS BIGINT) AS num_secu

-- ✅ CALCULS SIMPLES
DATE_PART('year', CURRENT_DATE) - DATE_PART('year', date_naissance) AS age

-- ✅ VALEURS PAR DÉFAUT
COALESCE(Pays, 'FR') AS pays
COALESCE(Sexe, 'I') AS sexe               -- I = Inconnu

-- ✅ CATÉGORISATION SIMPLE
CASE
    WHEN age < 18 THEN '0-18'
    WHEN age BETWEEN 19 AND 30 THEN '19-30'
    WHEN age BETWEEN 31 AND 50 THEN '31-50'
    WHEN age BETWEEN 51 AND 65 THEN '51-65'
    ELSE '66+'
END AS tranche_age

-- ✅ FILTRAGE
WHERE Id IS NOT NULL
```

**Avant (RAW)** :
```
Id  | Nom    | Date       | Poid  | Taille | Sexe | Pays
----|--------|------------|-------|--------|------|-----
1   | dupont | 4/6/1980   | 54.3  | 162    | NULL | NULL
2   |  MARTIN| 07/25/2013 | 72    | 175    | M    | FR
```

**Après (STAGING)** :
```
id_patient | nom    | date_naissance | poids | taille | sexe | pays | age | tranche_age
-----------|--------|----------------|-------|--------|------|------|-----|------------
1          | DUPONT | 1980-06-04     | 54.30 | 162    | I    | FR   | 44  | 31-50
2          | MARTIN | 2013-07-25     | 72.00 | 175    | M    | FR   | 11  | 0-18
```

---

### 2️⃣ `stg_specialites` ⭐ (Classification Auto)

**Source** : `raw.specialites`

#### Transformations

```sql
-- ✅ NETTOYAGE
TRIM(UPPER(Code_specialite)) AS code_specialite
TRIM(Fonction) AS fonction
TRIM(Specialite) AS specialite

-- ✅ CLASSIFICATION AUTOMATIQUE (30+ catégories)
CASE
    WHEN LOWER(Fonction) LIKE '%medecin generaliste%' THEN 'Medecine generale'
    WHEN LOWER(Fonction) LIKE '%medecin%' AND Specialite IS NOT NULL THEN 'Medecine specialisee'
    WHEN LOWER(Fonction) LIKE '%infirmier%' THEN 'Soins infirmiers'
    WHEN LOWER(Fonction) LIKE '%kinesitherapeute%' THEN 'Reeducation'
    WHEN LOWER(Fonction) LIKE '%pharmacien%' THEN 'Pharmacie'
    WHEN LOWER(Fonction) LIKE '%psychologue%' THEN 'Sante mentale'
    WHEN LOWER(Fonction) LIKE '%radiologue%' THEN 'Imagerie medicale'
    -- ... 20+ autres catégories
    ELSE 'Autre'
END AS categorie
```

**Avant** :
```
Code_specialite | Fonction                  | Specialite
----------------|---------------------------|------------
SM26            | Infirmier                 | NULL
SM54            | Médecin spécialiste       | Cardiologie
```

**Après** :
```
code_specialite | fonction          | specialite  | categorie
----------------|-------------------|-------------|-------------------
SM26            | Infirmier         | NULL        | Soins infirmiers
SM54            | Médecin spécialiste| Cardiologie | Medecine specialisee
```

---

### 3️⃣ `stg_consultation` (Calculs Métier Basiques)

**Source** : `raw.consultation`

#### Transformations

```sql
-- ✅ CALCULS AUTOMATIQUES
CAST(Heure_arrivee AS TIME) AS heure_arrivee
CAST(Heure_depart AS TIME) AS heure_depart

-- Calcul durée en minutes
DATE_PART('hour', heure_depart - heure_arrivee) * 60 +
DATE_PART('minute', heure_depart - heure_arrivee) 
AS duree_consultation_minutes

-- ✅ FILTRAGE
WHERE num_consultation IS NOT NULL
  AND id_patient IS NOT NULL
  AND heure_depart > heure_arrivee  -- Cohérence temporelle
```

**Avant** :
```
num_consultation | heure_arrivee | heure_depart
-----------------|---------------|-------------
1                | 09:00:00      | 09:30:00
2                | 14:15:00      | 15:45:00
```

**Après** :
```
num_consultation | heure_arrivee | heure_depart | duree_consultation_minutes
-----------------|---------------|--------------|---------------------------
1                | 09:00:00      | 09:30:00     | 30
2                | 14:15:00      | 15:45:00     | 90
```

---

### 4️⃣ `stg_etablissement_sante` (Gestion Corse)

**Source** : `raw.etablissement_de_sante_etablissement_sante`

#### Transformations

```sql
-- ✅ CALCUL DÉPARTEMENT (avec gestion Corse 2A/2B)
CASE
    -- Cas spécial Corse (20xxx)
    WHEN SUBSTRING(TRIM(code_postal), 1, 2) = '20' 
         AND LENGTH(TRIM(code_postal)) >= 3 THEN
        CASE
            -- 200xx, 201xx → 2A (Corse-du-Sud)
            WHEN TRY_CAST(SUBSTRING(TRIM(code_postal), 3, 1) AS INTEGER) < 2 
            THEN '2A'
            -- 202xx à 209xx → 2B (Haute-Corse)
            ELSE '2B'
        END
    -- Cas général (2 premiers chiffres)
    WHEN LENGTH(TRIM(code_postal)) >= 2 
    THEN SUBSTRING(TRIM(code_postal), 1, 2)
    ELSE NULL
END AS departement
```

**Avant** :
```
finess  | code_postal | nom
--------|-------------|-----
010001  | 20000       | Hôpital Ajaccio
010002  | 20200       | Hôpital Bastia
010003  | 75001       | Hôpital Paris
```

**Après** :
```
finess  | code_postal | nom              | departement
--------|-------------|------------------|------------
010001  | 20000       | Hôpital Ajaccio  | 2A
010002  | 20200       | Hôpital Bastia   | 2B
010003  | 75001       | Hôpital Paris    | 75
```

---

### 5️⃣ `stg_deces` (Gros Volume)

**Source** : `raw.deces_en_france_deces` (25M+ lignes)

#### Transformations

```sql
-- ✅ PARSING DATES ROBUSTE
TRY_CAST(date_deces AS DATE) AS date_deces
TRY_CAST(date_naissance AS DATE) AS date_naissance

-- ✅ CALCUL AGE AU DÉCÈS
DATE_PART('year', date_deces) - DATE_PART('year', date_naissance) AS age_deces

-- ✅ NETTOYAGE GÉOGRAPHIE
TRIM(UPPER(commune_deces)) AS commune_deces
TRIM(departement_deces) AS departement_deces

-- ✅ FILTRAGE
WHERE date_deces IS NOT NULL
```

---

### 6️⃣ `stg_mutuelle` (Classification Type)

**Source** : `raw.mutuelle`

#### Transformations

```sql
-- ✅ CLASSIFICATION AUTOMATIQUE TYPE
CASE
    WHEN LOWER(nom_mut) LIKE '%cmu%' THEN 'CMU'
    WHEN LOWER(nom_mut) LIKE '%assurance%' THEN 'Assurance'
    WHEN LOWER(nom_mut) LIKE '%mutuelle%' THEN 'Mutuelle'
    ELSE 'Autre'
END AS type_mutuelle
```

**Avant** :
```
id_mut | nom_mut
-------|------------------
1      | CMU-C
2      | Mutuelle Santé +
3      | Assurance Maladie
```

**Après** :
```
id_mut | nom_mut           | type_mutuelle
-------|-------------------|---------------
1      | CMU-C             | CMU
2      | Mutuelle Santé +  | Mutuelle
3      | Assurance Maladie | Assurance
```

---

## 📊 Transformations par Type

### 🔤 Nettoyage Texte (Tous les modèles)

```sql
-- Espaces superflus
TRIM(colonne)

-- Casse standardisée
UPPER(colonne)
LOWER(colonne)

-- Combinaison
TRIM(UPPER(colonne))
```

### 📅 Parsing Dates

```sql
-- Simple
CAST(colonne AS DATE)

-- Robuste (multi-format)
COALESCE(
    TRY_STRPTIME(colonne, '%m/%d/%Y'),  -- US
    TRY_STRPTIME(colonne, '%d/%m/%Y'),  -- FR
    TRY_CAST(colonne AS DATE)
) AS date_propre

-- Extraction parties
DATE_PART('year', date_colonne)
DATE_PART('month', date_colonne)
DATE_PART('day', date_colonne)
```

### 🔢 Cast Types

```sql
-- Entiers
CAST(colonne AS INTEGER)
CAST(colonne AS BIGINT)
TRY_CAST(colonne AS INTEGER)  -- Sûr (NULL si échec)

-- Décimaux
CAST(colonne AS DECIMAL(10,2))
TRY_CAST(colonne AS DECIMAL(5,2))

-- Temps
CAST(colonne AS TIME)
CAST(colonne AS TIMESTAMP)
```

### 🎯 Valeurs par Défaut

```sql
-- Simple
COALESCE(colonne, 'VALEUR_DEFAUT')
COALESCE(pays, 'FR')
COALESCE(sexe, 'I')

-- Avec expression
COALESCE(email, 'non_renseigne@chu.fr')
COALESCE(telephone, '0000000000')
```

### ✂️ Extraction Parties

```sql
-- Substring
SUBSTRING(code_postal, 1, 2) AS departement

-- Expressions régulières (DuckDB)
REGEXP_EXTRACT(colonne, 'pattern')
```

---

## 📋 Checklist Qualité STAGING

### ✅ Chaque modèle doit avoir :

- [ ] **Pas de `SELECT *`** sans transformation
- [ ] **Colonnes explicitement nommées**
- [ ] **Types de données corrects** (CAST)
- [ ] **Nettoyage appliqué** (TRIM, UPPER)
- [ ] **Business key validée** (NOT NULL)
- [ ] **CTE `source`** pour lecture raw
- [ ] **CTE `cleaned`** pour transformations
- [ ] **Timestamp `loaded_at`** ajouté
- [ ] **Tests configurés** dans schema.yml
- [ ] **Documentation** avec description

---

## 🚫 Anti-Patterns (À Éviter)

### ❌ MAUVAIS : Jointure dans STAGING

```sql
-- ❌ PAS BON !
SELECT
    p.id_patient,
    p.nom,
    m.nom_mutuelle  -- ← Jointure = ODS !
FROM {{ source('raw', 'patient') }} p
LEFT JOIN {{ source('raw', 'mutuelle') }} m
    ON p.id_mut = m.id_mut
```

**Correct** : Faire ça dans **ODS**, pas STAGING !

### ❌ MAUVAIS : Logique Métier Complexe

```sql
-- ❌ PAS BON !
CASE
    WHEN age > 65 AND pathologie = 'cardiaque' AND hospitalise = true
    THEN 'RISQUE_CRITIQUE'  -- ← Règle métier = ODS !
    WHEN age > 50 AND pathologie IN ('diabete', 'hypertension')
    THEN 'RISQUE_MODERE'
    ELSE 'NORMAL'
END AS niveau_risque
```

**Correct** : Logique métier → **ODS** !

### ❌ MAUVAIS : Agrégation

```sql
-- ❌ PAS BON !
SELECT
    id_patient,
    COUNT(*) as nb_consultations,  -- ← Agrégation = ODS/DWH !
    AVG(duree) as duree_moyenne
FROM {{ source('raw', 'consultation') }}
GROUP BY id_patient
```

**Correct** : Agrégation → **DWH** ou **Datamart** !

---

## ✅ Exemple Modèle STAGING Parfait

```sql
-- stg_exemple.sql
{{
    config(
        materialized='table',
        tags=['staging', 'exemple']
    )
}}

-- 1. Lire la source
WITH source AS (
    SELECT * FROM {{ source('raw', 'ma_table') }}
),

-- 2. Nettoyer et transformer
cleaned AS (
    SELECT
        -- ✅ Business key (renommage + nettoyage)
        CAST(id AS INTEGER) AS id_element,
        
        -- ✅ Nettoyage texte
        TRIM(UPPER(nom)) AS nom,
        TRIM(prenom) AS prenom,
        
        -- ✅ Parsing dates
        TRY_CAST(date_creation AS DATE) AS date_creation,
        
        -- ✅ Cast types
        TRY_CAST(montant AS DECIMAL(10,2)) AS montant,
        
        -- ✅ Valeurs par défaut
        COALESCE(statut, 'ACTIF') AS statut,
        
        -- ✅ Calcul simple
        DATE_PART('year', CURRENT_DATE) - DATE_PART('year', date_creation) AS anciennete,
        
        -- ✅ Catégorisation simple
        CASE
            WHEN anciennete < 1 THEN 'RECENT'
            WHEN anciennete BETWEEN 1 AND 5 THEN 'MOYEN'
            ELSE 'ANCIEN'
        END AS categorie_anciennete,
        
        -- ✅ Métadonnées
        CURRENT_TIMESTAMP AS loaded_at
        
    FROM source
    -- ✅ Filtrage simple
    WHERE id IS NOT NULL
)

-- 3. Retourner les données nettoyées
SELECT * FROM cleaned
```

---

## 📊 Résumé par Modèle

| Modèle STAGING | Transformations Principales |
|----------------|----------------------------|
| `stg_patient` | ⭐ Parsing dates multi-format, Cast Poid/Taille, Calcul âge/tranche_age |
| `stg_professionnel_sante` | Nettoyage noms, Standardisation civilité |
| `stg_specialites` | ⭐ Classification 30+ catégories médicales |
| `stg_consultation` | ⭐ Calcul durée consultation (minutes) |
| `stg_hospitalisation` | ⭐ Calcul durée séjour (jours) |
| `stg_deces` | Parsing dates, Calcul âge décès, Nettoyage géographie |
| `stg_etablissement_sante` | ⭐ Gestion Corse 2A/2B, Extraction département |
| `stg_mutuelle` | Classification type (CMU/Assurance/Mutuelle) |
| `stg_adher` | Calcul statut adhésion (ACTIF/INACTIF) |
| `stg_diagnostic` | Extraction catégorie CIM-10 |
| `stg_medicaments` | Nettoyage tous champs VARCHAR |
| `stg_prescription` | Nettoyage clés étrangères |
| `stg_salle` | Extraction explicite 5 colonnes |
| `stg_laboratoire` | Extraction explicite 3 colonnes |
| `stg_etablissement_professionnel` | Nettoyage relations pro-établissement |
| `stg_etablissement_activite` | Nettoyage activités professionnels |

---

## 🎯 Prochaine Étape : ODS

Une fois le **STAGING** validé, on passe à **ODS** (Operational Data Store) où on peut :

✅ **Faire des jointures** entre tables  
✅ **Appliquer des règles métier** complexes  
✅ **Enrichir les données** avec calculs avancés  
✅ **Créer des vues métier** intégrées

Voir `dbt/models/ods/README.md`

---

**Auteur** : Équipe Big Data Groupe 3  
**Version** : 1.0  
**Date** : 2025-10-21

