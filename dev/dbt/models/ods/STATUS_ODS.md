# Status ODS - Phase 2 

## 📊 Résumé

**9 modèles ODS créés** pour intégrer et enrichir les données staging avec des jointures et règles métier.

Ces modèles alimenteront les **5 tables de faits** du DWH cible.

---

## ✅ Modèles ODS créés

### Core Business (6 modèles)

| Modèle | Sources | Description | Destination DWH |
|--------|---------|-------------|-----------------|
| ✅ `ods_patient_complet` | stg_patient + stg_mutuelle + stg_adher | Patient + mutuelle active | → dim_patient |
| ✅ `ods_professionnel_complet` | stg_professionnel_sante + stg_etablissement_professionnel | Pro + établissements | → dim_professionnel |
| ✅ `ods_consultation_enrichie` | stg_consultation + ods_patient + ods_professionnel + stg_diagnostic | Consultation complète | → fait_consultation |
| ✅ `ods_hospitalisation_enrichie` | stg_hospitalisation + ods_patient + stg_etablissement + stg_diagnostic | Hospitalisation complète | → fait_hospitalisation |
| ✅ `ods_deces_enrichi` | stg_deces | Décès avec classifications | → fait_deces |
| ✅ `ods_prescription_enrichie` | stg_prescription + stg_medicaments + ods_consultation | Prescriptions + médicaments | → (enrichissement) |

### Référentiels (1 modèle)

| Modèle | Sources | Description | Destination DWH |
|--------|---------|-------------|-----------------|
| ✅ `ods_localisation_consolidee` | stg_patient + stg_etablissement + stg_deces | Référentiel géo unifié | → dim_localisation |

### Satisfaction & Qualité (2 modèles consolidés)

| Modèle | Sources | Description | Destination DWH |
|--------|---------|-------------|-----------------|
| ✅ `ods_satisfaction_unifie` | 31 tables CSV satisfaction (2014-2020) | Consolidation e-Satis | → fait_satisfaction |
| ✅ `ods_qualite_soins_unifie` | Tables IQSS + ETE ORTHO | Consolidation indicateurs qualité | → fait_qualite_soins |

### 📌 Alignement avec DWH cible

**Votre DWH PostgreSQL a 5 FAITS** :
1. `fait_consultation` ← `ods_consultation_enrichie` ✅
2. `fait_hospitalisation` ← `ods_hospitalisation_enrichie` ✅
3. `fait_deces` ← `ods_deces_enrichi` ✅
4. `fait_satisfaction` ← `ods_satisfaction_unifie` ✅
5. `fait_qualite_soins` ← `ods_qualite_soins_unifie` ✅

**Chaque fait a son modèle ODS préparatoire !**

---

## 🔄 Transformations ODS appliquées

### ods_patient_complet
**Jointures** :
- `stg_patient` LEFT JOIN `stg_adher` (sur id_patient)
- `stg_adher` LEFT JOIN `stg_mutuelle` (sur id_mut)

**Enrichissements** :
- ✅ Informations mutuelle ajoutées
- ✅ Statut adhesion
- ✅ Flag `a_mutuelle_active` (booléen)

---

### ods_professionnel_complet
**Jointures** :
- `stg_professionnel_sante` LEFT JOIN `stg_etablissement_professionnel`
- Agrégation par professionnel

**Enrichissements** :
- ✅ Commune d'exercice principale
- ✅ Spécialité d'exercice
- ✅ `mode_exercice` calculé (Libéral/Salarié) depuis catégorie
- ✅ Comptage établissements par professionnel

---

### ods_consultation_enrichie
**Jointures** :
- `stg_consultation` INNER JOIN `ods_patient_complet`
- LEFT JOIN `ods_professionnel_complet`
- LEFT JOIN `stg_diagnostic`

**Enrichissements** :
- ✅ Toutes infos patient (nom, âge, mutuelle, etc.)
- ✅ Toutes infos professionnel (nom, profession, spécialité)
- ✅ Libellé diagnostic complet
- ✅ **Classification patient** : PEDIATRIE / ADULTE / GERIATRIE
- ✅ **Classification durée** : COURTE / NORMALE / LONGUE

---

### ods_hospitalisation_enrichie
**Jointures** :
- `stg_hospitalisation` INNER JOIN `ods_patient_complet`
- LEFT JOIN `stg_etablissement_sante`
- LEFT JOIN `stg_diagnostic`

**Enrichissements** :
- ✅ Infos patient complètes
- ✅ Infos établissement (nom, commune, département)
- ✅ Diagnostic complet
- ✅ **Classification séjour** : COURT_SEJOUR / MOYEN_SEJOUR / LONG_SEJOUR
- ✅ **Classification patient** : PEDIATRIE / ADULTE / GERIATRIE

---

### ods_deces_enrichi
**Pas de jointures** (données déjà complètes)

**Enrichissements** :
- ✅ **Classification âge décès** : MOINS_1_AN / ENFANT / JEUNE_ADULTE / ADULTE / SENIOR
- ✅ **Conversion sexe** : 1→M, 2→F, autre→INCONNU
- ✅ Calcul âge au décès (depuis date_naissance et date_deces)

---

### ods_localisation_consolidee
**Union de 3 sources** :
- Localisations patients (code_postal + ville)
- Localisations établissements (code_postal + commune)
- Localisations décès (code_lieu_deces)

**Enrichissements** :
- ✅ Dédoublonnage par `code_lieu`
- ✅ Agrégation types de lieux
- ✅ Comptage occurrences
- ✅ Consolidation informations géographiques
- ✅ Préparation lat/long (colonnes créées pour futur enrichissement)

---

## 🎯 Règles métier appliquées

### Classification patients
```sql
CASE
    WHEN age < 18 THEN 'PEDIATRIE'
    WHEN age > 65 THEN 'GERIATRIE'
    ELSE 'ADULTE'
END
```

### Classification durée consultation
```sql
CASE
    WHEN duree < 15 THEN 'COURTE'
    WHEN duree BETWEEN 15 AND 30 THEN 'NORMALE'
    WHEN duree > 30 THEN 'LONGUE'
END
```

### Classification séjour hospitalisation
```sql
CASE
    WHEN jours < 3 THEN 'COURT_SEJOUR'
    WHEN jours BETWEEN 3 AND 7 THEN 'MOYEN_SEJOUR'
    WHEN jours > 7 THEN 'LONG_SEJOUR'
END
```

### Classification âge décès
```sql
CASE
    WHEN age < 1 THEN 'MOINS_1_AN'
    WHEN age BETWEEN 1 AND 18 THEN 'ENFANT'
    WHEN age BETWEEN 19 AND 30 THEN 'JEUNE_ADULTE'
    WHEN age BETWEEN 31 AND 65 THEN 'ADULTE'
    WHEN age > 65 THEN 'SENIOR'
END
```

---

## 🚀 Commandes pour tester

### Exécuter tous les modèles ODS
```bash
cd dbt
dbt run --select tag:ods
```

### Exécuter dans l'ordre des dépendances
```bash
# D'abord les modèles de base
dbt run --select ods_patient_complet ods_professionnel_complet ods_deces_enrichi ods_localisation_consolidee

# Puis les modèles enrichis qui dépendent des précédents
dbt run --select ods_consultation_enrichie ods_hospitalisation_enrichie
```

### Exécuter tout le pipeline
```bash
# Staging puis ODS (DBT gère l'ordre automatiquement)
dbt run --select tag:staging tag:ods
```

---

## 📈 Volumétrie attendue

| Table ODS | Lignes estimées | Note |
|-----------|-----------------|------|
| `ods_patient_complet` | ~100k | Patients avec mutuelle |
| `ods_professionnel_complet` | ~1M | Professionnels agrégés |
| `ods_consultation_enrichie` | ~1M | Consultations complètes |
| `ods_hospitalisation_enrichie` | ~2.5k | Hospitalisations |
| `ods_deces_enrichi` | ~25M | Décès (grosse table !) |
| `ods_localisation_consolidee` | ~50k | Lieux uniques consolidés |

---

## 🔍 Requêtes de vérification DuckDB

```sql
-- Voir les tables ODS créées
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'ods'
ORDER BY table_name;

-- Compter les lignes
SELECT COUNT(*) FROM ods.ods_patient_complet;
SELECT COUNT(*) FROM ods.ods_consultation_enrichie;

-- Vérifier enrichissements
SELECT 
    patient_tranche_age,
    categorie_patient,
    COUNT(*) as nb_consultations
FROM ods.ods_consultation_enrichie
GROUP BY patient_tranche_age, categorie_patient;

-- Vérifier patients avec/sans mutuelle
SELECT 
    a_mutuelle_active,
    COUNT(*) as nb_patients
FROM ods.ods_patient_complet
GROUP BY a_mutuelle_active;
```

---

## ✅ Prochaines étapes - Phase 3 : DIMENSIONS

Une fois l'ODS validé, on créera les dimensions :
1. `dim_temps` (macro génération 2015-2030)
2. `dim_specialite`
3. `dim_mutuelle`  
4. `dim_diagnostic`
5. `dim_etablissement`
6. `dim_localisation`
7. `dim_patient` (SCD Type 1)
8. `dim_professionnel` (SCD Type 2)

---

## 🎓 Architecture actuelle

```
RAW (44 tables, 30M+ lignes) ✅ Chargé
  ↓
STAGING (17 tables, 30M+ lignes) ✅ Nettoyé
  ↓
ODS (6 tables) ✅ Créé (à tester)
  ↓
DWH (13 tables) 🔲 À créer
```
