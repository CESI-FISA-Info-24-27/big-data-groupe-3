# 🔄 Transformations STAGING → ODS

## 📋 Vue d'Ensemble

La couche **ODS** (Operational Data Store) est la **couche d'intégration** où on combine et enrichit les données du staging.

### Principe Fondamental

> **STAGING = Nettoyage simple** (1 table → 1 table)
> 
> **ODS = Intégration** (N tables → 1 vue métier)
> 
> ✅ **Jointures autorisées** entre tables  
> ✅ **Règles métier** appliquées  
> ✅ **Enrichissements** métier

---

## 🎯 Types de Transformations Appliquées

### ✅ CE QU'ON FAIT (Autorisé dans ODS)

| Type | Description | Exemple |
|------|-------------|---------|
| **Jointures** | Combiner plusieurs sources | Patient + Mutuelle |
| **Règles métier** | Logique business | Statut actif/inactif |
| **Calculs dérivés** | Calculs complexes | Age au moment consultation |
| **Agrégations** | GROUP BY, COUNT, SUM | Nombre d'établissements par pro |
| **Classifications** | CASE WHEN métier | Catégorie patient (pédiatrie/adulte/gériatrie) |
| **Enrichissements** | Ajouter contexte métier | Libellés, descriptions |
| **Dédoublonnage** | Window functions avancées | Garder dernière version |

### ❌ CE QU'ON NE FAIT PAS ENCORE

| Type | Raison | Où le faire ? |
|------|--------|---------------|
| **Clés substituts (sk_*)** | Modèle dimensionnel | → **DWH** |
| **Dimensions/Faits** | Architecture en étoile | → **DWH** |
| **SCD Type 2** | Historisation | → **DWH** |
| **Agrégations finales** | Pré-calculs pour BI | → **DATAMART** |

---

## 📊 Exemples Concrets par Modèle

### 1️⃣ `ods_patient_complet` ⭐ (Jointures Multiples)

**Sources** : `stg_patient` + `stg_adher` + `stg_mutuelle`

#### Transformations Appliquées

```sql
WITH patients AS (
    SELECT * FROM {{ ref('stg_patient') }}
),

adhesions AS (
    SELECT * FROM {{ ref('stg_adher') }}
),

mutuelles AS (
    SELECT * FROM {{ ref('stg_mutuelle') }}
),

patient_mutuelle AS (
    SELECT
        p.*,  -- Toutes les colonnes patient
        
        -- ✅ JOINTURES : Informations mutuelle
        m.id_mut,
        m.nom_mutuelle,
        m.type_mutuelle,       -- CMU/Assurance/Mutuelle
        a.statut_adhesion,     -- ACTIF/INACTIF
        
        -- ✅ RÈGLE MÉTIER : Calcul mutuelle active
        CASE
            WHEN m.id_mut IS NOT NULL 
                 AND a.statut_adhesion = 'ACTIF' 
            THEN TRUE
            ELSE FALSE
        END AS a_mutuelle_active
        
    FROM patients p
    LEFT JOIN adhesions a ON p.id_patient = a.id_patient
    LEFT JOIN mutuelles m ON a.id_mut = m.id_mut
)

SELECT * FROM patient_mutuelle
```

**Avant (STAGING)** :
```
-- stg_patient
id_patient | nom    | prenom | age | ville
-----------|--------|--------|-----|-------
1          | DUPONT | Jean   | 44  | Paris

-- stg_adher
id_patient | id_mut | statut_adhesion
-----------|--------|----------------
1          | 12     | ACTIF

-- stg_mutuelle
id_mut | nom_mutuelle  | type_mutuelle
-------|---------------|---------------
12     | Mutuelle AXA  | Mutuelle
```

**Après (ODS)** :
```
id_patient | nom    | prenom | age | ville | nom_mutuelle | type_mutuelle | a_mutuelle_active
-----------|--------|--------|-----|-------|--------------|---------------|------------------
1          | DUPONT | Jean   | 44  | Paris | Mutuelle AXA | Mutuelle      | TRUE
```

---

### 2️⃣ `ods_professionnel_complet` ⭐ (Agrégations + Enrichissement)

**Sources** : `stg_professionnel_sante` + `stg_etablissement_professionnel` + `stg_specialites`

#### Transformations

```sql
WITH professionnels AS (
    SELECT * FROM {{ ref('stg_professionnel_sante') }}
),

etablissements_pro AS (
    SELECT * FROM {{ ref('stg_etablissement_professionnel') }}
),

specialites AS (
    SELECT * FROM {{ ref('stg_specialites') }}
),

-- ✅ AGRÉGATION : Grouper par professionnel
professionnel_avec_etablissement AS (
    SELECT
        p.*,
        
        -- ✅ AGRÉGATION : Informations établissement
        MAX(ep.commune) AS commune_exercice,
        MAX(ep.specialite) AS specialite_exercice_etab,
        COUNT(DISTINCT ep.commune) AS nb_etablissements,
        
    FROM professionnels p
    LEFT JOIN etablissements_pro ep ON p.identifiant = ep.identifiant
    GROUP BY p.identifiant, p.civilite, p.nom, p.prenom, 
             p.profession, p.categorie_professionnelle, 
             p.code_specialite, p.loaded_at
),

-- ✅ ENRICHISSEMENT : Ajouter infos spécialité
professionnel_enrichi AS (
    SELECT
        p.*,
        
        -- ✅ JOINTURE : Informations spécialité détaillées
        s.fonction AS specialite_fonction,
        s.specialite AS specialite_libelle,
        s.categorie AS specialite_categorie,
        
        -- ✅ RÈGLE MÉTIER : Mode d'exercice
        CASE
            WHEN p.categorie_professionnelle LIKE '%Libéral%' THEN 'Libéral'
            WHEN p.categorie_professionnelle LIKE '%Salarié%' THEN 'Salarié'
            WHEN p.categorie_professionnelle LIKE '%Mixte%' THEN 'Mixte'
            ELSE 'Non renseigné'
        END AS mode_exercice
        
    FROM professionnel_avec_etablissement p
    LEFT JOIN specialites s ON p.code_specialite = s.code_specialite
)

SELECT * FROM professionnel_enrichi
```

**Avant (3 tables STAGING)** :
```
-- stg_professionnel_sante
identifiant | nom    | code_specialite
------------|--------|----------------
123456      | MARTIN | SM54

-- stg_etablissement_professionnel
identifiant | commune | specialite
------------|---------|------------
123456      | Paris   | Cardiologue
123456      | Lyon    | Cardiologue

-- stg_specialites
code_specialite | fonction              | categorie
----------------|-----------------------|--------------------
SM54            | Médecin spécialiste   | Medecine specialisee
```

**Après (1 table ODS)** :
```
identifiant | nom    | commune_exercice | nb_etablissements | specialite_fonction | mode_exercice
------------|--------|------------------|-------------------|---------------------|---------------
123456      | MARTIN | Paris            | 2                 | Médecin spécialiste | Libéral
```

---

### 3️⃣ `ods_consultation_enrichie` ⭐ (Jointures Multiples + Classifications)

**Sources** : `stg_consultation` + `ods_patient_complet` + `ods_professionnel_complet` + `stg_diagnostic`

#### Transformations

```sql
WITH consultations AS (
    SELECT * FROM {{ ref('stg_consultation') }}
),

patients AS (
    SELECT * FROM {{ ref('ods_patient_complet') }}  -- Déjà enrichi !
),

professionnels AS (
    SELECT * FROM {{ ref('ods_professionnel_complet') }}  -- Déjà enrichi !
),

diagnostics AS (
    SELECT * FROM {{ ref('stg_diagnostic') }}
),

consultation_complete AS (
    SELECT
        -- ✅ Identifiants consultation
        c.num_consultation,
        c.date_consultation,
        c.heure_debut,
        c.heure_fin,
        c.duree_consultation_minutes,
        c.motif,
        
        -- ✅ Clés pour DWH
        c.id_patient,
        c.id_professionnel,
        c.code_diagnostic,
        c.id_mut,
        
        -- ✅ JOINTURE : Informations patient enrichies
        p.nom AS patient_nom,
        p.prenom AS patient_prenom,
        p.sexe AS patient_sexe,
        p.age AS patient_age,
        p.tranche_age AS patient_tranche_age,
        p.ville AS patient_ville,
        p.nom_mutuelle AS patient_mutuelle,
        p.a_mutuelle_active AS patient_a_mutuelle,
        
        -- ✅ JOINTURE : Informations professionnel
        pr.nom AS professionnel_nom,
        pr.prenom AS professionnel_prenom,
        pr.profession AS professionnel_profession,
        pr.code_specialite AS professionnel_code_specialite,
        pr.mode_exercice AS professionnel_mode_exercice,
        
        -- ✅ JOINTURE : Informations diagnostic
        d.libelle_diagnostic,
        d.categorie_cim10,
        
        -- ✅ CLASSIFICATION MÉTIER : Catégorie patient
        CASE
            WHEN p.age < 18 THEN 'PEDIATRIE'
            WHEN p.age > 65 THEN 'GERIATRIE'
            ELSE 'ADULTE'
        END AS categorie_patient,
        
        -- ✅ CLASSIFICATION MÉTIER : Durée consultation
        CASE
            WHEN c.duree_consultation_minutes < 15 THEN 'COURTE'
            WHEN c.duree_consultation_minutes BETWEEN 15 AND 30 THEN 'NORMALE'
            WHEN c.duree_consultation_minutes > 30 THEN 'LONGUE'
            ELSE 'NON_RENSEIGNEE'
        END AS duree_categorie,
        
        c.loaded_at
        
    FROM consultations c
    INNER JOIN patients p ON c.id_patient = p.id_patient
    LEFT JOIN professionnels pr ON c.id_professionnel = pr.identifiant
    LEFT JOIN diagnostics d ON c.code_diagnostic = d.code_diagnostic
)

SELECT * FROM consultation_complete
```

**Avant (4 tables)** :
```
-- stg_consultation
num_consultation | id_patient | id_professionnel | duree_consultation_minutes
-----------------|------------|------------------|---------------------------
1001             | 1          | 123456           | 25

-- ods_patient_complet
id_patient | nom    | age | tranche_age | mutuelle
-----------|--------|-----|-------------|----------
1          | DUPONT | 44  | 31-50       | AXA

-- ods_professionnel_complet
identifiant | nom    | profession       | mode_exercice
------------|--------|------------------|---------------
123456      | MARTIN | Médecin          | Libéral

-- stg_diagnostic
code_diagnostic | libelle_diagnostic
----------------|-------------------
J06.9           | Infection respiratoire
```

**Après (1 table ODS enrichie)** :
```
num_consultation | patient_nom | patient_age | categorie_patient | professionnel_nom | mode_exercice | duree_categorie
-----------------|-------------|-------------|-------------------|-------------------|---------------|----------------
1001             | DUPONT      | 44          | ADULTE            | MARTIN            | Libéral       | NORMALE
```

---

### 4️⃣ `ods_hospitalisation_enrichie` (Calculs Métier)

**Sources** : `stg_hospitalisation` + `ods_patient_complet` + `stg_diagnostic` + `stg_etablissement_sante`

#### Transformations

```sql
SELECT
    h.num_hospitalisation,
    h.date_admission,
    h.date_sortie,
    h.jour_hospitalisation,  -- Calculé dans STAGING
    
    -- ✅ JOINTURES
    p.nom AS patient_nom,
    p.age AS patient_age,
    e.nom_etablissement,
    e.region AS region_etablissement,
    d.libelle_diagnostic,
    
    -- ✅ CLASSIFICATION MÉTIER : Durée séjour
    CASE
        WHEN h.jour_hospitalisation < 3 THEN 'COURT_SEJOUR'
        WHEN h.jour_hospitalisation BETWEEN 3 AND 7 THEN 'MOYEN_SEJOUR'
        WHEN h.jour_hospitalisation > 7 THEN 'LONG_SEJOUR'
        ELSE 'NON_RENSEIGNE'
    END AS categorie_sejour,
    
    -- ✅ RÈGLE MÉTIER : Hospitalisation prolongée (> DMS)
    CASE
        WHEN h.jour_hospitalisation > 7 THEN TRUE
        ELSE FALSE
    END AS est_sejour_prolonge
    
FROM {{ ref('stg_hospitalisation') }} h
LEFT JOIN {{ ref('ods_patient_complet') }} p ON h.id_patient = p.id_patient
LEFT JOIN {{ ref('stg_etablissement_sante') }} e ON h.finess = e.finess_site
LEFT JOIN {{ ref('stg_diagnostic') }} d ON h.code_diagnostic = d.code_diagnostic
```

---

### 5️⃣ `ods_localisation_consolidee` (Consolidation Multi-Sources)

**Sources** : `stg_patient` + `stg_etablissement_sante` + `stg_deces`

#### Transformations

```sql
-- ✅ CONSOLIDATION : Toutes les localisations du système

-- Localisations depuis patients
WITH loc_patients AS (
    SELECT DISTINCT
        code_postal,
        ville,
        'Patient' AS source_donnee
    FROM {{ ref('stg_patient') }}
    WHERE code_postal IS NOT NULL
),

-- Localisations depuis établissements
loc_etablissements AS (
    SELECT DISTINCT
        code_postal,
        commune AS ville,
        departement,
        'Etablissement' AS source_donnee
    FROM {{ ref('stg_etablissement_sante') }}
    WHERE code_postal IS NOT NULL
),

-- Localisations depuis décès
loc_deces AS (
    SELECT DISTINCT
        code_postal_deces AS code_postal,
        commune_deces AS ville,
        departement_deces AS departement,
        'Deces' AS source_donnee
    FROM {{ ref('stg_deces') }}
    WHERE code_postal_deces IS NOT NULL
),

-- ✅ UNION : Consolider toutes les sources
toutes_localisations AS (
    SELECT * FROM loc_patients
    UNION
    SELECT * FROM loc_etablissements
    UNION
    SELECT * FROM loc_deces
),

-- ✅ DÉDOUBLONNAGE + ENRICHISSEMENT
localisation_unique AS (
    SELECT
        code_postal,
        ville,
        
        -- ✅ CALCUL : Département
        CASE
            WHEN SUBSTRING(code_postal, 1, 2) = '20' THEN
                CASE
                    WHEN TRY_CAST(SUBSTRING(code_postal, 3, 1) AS INTEGER) < 2 
                    THEN '2A'
                    ELSE '2B'
                END
            ELSE SUBSTRING(code_postal, 1, 2)
        END AS departement,
        
        -- ✅ ENRICHISSEMENT : Région
        CASE
            WHEN SUBSTRING(code_postal, 1, 2) IN ('75', '77', '78', '91', '92', '93', '94', '95') 
            THEN 'Ile-de-France'
            -- ... autres régions
            ELSE 'Non renseigne'
        END AS region,
        
        -- Garder la source (pour traçabilité)
        MAX(source_donnee) AS source_donnee,
        
    FROM toutes_localisations
    GROUP BY code_postal, ville
)

SELECT * FROM localisation_unique
```

---

## 📋 Transformations par Type

### 🔗 Jointures (Principal Ajout dans ODS)

```sql
-- Simple LEFT JOIN
SELECT
    p.*,
    m.nom_mutuelle
FROM {{ ref('stg_patient') }} p
LEFT JOIN {{ ref('stg_mutuelle') }} m 
    ON p.id_mut = m.id_mut

-- Multiple JOINs
SELECT
    c.*,
    p.nom AS patient_nom,
    pr.nom AS professionnel_nom,
    d.libelle_diagnostic
FROM {{ ref('stg_consultation') }} c
INNER JOIN {{ ref('stg_patient') }} p ON c.id_patient = p.id_patient
LEFT JOIN {{ ref('stg_professionnel_sante') }} pr ON c.id_professionnel = pr.identifiant
LEFT JOIN {{ ref('stg_diagnostic') }} d ON c.code_diagnostic = d.code_diagnostic
```

### 🎯 Règles Métier

```sql
-- Statut actif/inactif
CASE
    WHEN date_fin IS NULL OR date_fin > CURRENT_DATE 
    THEN 'ACTIF'
    ELSE 'INACTIF'
END AS statut

-- Classification âge
CASE
    WHEN age < 18 THEN 'PEDIATRIE'
    WHEN age > 65 THEN 'GERIATRIE'
    ELSE 'ADULTE'
END AS categorie_patient

-- Seuils métier
CASE
    WHEN valeur > seuil_critique THEN 'ALERTE'
    WHEN valeur > seuil_moyen THEN 'ATTENTION'
    ELSE 'NORMAL'
END AS niveau_alerte
```

### 📊 Agrégations

```sql
-- Compter
COUNT(DISTINCT etablissement_id) AS nb_etablissements

-- Calculer moyenne
AVG(duree_consultation) AS duree_moyenne

-- Prendre max/min
MAX(date_modification) AS derniere_modification

-- Grouper
SELECT
    professionnel_id,
    COUNT(*) AS nb_consultations,
    AVG(duree) AS duree_moyenne
FROM consultations
GROUP BY professionnel_id
```

### 🏷️ Classifications Métier

```sql
-- Classification simple
CASE
    WHEN condition1 THEN 'CATEGORIE_A'
    WHEN condition2 THEN 'CATEGORIE_B'
    ELSE 'CATEGORIE_C'
END

-- Classification multiple critères
CASE
    WHEN age > 65 AND pathologie = 'cardiaque' THEN 'RISQUE_ELEVE'
    WHEN age > 50 AND pathologie IN ('diabete', 'hypertension') THEN 'RISQUE_MOYEN'
    ELSE 'RISQUE_FAIBLE'
END AS niveau_risque
```

### 🔄 Dédoublonnage Avancé

```sql
-- Garder la dernière version
WITH ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY id_patient 
            ORDER BY date_modification DESC
        ) AS rn
    FROM patients_historique
)
SELECT * FROM ranked WHERE rn = 1

-- Garder la meilleure qualité
SELECT
    id_patient,
    MAX(CASE WHEN source = 'system_A' THEN nom END) AS nom,
    MAX(CASE WHEN source = 'system_B' THEN email END) AS email
FROM patients_multi_sources
GROUP BY id_patient
```

---

## 📊 Résumé par Modèle ODS

| Modèle ODS | Sources | Transformations Principales |
|------------|---------|----------------------------|
| `ods_patient_complet` | stg_patient + stg_adher + stg_mutuelle | ⭐ Jointures, Règle métier mutuelle active |
| `ods_professionnel_complet` | stg_professionnel_sante + stg_etablissement_professionnel + stg_specialites | ⭐ Agrégation nb_établissements, Enrichissement spécialité |
| `ods_consultation_enrichie` | stg_consultation + ods_patient + ods_professionnel + stg_diagnostic | ⭐ Jointures multiples, Classifications métier (pédiatrie/adulte/gériatrie) |
| `ods_hospitalisation_enrichie` | stg_hospitalisation + ods_patient + stg_etablissement + stg_diagnostic | ⭐ Classification durée séjour, Règle séjour prolongé |
| `ods_deces_enrichi` | stg_deces + ods_patient | ⭐ Matching fuzzy, Enrichissement patient |
| `ods_localisation_consolidee` | stg_patient + stg_etablissement + stg_deces | ⭐ Consolidation multi-sources, Calcul région/département |
| `ods_prescription_enrichie` | stg_prescription + stg_medicaments + stg_laboratoire | ⭐ Enrichissement médicament, Informations laboratoire |
| `ods_satisfaction_unifie` | 31 tables satisfaction CSV | ⭐ UNION ALL multi-années, Normalisation scores |
| `ods_qualite_soins_unifie` | Tables qualité/IPAQSS | ⭐ Consolidation indicateurs, Calculs ratios |

---

## 📋 Checklist Qualité ODS

### ✅ Chaque modèle doit avoir :

- [ ] **Jointures logiques** avec bonnes clés
- [ ] **Gestion des NULL** (LEFT vs INNER JOIN)
- [ ] **Règles métier** documentées
- [ ] **Pas de doublons** non voulus
- [ ] **CTE claires** pour chaque source
- [ ] **Nomenclature cohérente** (préfixes patient_, professionnel_)
- [ ] **Tests configurés** (unicité, non-nullité)
- [ ] **Performance** (éviter cross-joins)

---

## 🚫 Anti-Patterns (À Éviter)

### ❌ MAUVAIS : Créer dimensions dans ODS

```sql
-- ❌ PAS BON ! Les sk_* c'est pour le DWH
SELECT
    ROW_NUMBER() OVER (ORDER BY id) AS sk_patient,  -- ← DWH !
    id_patient,
    nom
FROM patients
```

**Correct** : Les clés substituts → **DWH** uniquement

### ❌ MAUVAIS : Agrégations finales

```sql
-- ❌ PAS BON ! Les agrégations finales c'est pour le DATAMART
SELECT
    region,
    COUNT(*) AS nb_consultations_total,  -- ← DATAMART !
    AVG(duree) AS duree_moyenne_region
FROM consultations
GROUP BY region
```

**Correct** : Agrégations finales → **DATAMART**

---

## ✅ Exemple Modèle ODS Parfait

```sql
-- ods_exemple.sql
{{
    config(
        materialized='table',
        tags=['ods', 'core', 'exemple']
    )
}}

-- 1. Importer les sources
WITH source_a AS (
    SELECT * FROM {{ ref('stg_table_a') }}
),

source_b AS (
    SELECT * FROM {{ ref('stg_table_b') }}
),

source_c AS (
    SELECT * FROM {{ ref('stg_table_c') }}
),

-- 2. Jointures et enrichissements
enrichi AS (
    SELECT
        -- ✅ Clés business
        a.id_element,
        
        -- ✅ Informations source A
        a.nom,
        a.date_creation,
        
        -- ✅ JOINTURE : Informations source B
        b.categorie,
        b.statut,
        
        -- ✅ JOINTURE : Informations source C
        c.code_postal,
        c.ville,
        
        -- ✅ RÈGLE MÉTIER : Calcul statut actif
        CASE
            WHEN b.date_fin IS NULL OR b.date_fin > CURRENT_DATE 
            THEN TRUE
            ELSE FALSE
        END AS est_actif,
        
        -- ✅ CLASSIFICATION MÉTIER
        CASE
            WHEN a.valeur > 100 THEN 'HAUT'
            WHEN a.valeur > 50 THEN 'MOYEN'
            ELSE 'BAS'
        END AS niveau,
        
        -- ✅ Métadonnées
        a.loaded_at
        
    FROM source_a a
    LEFT JOIN source_b b ON a.id_b = b.id_b
    LEFT JOIN source_c c ON a.id_c = c.id_c
    WHERE a.id_element IS NOT NULL
)

-- 3. Retourner les données enrichies
SELECT * FROM enrichi
```

---

## 🔄 Workflow STAGING → ODS

```
STAGING (tables nettoyées)
    ↓
    ├─ stg_patient ──┐
    ├─ stg_mutuelle ─┼─→ ods_patient_complet (JOIN + règles métier)
    └─ stg_adher ────┘
    
    ├─ stg_professionnel ──┐
    ├─ stg_etablissement ──┼─→ ods_professionnel_complet (JOIN + agrégations)
    └─ stg_specialites ────┘
    
    ├─ stg_consultation ─┐
    ├─ ods_patient ──────┼─→ ods_consultation_enrichie (JOIN multiples + classifications)
    ├─ ods_professionnel ┤
    └─ stg_diagnostic ───┘
```

---

## 🎯 Prochaine Étape : DWH

Une fois l'**ODS** validé, on passe au **DWH** (Data Warehouse) où on va :

✅ **Créer les dimensions** avec clés substituts (sk_*)  
✅ **Créer les faits** avec métriques  
✅ **Implémenter SCD Type 2** pour historisation  
✅ **Architecture en étoile** (star schema)

Voir `docs/TRANSFORMATIONS_ODS_TO_DWH.md`

---

**Auteur** : Équipe Big Data Groupe 3  
**Version** : 1.0  
**Date** : 2025-10-21

