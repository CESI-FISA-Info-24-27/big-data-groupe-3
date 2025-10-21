# 🔄 Transformations DWH → DATAMART

## 📋 Vue d'Ensemble

La couche **DATAMART** transforme le modèle dimensionnel (DWH) en **vues agrégées optimisées** pour Power BI.

### Principe Fondamental

> **DWH = Modèle dimensionnel** (star schema, granularité fine)
> 
> **DATAMART = Vues agrégées** (pré-calculs pour performance BI)
> 
> ✅ **Agrégations pré-calculées**  
> ✅ **Dénormalisation** pour performance  
> ✅ **Indicateurs métier** (KPI)  
> ✅ **Optimisation requêtes** BI

---

## 🎯 Types de Transformations Appliquées

### ✅ CE QU'ON FAIT (DATAMART)

| Type | Description | Exemple |
|------|-------------|---------|
| **Agrégations complexes** | GROUP BY multiples | Consultations par région/mois/spécialité |
| **Pré-calculs** | SUM, AVG, COUNT pré-calculés | Total consultations par période |
| **Dénormalisation** | Répéter infos dimensions | Nom établissement dans table agrégée |
| **Indicateurs métier** | KPI métier | Taux satisfaction, DMS |
| **Jointures multiples** | Réunir plusieurs faits | Consultations + Hospitalisations |
| **Window functions** | RANK, PARTITION BY | Top 10 spécialités |
| **Vues plates** | Tout en une table | Faciliter Power BI |

### ❌ CE QU'ON NE FAIT PAS

| Type | Raison | Où c'était fait ? |
|------|--------|-------------------|
| **Nettoyage données** | Déjà fait | → **STAGING** |
| **Jointures basiques** | Déjà fait | → **ODS** |
| **Création dimensions** | Déjà fait | → **DWH** |

---

## 📊 Architecture DATAMART

```
           DWH (star schema)
                 |
                 ↓
    ┌────────────────────────────┐
    │     DATAMART (agrégé)      │
    └────────────────────────────┘
                 |
     ┌───────────┴───────────┐
     ↓                       ↓
dm_consultations_agregees    dm_hospitalisations_agregees
     ↓                       ↓
dm_analyse_territoriale      (optimisé Power BI)
```

---

## 📊 Exemples Concrets par Datamart

### 1️⃣ `dm_consultations_agregees` ⭐ (Agrégations Multiples)

**Sources** : `fait_consultation` + dimensions

**Grain** : **1 ligne = 1 combinaison (établissement, diagnostic, période, professionnel)**

#### Transformations Appliquées

```sql
WITH consultations_base AS (
    SELECT 
        fc.sk_temps,
        fc.sk_diagnostic,
        fc.sk_professionnel,
        fc.sk_patient,
        fc.sk_mutuelle,
        
        -- ✅ DÉNORMALISATION : Répéter infos dimensions
        dt.date_complete,
        dt.annee,
        dt.trimestre,
        dt.mois,
        
        dd.code_diagnostic,
        dd.libelle_diagnostic,
        dd.chapitre_cim10,
        dd.categorie_cim10,
        
        dp.nom_anonyme AS nom_professionnel,
        dp.prenom_anonyme AS prenom_professionnel,
        ds.specialite,
        ds.fonction,
        
        dp2.sexe,
        dp2.tranche_age,
        dp2.age,
        
        -- ✅ MÉTRIQUES de base
        fc.nombre_consultations,
        fc.duree_consultation
        
    FROM {{ ref('fait_consultation') }} fc
    LEFT JOIN {{ ref('dim_temps') }} dt ON fc.sk_temps = dt.sk_temps
    LEFT JOIN {{ ref('dim_diagnostic') }} dd ON fc.sk_diagnostic = dd.sk_diagnostic
    LEFT JOIN {{ ref('dim_professionnel') }} dp ON fc.sk_professionnel = dp.sk_professionnel
    LEFT JOIN {{ ref('dim_specialite') }} ds ON dp.fk_specialite = ds.sk_specialite
    LEFT JOIN {{ ref('dim_patient') }} dp2 ON fc.sk_patient = dp2.sk_patient
    WHERE dp.est_actuel = TRUE
),

-- ✅ AGRÉGATION 1 : Par établissement
agreg_etablissement AS (
    SELECT 
        sk_temps,
        sk_etablissement,
        nom_etablissement,
        region_etablissement,
        departement_etablissement,
        annee,
        trimestre,
        mois,
        date_complete,
        
        -- ✅ PRÉ-CALCULS
        SUM(nombre_consultations) AS nb_consultations_etablissement,
        SUM(duree_consultation) AS duree_totale_etablissement,
        COUNT(DISTINCT sk_patient) AS nb_patients_uniques_etablissement,
        COUNT(DISTINCT sk_professionnel) AS nb_professionnels_etablissement
        
    FROM consultations_base
    GROUP BY 1,2,3,4,5,6,7,8,9
),

-- ✅ AGRÉGATION 2 : Par diagnostic
agreg_diagnostic AS (
    SELECT 
        sk_temps,
        sk_etablissement,
        sk_diagnostic,
        code_diagnostic,
        libelle_diagnostic,
        chapitre_cim10,
        categorie_cim10,
        annee,
        trimestre,
        mois,
        
        -- ✅ PRÉ-CALCULS
        SUM(nombre_consultations) AS nb_consultations_diagnostic,
        SUM(duree_consultation) AS duree_totale_diagnostic,
        COUNT(DISTINCT sk_patient) AS nb_patients_uniques_diagnostic
        
    FROM consultations_base
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),

-- ✅ AGRÉGATION 3 : Par professionnel
agreg_professionnel AS (
    SELECT 
        sk_temps,
        sk_professionnel,
        nom_professionnel,
        prenom_professionnel,
        specialite,
        fonction,
        annee,
        trimestre,
        mois,
        
        -- ✅ PRÉ-CALCULS
        SUM(nombre_consultations) AS nb_consultations_professionnel,
        SUM(duree_consultation) AS duree_totale_professionnel,
        COUNT(DISTINCT sk_patient) AS nb_patients_uniques_professionnel,
        COUNT(DISTINCT sk_etablissement) AS nb_etablissements_professionnel
        
    FROM consultations_base
    GROUP BY 1,2,3,4,5,6,7,8,9,10
),

-- ✅ AGRÉGATION 4 : Par profil patient (sexe/âge)
agreg_patient AS (
    SELECT 
        sk_temps,
        sexe,
        tranche_age,
        age,
        annee,
        trimestre,
        mois,
        
        -- ✅ PRÉ-CALCULS
        SUM(nombre_consultations) AS nb_consultations_profil,
        SUM(duree_consultation) AS duree_totale_profil,
        COUNT(DISTINCT sk_patient) AS nb_patients_uniques_profil
        
    FROM consultations_base
    WHERE sexe != 'I' AND tranche_age != 'Non renseigne'
    GROUP BY 1,2,3,4,5,6,7,8
),

-- ✅ JOINTURE FINALE : Vue dénormalisée complète
final AS (
    SELECT 
        -- Clés temporelles
        cb.sk_temps,
        cb.date_complete,
        cb.annee,
        cb.trimestre,
        cb.mois,
        
        -- Clés et libellés établissement
        cb.sk_etablissement,
        cb.nom_etablissement,
        cb.region_etablissement,
        cb.departement_etablissement,
        
        -- Clés et libellés diagnostic
        cb.sk_diagnostic,
        cb.code_diagnostic,
        cb.libelle_diagnostic,
        cb.chapitre_cim10,
        cb.categorie_cim10,
        
        -- Clés et libellés professionnel
        cb.sk_professionnel,
        cb.nom_professionnel,
        cb.prenom_professionnel,
        cb.specialite,
        cb.fonction,
        
        -- Profil patient
        cb.sexe,
        cb.tranche_age,
        cb.age,
        
        -- ✅ MESURES AGRÉGÉES (toutes pré-calculées)
        COALESCE(ae.nb_consultations_etablissement, 0) AS nb_consultations_etablissement,
        COALESCE(ae.duree_totale_etablissement, 0) AS duree_totale_etablissement,
        COALESCE(ae.nb_patients_uniques_etablissement, 0) AS nb_patients_uniques_etablissement,
        
        COALESCE(ad.nb_consultations_diagnostic, 0) AS nb_consultations_diagnostic,
        COALESCE(ad.duree_totale_diagnostic, 0) AS duree_totale_diagnostic,
        COALESCE(ad.nb_patients_uniques_diagnostic, 0) AS nb_patients_uniques_diagnostic,
        
        COALESCE(aprof.nb_consultations_professionnel, 0) AS nb_consultations_professionnel,
        COALESCE(aprof.duree_totale_professionnel, 0) AS duree_totale_professionnel,
        COALESCE(aprof.nb_patients_uniques_professionnel, 0) AS nb_patients_uniques_professionnel,
        
        COALESCE(apat.nb_consultations_profil, 0) AS nb_consultations_profil,
        COALESCE(apat.duree_totale_profil, 0) AS duree_totale_profil,
        COALESCE(apat.nb_patients_uniques_profil, 0) AS nb_patients_uniques_profil,
        
        CURRENT_TIMESTAMP AS date_chargement
        
    FROM consultations_base cb
    LEFT JOIN agreg_etablissement ae 
        ON cb.sk_temps = ae.sk_temps AND cb.sk_etablissement = ae.sk_etablissement
    LEFT JOIN agreg_diagnostic ad 
        ON cb.sk_temps = ad.sk_temps AND cb.sk_diagnostic = ad.sk_diagnostic
    LEFT JOIN agreg_professionnel aprof 
        ON cb.sk_temps = aprof.sk_temps AND cb.sk_professionnel = aprof.sk_professionnel
    LEFT JOIN agreg_patient apat 
        ON cb.sk_temps = apat.sk_temps AND cb.sexe = apat.sexe 
        AND cb.tranche_age = apat.tranche_age
)

SELECT * FROM final
```

**Avant (DWH - fait_consultation)** :
```
-- 1 ligne par consultation (granularité fine)
id_consultation | sk_temps | sk_patient | sk_professionnel | duree_consultation
----------------|----------|------------|------------------|-------------------
1001            | 20230501 | 1          | 1                | 25
1002            | 20230501 | 2          | 1                | 30
1003            | 20230502 | 1          | 2                | 20
... (1M+ lignes)
```

**Après (DATAMART - dm_consultations_agregees)** :
```
-- 1 ligne par combinaison (agrégé)
annee | mois | specialite | nb_consultations_professionnel | duree_totale_professionnel | nb_patients_uniques
------|------|------------|-------------------------------|---------------------------|--------------------
2023  | 5    | Cardio     | 150                           | 3750                      | 120
2023  | 5    | Dermato    | 200                           | 5000                      | 180
... (45M lignes agrégées)
```

**Gain** : Power BI n'a plus besoin d'agréger !

---

### 2️⃣ `dm_hospitalisations_agregees` ⭐ (Indicateurs Métier)

**Sources** : `fait_hospitalisation` + dimensions

**Grain** : **1 ligne = 1 combinaison (établissement, diagnostic, période, profil patient)**

#### Transformations

```sql
WITH hospitalisations_base AS (
    SELECT 
        fh.sk_temps,
        fh.sk_etablissement,
        fh.sk_diagnostic,
        fh.sk_patient,
        
        -- ✅ DÉNORMALISATION
        dt.annee,
        dt.trimestre,
        dt.mois,
        de.nom_etablissement,
        de.region AS region_etablissement,
        dd.code_diagnostic,
        dd.libelle_diagnostic,
        dp.sexe,
        dp.tranche_age,
        
        -- ✅ MÉTRIQUES
        fh.nombre_hospitalisations,
        fh.jour_hospitalisation
        
    FROM {{ ref('fait_hospitalisation') }} fh
    LEFT JOIN {{ ref('dim_temps') }} dt ON fh.sk_temps = dt.sk_temps
    LEFT JOIN {{ ref('dim_etablissement') }} de ON fh.sk_etablissement = de.sk_etablissement
    LEFT JOIN {{ ref('dim_diagnostic') }} dd ON fh.sk_diagnostic = dd.sk_diagnostic
    LEFT JOIN {{ ref('dim_patient') }} dp ON fh.sk_patient = dp.sk_patient
),

-- ✅ AGRÉGATIONS + INDICATEURS MÉTIER
agreg_etablissement AS (
    SELECT 
        sk_temps,
        sk_etablissement,
        nom_etablissement,
        region_etablissement,
        annee,
        trimestre,
        mois,
        
        -- ✅ PRÉ-CALCULS
        SUM(nombre_hospitalisations) AS nb_hospitalisations_etablissement,
        SUM(jour_hospitalisation) AS duree_totale_etablissement,
        COUNT(DISTINCT sk_patient) AS nb_patients_uniques_etablissement,
        
        -- ✅ INDICATEUR MÉTIER : DMS (Durée Moyenne Séjour)
        AVG(jour_hospitalisation) AS dms_etablissement  -- KPI important !
        
    FROM hospitalisations_base
    GROUP BY 1,2,3,4,5,6,7
),

-- ✅ AGRÉGATION par région
agreg_region AS (
    SELECT 
        sk_temps,
        region_etablissement,
        annee,
        trimestre,
        mois,
        
        SUM(nombre_hospitalisations) AS nb_hospitalisations_region,
        SUM(jour_hospitalisation) AS duree_totale_region,
        COUNT(DISTINCT sk_patient) AS nb_patients_uniques_region,
        COUNT(DISTINCT sk_etablissement) AS nb_etablissements_region,
        
        -- ✅ INDICATEUR : DMS régionale
        AVG(jour_hospitalisation) AS dms_region
        
    FROM hospitalisations_base
    WHERE region_etablissement IS NOT NULL
    GROUP BY 1,2,3,4,5
)
...
```

**Indicateurs calculés** :
- **DMS** (Durée Moyenne Séjour) : KPI hospitalier majeur
- **Taux occupation** : Si données disponibles
- **Taux réadmission** : Si jointure avec autre fait

---

### 3️⃣ `dm_analyse_territoriale` ⭐ (Consolidation Multi-Faits)

**Sources** : `fait_deces` + `fait_satisfaction` + dimensions

**Grain** : **1 ligne = 1 combinaison (région, période)**

#### Transformations

```sql
WITH deces_base AS (
    SELECT 
        fd.sk_temps,
        fd.sk_localisation,
        fd.sk_patient,
        
        -- ✅ DÉNORMALISATION
        dt.annee,
        dt.trimestre,
        dt.mois,
        dl.region,
        dl.departement,
        dp.sexe,
        dp.tranche_age,
        
        -- ✅ MÉTRIQUES
        fd.nombre_deces
        
    FROM {{ ref('fait_deces') }} fd
    LEFT JOIN {{ ref('dim_temps') }} dt ON fd.sk_temps = dt.sk_temps
    LEFT JOIN {{ ref('dim_localisation') }} dl ON fd.sk_localisation = dl.sk_localisation
    LEFT JOIN {{ ref('dim_patient') }} dp ON fd.sk_patient = dp.sk_patient
    WHERE dl.region IS NOT NULL
),

satisfaction_base AS (
    SELECT 
        fs.sk_temps,
        fs.sk_etablissement,
        
        -- ✅ DÉNORMALISATION
        dt.annee,
        dt.trimestre,
        dt.mois,
        de.region AS region_etablissement,
        
        -- ✅ MÉTRIQUES
        fs.score_global AS note_satisfaction,
        fs.nombre_reponses
        
    FROM {{ ref('fait_satisfaction') }} fs
    LEFT JOIN {{ ref('dim_temps') }} dt ON fs.sk_temps = dt.sk_temps
    LEFT JOIN {{ ref('dim_etablissement') }} de ON fs.sk_etablissement = de.sk_etablissement
    WHERE de.region IS NOT NULL
),

-- ✅ AGRÉGATION : Décès par région
agreg_deces_region AS (
    SELECT 
        sk_temps,
        region,
        annee,
        trimestre,
        mois,
        
        SUM(nombre_deces) AS nb_deces_region,
        COUNT(DISTINCT sk_patient) AS nb_patients_deces_region,
        
        -- ✅ VENTILATION par sexe
        SUM(CASE WHEN sexe = 'M' THEN nombre_deces ELSE 0 END) AS nb_deces_hommes,
        SUM(CASE WHEN sexe = 'F' THEN nombre_deces ELSE 0 END) AS nb_deces_femmes,
        
        -- ✅ VENTILATION par tranche d'âge
        SUM(CASE WHEN tranche_age = '0-18' THEN nombre_deces ELSE 0 END) AS nb_deces_0_18,
        SUM(CASE WHEN tranche_age = '19-30' THEN nombre_deces ELSE 0 END) AS nb_deces_19_30,
        SUM(CASE WHEN tranche_age = '31-50' THEN nombre_deces ELSE 0 END) AS nb_deces_31_50,
        SUM(CASE WHEN tranche_age = '51-65' THEN nombre_deces ELSE 0 END) AS nb_deces_51_65,
        SUM(CASE WHEN tranche_age = '66+' THEN nombre_deces ELSE 0 END) AS nb_deces_66_plus
        
    FROM deces_base
    GROUP BY 1,2,3,4,5
),

-- ✅ AGRÉGATION : Satisfaction par région
agreg_satisfaction_region AS (
    SELECT 
        sk_temps,
        region_etablissement,
        annee,
        trimestre,
        mois,
        
        SUM(nombre_reponses) AS nb_reponses_satisfaction,
        AVG(note_satisfaction) AS note_moyenne_satisfaction,
        COUNT(DISTINCT sk_etablissement) AS nb_etablissements_satisfaction
        
    FROM satisfaction_base
    GROUP BY 1,2,3,4,5
),

-- ✅ JOINTURE FINALE : Réunir décès + satisfaction
final AS (
    SELECT 
        COALESCE(dr.sk_temps, sr.sk_temps) AS sk_temps,
        COALESCE(dr.annee, sr.annee) AS annee,
        COALESCE(dr.trimestre, sr.trimestre) AS trimestre,
        COALESCE(dr.mois, sr.mois) AS mois,
        COALESCE(dr.region, sr.region_etablissement) AS region,
        
        -- ✅ INDICATEURS DÉCÈS
        COALESCE(dr.nb_deces_region, 0) AS nb_deces_region,
        COALESCE(dr.nb_deces_hommes, 0) AS nb_deces_hommes,
        COALESCE(dr.nb_deces_femmes, 0) AS nb_deces_femmes,
        COALESCE(dr.nb_deces_0_18, 0) AS nb_deces_0_18,
        -- ... autres tranches d'âge
        
        -- ✅ INDICATEURS SATISFACTION
        COALESCE(sr.nb_reponses_satisfaction, 0) AS nb_reponses_satisfaction,
        COALESCE(sr.note_moyenne_satisfaction, 0) AS note_moyenne_satisfaction,
        COALESCE(sr.nb_etablissements_satisfaction, 0) AS nb_etablissements_satisfaction,
        
        CURRENT_TIMESTAMP AS date_chargement
        
    FROM agreg_deces_region dr
    FULL OUTER JOIN agreg_satisfaction_region sr 
        ON dr.sk_temps = sr.sk_temps AND dr.region = sr.region_etablissement
)

SELECT * FROM final
```

**Résultat** : Vue consolidée décès + satisfaction par région

---

## 📊 Transformations Spéciales DATAMART

### 📈 Pré-calculs d'Agrégations

```sql
-- ✅ SUM pré-calculé
SUM(nombre_consultations) AS total_consultations

-- ✅ AVG pré-calculé
AVG(duree_consultation) AS duree_moyenne

-- ✅ COUNT DISTINCT pré-calculé
COUNT(DISTINCT sk_patient) AS nb_patients_uniques

-- ✅ PERCENTILE pré-calculé
PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duree) AS mediane_duree
```

### 🎯 Indicateurs Métier (KPI)

```sql
-- ✅ DMS (Durée Moyenne Séjour)
AVG(jour_hospitalisation) AS dms

-- ✅ Taux satisfaction
SUM(nb_satisfaits) / NULLIF(SUM(nb_reponses), 0) * 100 AS taux_satisfaction

-- ✅ Taux mortalité (pour 1000)
SUM(nb_deces) / NULLIF(SUM(nb_population), 0) * 1000 AS taux_mortalite_pour_1000

-- ✅ Ratio consultations/habitant
SUM(nb_consultations) / NULLIF(SUM(nb_habitants), 0) AS ratio_consultation_habitant
```

### 🔄 Ventilations (Breakdowns)

```sql
-- ✅ PIVOT : Ventilation par sexe
SUM(CASE WHEN sexe = 'M' THEN nombre ELSE 0 END) AS nb_hommes,
SUM(CASE WHEN sexe = 'F' THEN nombre ELSE 0 END) AS nb_femmes,
SUM(CASE WHEN sexe = 'I' THEN nombre ELSE 0 END) AS nb_inconnu

-- ✅ PIVOT : Ventilation par tranche d'âge
SUM(CASE WHEN tranche_age = '0-18' THEN nombre ELSE 0 END) AS nb_0_18,
SUM(CASE WHEN tranche_age = '19-30' THEN nombre ELSE 0 END) AS nb_19_30,
SUM(CASE WHEN tranche_age = '31-50' THEN nombre ELSE 0 END) AS nb_31_50,
SUM(CASE WHEN tranche_age = '51-65' THEN nombre ELSE 0 END) AS nb_51_65,
SUM(CASE WHEN tranche_age = '66+' THEN nombre ELSE 0 END) AS nb_66_plus
```

### 🏆 Classements (Ranking)

```sql
-- ✅ TOP N
WITH ranked AS (
    SELECT
        region,
        nb_consultations,
        ROW_NUMBER() OVER (ORDER BY nb_consultations DESC) AS rang
    FROM consultations_region
)
SELECT * FROM ranked WHERE rang <= 10  -- Top 10

-- ✅ RANK par catégorie
RANK() OVER (PARTITION BY region ORDER BY nb_consultations DESC) AS rang_region

-- ✅ PERCENTILE
PERCENT_RANK() OVER (ORDER BY nb_consultations) AS percentile_rang
```

---

## 📊 Résumé Transformations DWH → DATAMART

| Table DATAMART | Sources DWH | Transformations Principales | Volumétrie |
|----------------|-------------|----------------------------|------------|
| `dm_consultations_agregees` | fait_consultation + 5 dims | ⭐ 4 agrégations (établ/diag/pro/patient), Dénormalisation complète | ~45M lignes |
| `dm_hospitalisations_agregees` | fait_hospitalisation + 4 dims | ⭐ Agrégations multi-niveaux, Calcul DMS (KPI) | ~6K lignes |
| `dm_analyse_territoriale` | fait_deces + fait_satisfaction + dims | ⭐ Consolidation 2 faits, Ventilations sexe/âge, FULL OUTER JOIN | ~30K lignes |

---

## 📋 Checklist Qualité DATAMART

### ✅ Chaque DATAMART doit avoir :

- [ ] **Grain clairement défini** et documenté
- [ ] **Toutes agrégations pré-calculées** (pas de calcul dans Power BI)
- [ ] **Dénormalisation complète** (libellés présents)
- [ ] **Indicateurs métier** (KPI) calculés
- [ ] **Performance optimisée** (<5s requête Power BI)
- [ ] **Pas de NULL** (COALESCE vers 0)
- [ ] **Documentation** des mesures et dimensions

### ✅ Pour Power BI :

- [ ] **Vue plate** (pas de jointures nécessaires)
- [ ] **Noms de colonnes explicites** (français, pas d'abréviations)
- [ ] **Types de données corrects** (INTEGER pour compteurs, DECIMAL pour ratios)
- [ ] **Dates dans format standard** (pas de sk_temps dans BI)
- [ ] **Filtres optimisés** (index sur colonnes filtrées)

---

## 🚫 Anti-Patterns (À Éviter)

### ❌ MAUVAIS : Ne pas pré-calculer

```sql
-- ❌ PAS BON ! Power BI devra agréger
SELECT
    sk_temps,
    sk_patient,
    duree_consultation  -- ← Power BI fera SUM() à chaque fois !
FROM fait_consultation
```

**Correct** : Pré-calculer

```sql
-- ✅ BON !
SELECT
    annee,
    mois,
    region,
    SUM(duree_consultation) AS duree_totale  -- ← Déjà agrégé !
FROM fait_consultation
GROUP BY annee, mois, region
```

### ❌ MAUVAIS : Garder clés substituts dans BI

```sql
-- ❌ PAS BON !
SELECT
    sk_temps,  -- ← 20230515 pas lisible dans Power BI !
    region,
    nb_consultations
FROM datamart
```

**Correct** : Utiliser dates lisibles

```sql
-- ✅ BON !
SELECT
    date_complete,  -- ← 2023-05-15 lisible !
    annee,
    mois,
    region,
    nb_consultations
FROM datamart
```

---

## 🎯 Optimisation pour Power BI

### 🚀 Bonnes Pratiques

```sql
-- ✅ 1. Dénormaliser complètement
SELECT
    annee,
    mois,
    region,
    nom_etablissement,     -- ← Pas besoin de jointure !
    type_etablissement,
    nb_consultations

-- ✅ 2. Pré-calculer TOUT
SELECT
    region,
    SUM(nb_consultations) AS total_consultations,
    AVG(duree) AS duree_moyenne,
    COUNT(DISTINCT id_patient) AS nb_patients_uniques,
    SUM(nb_consultations) / COUNT(DISTINCT id_patient) AS ratio_consultation_patient

-- ✅ 3. Ventiler les dimensions importantes
SELECT
    region,
    SUM(CASE WHEN sexe = 'M' THEN nb END) AS nb_hommes,
    SUM(CASE WHEN sexe = 'F' THEN nb END) AS nb_femmes,
    SUM(nb) AS total

-- ✅ 4. Gérer les NULL
COALESCE(valeur, 0) AS valeur_propre
```

---

## 🎯 Workflow Complet

```
RAW (données brutes)
    ↓ (nettoyage simple)
STAGING (données nettoyées)
    ↓ (jointures + règles métier)
ODS (données intégrées)
    ↓ (modèle dimensionnel)
DWH (star schema)
    ↓ (agrégations + KPI)
DATAMART (vues optimisées)
    ↓
POWER BI (dashboards)
```

---

## ✨ Exemple Complet : Du Fait au Datamart

**Étape 1 - FAIT (1M lignes)** :
```sql
-- fait_consultation
id_consultation | sk_temps | sk_patient | duree
----------------|----------|------------|------
1               | 20230501 | 1          | 25
2               | 20230501 | 2          | 30
... (1M lignes)
```

**Étape 2 - DATAMART (agrégé, 1K lignes)** :
```sql
-- dm_consultations_agregees
annee | mois | region        | nb_consultations | duree_moyenne | nb_patients
------|------|---------------|------------------|---------------|------------
2023  | 5    | Ile-de-France | 50000            | 27.5          | 35000
2023  | 6    | Ile-de-France | 52000            | 28.1          | 36000
... (1K lignes agrégées)
```

**Étape 3 - POWER BI** : Utilise directement le datamart (rapide !)

---

**Auteur** : Équipe Big Data Groupe 3  
**Version** : 1.0  
**Date** : 2025-10-21

