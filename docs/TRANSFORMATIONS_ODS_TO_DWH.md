# 🔄 Transformations ODS → DWH

## 📋 Vue d'Ensemble

La couche **DWH** (Data Warehouse) transforme les données intégrées (ODS) en **modèle dimensionnel** pour l'analyse.

### Principe Fondamental

> **ODS = Données intégrées** (structure opérationnelle)
> 
> **DWH = Modèle dimensionnel** (architecture en étoile)
> 
> ✅ **Clés substituts** (sk_*) générées  
> ✅ **Dimensions** créées  
> ✅ **Faits** avec métriques  
> ✅ **SCD Type 2** pour historisation

---

## 🎯 Types de Transformations Appliquées

### ✅ CE QU'ON FAIT (DWH)

| Type | Description | Exemple |
|------|-------------|---------|
| **Clés substituts** | Génération sk_* séquentielles | sk_patient, sk_temps |
| **Dimensions** | Tables de référence | dim_patient, dim_temps |
| **Faits** | Tables de mesures | fait_consultation, fait_deces |
| **SCD Type 2** | Historisation des changements | dim_professionnel avec validité |
| **Dénormalisation** | Répéter infos pour performance | Nom patient dans fait |
| **Ligne "Inconnu"** | sk=-1 pour valeurs manquantes | Patient inconnu, diagnostic inconnu |
| **Agrégations simples** | COUNT, SUM dans faits | nombre_consultations |

### ❌ CE QU'ON NE FAIT PAS ENCORE

| Type | Raison | Où le faire ? |
|------|--------|---------------|
| **Agrégations complexes** | Pré-calculs pour BI | → **DATAMART** |
| **Jointures multiples** | Déjà fait dans ODS | → **ODS** |
| **Nettoyage données** | Déjà fait | → **STAGING** |

---

## 📊 Architecture Star Schema

```
         dim_temps
             |
             |
         dim_patient ────┐
                         |
                         ↓
    dim_diagnostic ─→ fait_consultation ←─ dim_professionnel
                         ↑
                         |
                    dim_mutuelle
                    
    
Chaque FAIT a :
- Des FK vers dimensions (sk_*)
- Des métriques (COUNT, SUM, AVG)
- Grain défini (1 ligne = quoi ?)
```

---

## 📊 Exemples Concrets par Dimension

### 1️⃣ `dim_patient` ⭐ (Dimension Simple)

**Source** : `ods_patient_complet`

#### Transformations Appliquées

```sql
WITH patients_source AS (
    SELECT * FROM {{ ref('ods_patient_complet') }}
),

-- ✅ DÉDOUBLONNAGE : Un patient peut avoir plusieurs mutuelles
patients_dedupliques AS (
    SELECT
        id_patient,
        nom,
        prenom,
        sexe,
        date_naissance,
        age,
        tranche_age,
        groupe_sanguin,
        poids,
        taille,
        code_postal,
        ville,
        pays,
        num_secu,
        loaded_at,
        
        -- Garder seulement la première adhésion mutuelle
        MAX(CASE WHEN a_mutuelle_active THEN 1 ELSE 0 END) AS a_mutuelle_active
        
    FROM patients_source
    GROUP BY id_patient, nom, prenom, sexe, date_naissance, age, 
             tranche_age, groupe_sanguin, poids, taille, 
             code_postal, ville, pays, num_secu, loaded_at
),

dimension_patient AS (
    SELECT
        -- ✅ CLÉ SUBSTITUT (auto-incrémentée)
        ROW_NUMBER() OVER (ORDER BY id_patient) AS sk_patient,
        
        -- ✅ BUSINESS KEY (clé naturelle)
        id_patient,
        
        -- ✅ ANONYMISATION RGPD : Hash SHA-256
        SUBSTRING(LOWER(CAST(SHA256(CAST(nom AS VARCHAR)) AS VARCHAR)), 1, 8) AS nom_anonyme,
        SUBSTRING(LOWER(CAST(SHA256(CAST(prenom AS VARCHAR)) AS VARCHAR)), 1, 8) AS prenom_anonyme,
        
        sexe,
        date_naissance,
        age,
        tranche_age,
        groupe_sanguin,
        poids,
        taille,
        code_postal,
        ville,
        pays,
        
        -- ✅ ANONYMISATION : num_secu hashé
        CASE
            WHEN num_secu IS NOT NULL THEN 
                LOWER(CAST(SHA256(CAST(num_secu AS VARCHAR)) AS VARCHAR))
            ELSE NULL
        END AS num_secu_hash,
        
        -- ✅ MÉTADONNÉES SCD Type 1 (simple)
        loaded_at AS date_chargement,
        loaded_at AS date_modification
        
    FROM patients_dedupliques
)

SELECT * FROM dimension_patient
ORDER BY sk_patient
```

**Avant (ODS)** :
```
id_patient | nom    | prenom | num_secu     | age
-----------|--------|--------|--------------|----
1          | DUPONT | Jean   | 123456789012 | 44
```

**Après (DWH)** :
```
sk_patient | id_patient | nom_anonyme | prenom_anonyme | num_secu_hash                               | age
-----------|------------|-------------|----------------|---------------------------------------------|----
1          | 1          | a3f2d1c8    | 9b4e6f2a       | 5e884898da28047151d0e56f8dc6292773603d0... | 44
```

---

### 2️⃣ `dim_professionnel` ⭐ (SCD Type 2 - Historisation)

**Source** : `ods_professionnel_complet`

#### Transformations

```sql
WITH professionnels_source AS (
    SELECT * FROM {{ ref('ods_professionnel_complet') }}
),

specialites_dim AS (
    SELECT * FROM {{ ref('dim_specialite') }}
),

dimension_professionnel AS (
    SELECT
        -- ✅ CLÉ SUBSTITUT
        ROW_NUMBER() OVER (ORDER BY p.identifiant) AS sk_professionnel,
        
        -- ✅ BUSINESS KEY (RPPS/ADELI)
        p.identifiant,
        
        -- ✅ ANONYMISATION
        p.civilite,
        SUBSTRING(LOWER(CAST(SHA256(CAST(p.nom AS VARCHAR)) AS VARCHAR)), 1, 8) AS nom_anonyme,
        SUBSTRING(LOWER(CAST(SHA256(CAST(p.prenom AS VARCHAR)) AS VARCHAR)), 1, 8) AS prenom_anonyme,
        
        -- ✅ Informations professionnelles
        p.profession,
        p.categorie_professionnelle,
        
        -- ✅ FK vers autre dimension
        s.sk_specialite AS fk_specialite,
        
        p.mode_exercice,
        
        NULL AS fk_organisation,  -- TODO: À enrichir
        
        -- ✅ SCD TYPE 2 : Gestion de l'historique
        CURRENT_DATE AS date_debut_validite,
        CAST(NULL AS DATE) AS date_fin_validite,
        TRUE AS est_actuel,  -- Version actuelle
        
        p.loaded_at AS date_chargement
        
    FROM professionnels_source p
    LEFT JOIN specialites_dim s ON p.code_specialite = s.code_specialite
)

SELECT * FROM dimension_professionnel
ORDER BY sk_professionnel
```

**Concept SCD Type 2** :

```
-- Version 1 (actuelle)
sk_professionnel | identifiant | nom_anonyme | profession | date_debut | date_fin | est_actuel
-----------------|-------------|-------------|------------|------------|----------|------------
1                | 123456      | a3f2d1c8    | Médecin    | 2020-01-01 | NULL     | TRUE

-- Si le professionnel change de spécialité → Nouvelle ligne
-- Version 2 (nouvelle)
sk_professionnel | identifiant | nom_anonyme | profession | date_debut | date_fin | est_actuel
-----------------|-------------|-------------|------------|------------|----------|------------
1                | 123456      | a3f2d1c8    | Médecin    | 2020-01-01 | 2023-06-30 | FALSE  ← Ancienne
2                | 123456      | a3f2d1c8    | Chirurgien | 2023-07-01 | NULL     | TRUE   ← Actuelle
```

---

### 3️⃣ `dim_temps` ⭐ (Dimension Générée)

**Source** : **AUCUNE** (générée programmatiquement)

#### Transformations

```sql
-- ✅ GÉNÉRATION : Créer toutes les dates de 2015 à 2030
WITH date_sequence AS (
    SELECT 
        CAST(DATE '2015-01-01' + (n * INTERVAL '1 day') AS DATE) AS date_complete
    FROM GENERATE_SERIES(0, 5844) AS t(n)  -- 16 ans * 365.25 jours
),

dimension_temps AS (
    SELECT
        -- ✅ CLÉ SUBSTITUT : Format YYYYMMDD (INT)
        CAST(TO_CHAR(date_complete, 'YYYYMMDD') AS INTEGER) AS sk_temps,
        
        -- ✅ Date complète
        date_complete,
        
        -- ✅ EXTRACTION : Composantes temporelles
        DATE_PART('year', date_complete) AS annee,
        DATE_PART('month', date_complete) AS mois,
        DATE_PART('day', date_complete) AS jour,
        DATE_PART('quarter', date_complete) AS trimestre,
        DATE_PART('week', date_complete) AS semaine,
        DATE_PART('dow', date_complete) AS jour_semaine,  -- 0=Dimanche
        
        -- ✅ LIBELLÉS
        TO_CHAR(date_complete, 'Month') AS nom_mois,
        TO_CHAR(date_complete, 'Day') AS nom_jour,
        
        -- ✅ RÈGLES MÉTIER : Jours fériés français
        CASE
            WHEN TO_CHAR(date_complete, 'MM-DD') = '01-01' THEN 'Jour de l''An'
            WHEN TO_CHAR(date_complete, 'MM-DD') = '05-01' THEN 'Fête du Travail'
            WHEN TO_CHAR(date_complete, 'MM-DD') = '05-08' THEN '8 Mai 1945'
            WHEN TO_CHAR(date_complete, 'MM-DD') = '07-14' THEN 'Fête Nationale'
            WHEN TO_CHAR(date_complete, 'MM-DD') = '08-15' THEN 'Assomption'
            WHEN TO_CHAR(date_complete, 'MM-DD') = '11-01' THEN 'Toussaint'
            WHEN TO_CHAR(date_complete, 'MM-DD') = '11-11' THEN 'Armistice 1918'
            WHEN TO_CHAR(date_complete, 'MM-DD') = '12-25' THEN 'Noël'
            ELSE NULL
        END AS jour_ferie,
        
        -- ✅ CALCULS : Indicateurs booléens
        CASE WHEN DATE_PART('dow', date_complete) IN (0, 6) THEN TRUE ELSE FALSE END AS est_weekend,
        CASE WHEN jour_ferie IS NOT NULL THEN TRUE ELSE FALSE END AS est_ferie
        
    FROM date_sequence
)

SELECT * FROM dimension_temps
ORDER BY sk_temps
```

**Résultat** :
```
sk_temps | date_complete | annee | mois | trimestre | jour_ferie  | est_weekend
---------|---------------|-------|------|-----------|-------------|------------
20150101 | 2015-01-01    | 2015  | 1    | 1         | Jour de l'An| FALSE
20150102 | 2015-01-02    | 2015  | 1    | 1         | NULL        | FALSE
20150103 | 2015-01-03    | 2015  | 1    | 1         | NULL        | TRUE
```

---

### 4️⃣ `dim_etablissement` ⭐ (Classification Automatique)

**Source** : `stg_etablissement_sante`

#### Transformations

```sql
WITH etablissements_source AS (
    SELECT * FROM {{ ref('stg_etablissement_sante') }}
),

dimension_etablissement AS (
    SELECT
        -- ✅ CLÉ SUBSTITUT
        ROW_NUMBER() OVER (ORDER BY finess_site) AS sk_etablissement,
        
        -- ✅ BUSINESS KEY
        CAST(finess_site AS VARCHAR) AS finess,
        
        raison_sociale_site AS nom_etablissement,
        
        -- ✅ CLASSIFICATION AUTOMATIQUE : Type établissement
        CASE
            WHEN UPPER(raison_sociale_site) LIKE '%CHU%' 
                 OR UPPER(raison_sociale_site) LIKE '%UNIVERSITAIRE%' 
            THEN 'CHU'
            WHEN UPPER(raison_sociale_site) LIKE '%CH %' 
                 OR UPPER(raison_sociale_site) LIKE '%HOPITAL%' 
            THEN 'Hopital Public'
            WHEN UPPER(raison_sociale_site) LIKE '%CLINIQUE%' THEN 'Clinique Privee'
            WHEN UPPER(raison_sociale_site) LIKE '%EHPAD%' THEN 'EHPAD'
            WHEN UPPER(raison_sociale_site) LIKE '%CIAS%' THEN 'Centre Communal Action Sociale'
            ELSE 'Autre etablissement'
        END AS type_etablissement,
        
        -- ✅ CLASSIFICATION : Catégorie Public/Privé
        CASE
            WHEN UPPER(raison_sociale_site) LIKE '%CHU%' 
                 OR UPPER(raison_sociale_site) LIKE '%CH %' 
            THEN 'Public'
            WHEN UPPER(raison_sociale_site) LIKE '%CLINIQUE%' THEN 'Prive'
            WHEN UPPER(raison_sociale_site) LIKE '%EHPAD%' THEN 'Medico-social'
            ELSE 'Non determine'
        END AS categorie,
        
        -- ✅ MAPPING : Région par département
        CASE
            WHEN departement IN ('75', '77', '78', '91', '92', '93', '94', '95') 
            THEN 'Ile-de-France'
            WHEN departement IN ('04', '05', '06', '13', '83', '84') 
            THEN 'Provence-Alpes-Cote d''Azur'
            -- ... autres régions
            WHEN departement IN ('2A', '2B', '20') THEN 'Corse'
            ELSE 'Non renseigne'
        END AS region,
        
        departement,
        adresse,
        code_postal,
        commune AS ville,
        
        loaded_at AS date_chargement
        
    FROM etablissements_source
)

SELECT * FROM dimension_etablissement
ORDER BY sk_etablissement
```

**Avant (STAGING)** :
```
finess_site | raison_sociale_site              | departement
------------|----------------------------------|------------
180036014   | CHNO DES QUINZE-VINGTS PARIS    | 75
```

**Après (DWH)** :
```
sk_etablissement | finess    | nom_etablissement              | type_etablissement | categorie | region
-----------------|-----------|--------------------------------|--------------------|-----------|---------------
1                | 180036014 | CHNO DES QUINZE-VINGTS PARIS  | Hopital Public     | Public    | Ile-de-France
```

---

## 📊 Exemples de Tables de Faits

### 1️⃣ `fait_consultation` ⭐ (Fait Transactionnel)

**Source** : `ods_consultation_enrichie`

#### Transformations

```sql
WITH consultations_source AS (
    SELECT * FROM {{ ref('ods_consultation_enrichie') }}
),

-- ✅ LOOKUP : Récupérer les clés substituts
dimensions AS (
    SELECT
        c.*,
        
        -- ✅ JOINTURE → Clé substitut temps
        CAST(TO_CHAR(c.date_consultation, 'YYYYMMDD') AS INTEGER) AS sk_temps,
        
        -- ✅ JOINTURE → Clé substitut patient
        dp.sk_patient,
        
        -- ✅ JOINTURE → Clé substitut professionnel
        dpr.sk_professionnel,
        
        -- ✅ JOINTURE → Clé substitut diagnostic
        dd.sk_diagnostic,
        
        -- ✅ JOINTURE → Clé substitut mutuelle
        dm.sk_mutuelle
        
    FROM consultations_source c
    LEFT JOIN {{ ref('dim_patient') }} dp 
        ON c.id_patient = dp.id_patient
    LEFT JOIN {{ ref('dim_professionnel') }} dpr 
        ON c.id_professionnel = dpr.identifiant 
        AND dpr.est_actuel = TRUE  -- ✅ SCD Type 2 : version actuelle
    LEFT JOIN {{ ref('dim_diagnostic') }} dd 
        ON c.code_diagnostic = dd.code_diagnostic
    LEFT JOIN {{ ref('dim_mutuelle') }} dm 
        ON c.id_mut = dm.id_mut
),

fait_consultation AS (
    SELECT
        -- ✅ CLÉ PRIMAIRE (business key)
        num_consultation AS id_consultation,
        
        -- ✅ CLÉS ÉTRANGÈRES (vers dimensions)
        COALESCE(sk_temps, -1) AS sk_temps,  -- -1 = Inconnu
        COALESCE(sk_patient, -1) AS sk_patient,
        COALESCE(sk_professionnel, -1) AS sk_professionnel,
        COALESCE(sk_diagnostic, -1) AS sk_diagnostic,
        COALESCE(sk_mutuelle, -1) AS sk_mutuelle,
        
        -- ✅ MÉTRIQUES (mesures numériques)
        1 AS nombre_consultations,  -- Compteur
        duree_consultation_minutes AS duree_consultation,
        
        -- ✅ INFORMATIONS DÉGÉNÉRÉES (contexte)
        heure_debut,
        heure_fin,
        motif,
        
        -- ✅ MÉTADONNÉES
        loaded_at AS date_chargement
        
    FROM dimensions
)

SELECT * FROM fait_consultation
```

**Grain** : **1 ligne = 1 consultation**

**Avant (ODS)** :
```
num_consultation | date_consultation | id_patient | id_professionnel | duree_consultation_minutes
-----------------|-------------------|------------|------------------|---------------------------
1001             | 2023-05-15        | 1          | 123456           | 25
```

**Après (DWH)** :
```
id_consultation | sk_temps | sk_patient | sk_professionnel | sk_diagnostic | nombre_consultations | duree_consultation
----------------|----------|------------|------------------|---------------|---------------------|-------------------
1001            | 20230515 | 1          | 1                | 42            | 1                   | 25
```

---

### 2️⃣ `fait_deces` ⭐ (Fait de Grand Volume)

**Source** : `ods_deces_enrichi`

#### Transformations

```sql
WITH deces_source AS (
    SELECT * FROM {{ ref('ods_deces_enrichi') }}
),

dimensions AS (
    SELECT
        d.*,
        
        -- ✅ Clés substituts
        CAST(TO_CHAR(d.date_deces, 'YYYYMMDD') AS INTEGER) AS sk_temps,
        
        -- ✅ LOOKUP : Patient (peut être NULL si pas matché)
        dp.sk_patient,
        
        -- ✅ LOOKUP : Localisation
        dl.sk_localisation
        
    FROM deces_source d
    LEFT JOIN {{ ref('dim_patient') }} dp ON d.id_patient_matche = dp.id_patient
    LEFT JOIN {{ ref('dim_localisation') }} dl 
        ON d.code_postal_deces = dl.code_postal 
        AND d.commune_deces = dl.ville
),

fait_deces AS (
    SELECT
        -- ✅ CLÉ PRIMAIRE
        ROW_NUMBER() OVER (ORDER BY date_deces) AS id_deces,
        
        -- ✅ CLÉS ÉTRANGÈRES
        COALESCE(sk_temps, -1) AS sk_temps,
        COALESCE(sk_patient, -1) AS sk_patient,  -- Souvent -1 (pas matché)
        COALESCE(sk_localisation, -1) AS sk_localisation,
        
        -- ✅ MÉTRIQUES
        1 AS nombre_deces,
        age_deces,
        
        -- ✅ INFORMATIONS DÉGÉNÉRÉES
        sexe_deces,  -- Peut différer du patient si pas matché
        date_naissance_deces,
        
        date_chargement
        
    FROM dimensions
)

SELECT * FROM fait_deces
```

**Grain** : **1 ligne = 1 décès**

**Volume** : 25M+ lignes !

---

## 📊 Transformations Spéciales

### 🔑 Génération Clés Substituts

```sql
-- ✅ AUTO-INCREMENT avec ROW_NUMBER
ROW_NUMBER() OVER (ORDER BY business_key) AS sk_dimension

-- Exemples
ROW_NUMBER() OVER (ORDER BY id_patient) AS sk_patient
ROW_NUMBER() OVER (ORDER BY finess) AS sk_etablissement

-- ✅ Clé composée pour dim_temps
CAST(TO_CHAR(date_complete, 'YYYYMMDD') AS INTEGER) AS sk_temps
-- 2023-05-15 → 20230515
```

### 🏷️ Ligne "Inconnu" (sk = -1)

```sql
-- ✅ Créer ligne "Inconnu" pour chaque dimension
INSERT INTO dim_patient VALUES (
    -1,                    -- sk_patient
    'INCONNU',             -- id_patient
    'INCONNU',             -- nom_anonyme
    'I',                   -- sexe
    NULL,                  -- date_naissance
    -- ... autres colonnes avec valeurs par défaut
)

-- ✅ Utiliser dans les faits
COALESCE(sk_patient, -1) AS sk_patient  -- Si NULL → -1 (Inconnu)
```

### 🔄 SCD Type 2 (Historisation)

```sql
-- ✅ Structure SCD Type 2
CREATE TABLE dim_professionnel (
    sk_professionnel INTEGER,          -- Clé substitut (unique)
    identifiant VARCHAR,                -- Business key (peut se répéter)
    nom_anonyme VARCHAR,
    profession VARCHAR,
    
    -- ✅ Colonnes SCD Type 2
    date_debut_validite DATE,          -- Début période validité
    date_fin_validite DATE,            -- Fin période (NULL si actuel)
    est_actuel BOOLEAN,                -- TRUE si version actuelle
    
    date_chargement TIMESTAMP
)

-- ✅ Requête pour version actuelle
SELECT *
FROM dim_professionnel
WHERE est_actuel = TRUE

-- ✅ Requête historique (version à une date)
SELECT *
FROM dim_professionnel
WHERE identifiant = '123456'
  AND date_debut_validite <= '2022-01-01'
  AND (date_fin_validite >= '2022-01-01' OR date_fin_validite IS NULL)
```

---

## 📋 Checklist Qualité DWH

### ✅ Chaque DIMENSION doit avoir :

- [ ] **Clé substitut** (sk_*) auto-incrémentée
- [ ] **Business key** (clé naturelle)
- [ ] **Ligne "Inconnu"** (sk = -1)
- [ ] **Pas de NULL** dans colonnes importantes
- [ ] **Anonymisation** (si données personnelles)
- [ ] **SCD implémenté** (si historisation nécessaire)
- [ ] **Tests d'unicité** sur sk_*

### ✅ Chaque FAIT doit avoir :

- [ ] **Grain clairement défini** (1 ligne = quoi ?)
- [ ] **FK vers dimensions** (sk_*)
- [ ] **COALESCE vers -1** pour FK NULL
- [ ] **Métriques additives** (SUM possible)
- [ ] **Pas d'informations qui changent** (utiliser FK)
- [ ] **Date/heure dans dim_temps** (pas directement dans fait)

---

## 🚫 Anti-Patterns (À Éviter)

### ❌ MAUVAIS : Dimensions dénormalisées

```sql
-- ❌ PAS BON !
CREATE TABLE fait_consultation (
    id_consultation INTEGER,
    patient_nom VARCHAR,  -- ← Devrait être dans dim_patient !
    patient_age INTEGER,  -- ← Devrait être dans dim_patient !
    ...
)
```

**Correct** : Mettre dans dimension + FK

### ❌ MAUVAIS : Pas de clé substitut

```sql
-- ❌ PAS BON !
CREATE TABLE dim_patient (
    id_patient INTEGER PRIMARY KEY,  -- ← Business key comme PK !
    nom VARCHAR
)
```

**Correct** : Clé substitut séparée

```sql
-- ✅ BON !
CREATE TABLE dim_patient (
    sk_patient INTEGER PRIMARY KEY,  -- ← Clé substitut
    id_patient INTEGER,              -- ← Business key
    nom VARCHAR
)
```

---

## 📊 Résumé Transformations ODS → DWH

| Élément DWH | Source ODS | Transformations Principales |
|-------------|------------|----------------------------|
| `dim_patient` | ods_patient_complet | ⭐ Clé substitut, Anonymisation SHA-256, Dédoublonnage |
| `dim_professionnel` | ods_professionnel_complet | ⭐ Clé substitut, SCD Type 2, Anonymisation |
| `dim_temps` | AUCUNE (générée) | ⭐ Génération dates 2015-2030, Jours fériés FR |
| `dim_etablissement` | stg_etablissement_sante | ⭐ Classification auto (CHU/Hôpital/Clinique), Mapping région |
| `dim_diagnostic` | stg_diagnostic | ⭐ Extraction chapitre CIM-10, Catégorisation |
| `dim_mutuelle` | stg_mutuelle | ⭐ Classification type (CMU/Assurance/Mutuelle) |
| `dim_localisation` | ods_localisation_consolidee | ⭐ Consolidation multi-sources, Calcul département/région |
| `dim_specialite` | stg_specialites | ⭐ Catégorisation 30+ spécialités médicales |
| `fait_consultation` | ods_consultation_enrichie | ⭐ Lookup clés substituts, Métriques (compteur + durée) |
| `fait_hospitalisation` | ods_hospitalisation_enrichie | ⭐ Lookup SK, Métriques (nb_hospitalisations + jours) |
| `fait_deces` | ods_deces_enrichi | ⭐ Lookup SK (25M lignes), Métrique (compteur) |
| `fait_satisfaction` | ods_satisfaction_unifie | ⭐ Scores satisfaction, Taux recommandation |
| `fait_qualite_soins` | ods_qualite_soins_unifie | ⭐ Indicateurs IPAQSS, Ratios qualité |

---

## 🎯 Prochaine Étape : DATAMART

Une fois le **DWH** validé, on passe au **DATAMART** où on va :

✅ **Pré-calculer agrégations** pour performance BI  
✅ **Dénormaliser pour Power BI** (vues plates)  
✅ **Créer indicateurs métier** (KPI)  
✅ **Optimiser requêtes** fréquentes

Voir `docs/TRANSFORMATIONS_DWH_TO_DATAMART.md`

---

**Auteur** : Équipe Big Data Groupe 3  
**Version** : 1.0  
**Date** : 2025-10-21

