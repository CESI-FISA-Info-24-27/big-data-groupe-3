# 📖 Dictionnaire de Données - DWH CHU

## 📋 Vue d'Ensemble

Ce dictionnaire décrit toutes les tables du **Data Warehouse** (schéma `dwh` dans PostgreSQL).

**Architecture** : Modèle en Constellation (Star Schema)
- **8 Dimensions** (tables de référence)
- **5 Faits** (tables de mesures)
- **4 Vues analytiques** (pour analyses rapides)

---

## 📊 Tables du DWH

### Résumé

| Type | Tables | Volumétrie | Rafraîchissement |
|------|--------|------------|------------------|
| **Dimensions** | 8 | ~2M lignes | Mensuel |
| **Faits** | 5 | ~27M lignes | Quotidien/Mensuel/Annuel |
| **Vues** | 4 | Calculées | Temps réel |
| **TOTAL** | 17 | ~29M lignes | - |

---

## 🔷 DIMENSIONS (Tables de Référence)

### 1. `dim_patient` - Dimension Patient

**Description** : Patients du CHU avec informations démographiques et médicales

**Type SCD** : Type 1 (pas d'historisation)

**Alimentation** : Mensuelle

**Volumétrie** : ~100,000 lignes

#### Structure

| Colonne | Type | Contrainte | Description |
|---------|------|------------|-------------|
| `sk_patient` | BIGSERIAL | PRIMARY KEY | **Clé substitut** (auto-générée) |
| `id_patient` | INT | UNIQUE NOT NULL | **Business Key** (clé métier source) |
| `nom_anonyme` | VARCHAR(8) | - | Nom hashé SHA-256 (8 car) - **RGPD** |
| `prenom_anonyme` | VARCHAR(8) | - | Prénom hashé SHA-256 (8 car) - **RGPD** |
| `sexe` | VARCHAR(10) | - | M/F/I (Inconnu) |
| `date_naissance` | DATE | - | Date de naissance |
| `age` | INT | - | Âge calculé (années) |
| `tranche_age` | VARCHAR(20) | - | Catégorie : '0-18', '19-30', '31-50', '51-65', '66+' |
| `groupe_sanguin` | VARCHAR(3) | - | A+, B-, O+, AB-, etc. |
| `poids` | DECIMAL(5,2) | - | Poids en kg |
| `taille` | INT | - | Taille en cm |
| `code_postal` | VARCHAR(10) | - | Code postal |
| `ville` | VARCHAR(100) | - | Ville de résidence |
| `pays` | VARCHAR(2) | - | Code pays (FR par défaut) |
| `num_secu_hash` | VARCHAR(64) | - | Numéro sécu hashé SHA-256 (64 car) - **RGPD** |
| `date_chargement` | TIMESTAMP | DEFAULT NOW() | Date de création de la ligne |
| `date_modification` | TIMESTAMP | DEFAULT NOW() | Date de dernière modification |

#### Index

- `PRIMARY KEY` : `sk_patient`
- `UNIQUE` : `id_patient`
- `INDEX` : `id_patient`, `sexe + tranche_age`

#### Business Rules

- ✅ Ligne "Inconnu" : `sk_patient = -1`
- ✅ Anonymisation RGPD : Noms et num_secu hashés
- ✅ Tranche d'âge calculée automatiquement
- ✅ Pays par défaut = 'FR'

#### Exemple

```sql
sk_patient | id_patient | nom_anonyme | sexe | age | tranche_age | groupe_sanguin | num_secu_hash
-----------|------------|-------------|------|-----|-------------|----------------|---------------
-1         | -1         | INCONNU     | I    | 0   | Non renseigne| ?              | NULL
1          | 1001       | a3f2d1c8    | M    | 44  | 31-50       | A+             | 5e884898da...
2          | 1002       | 9b4e6f2a    | F    | 28  | 19-30       | O+             | 7f9a2b1c3d...
```

---

### 2. `dim_professionnel` - Dimension Professionnel de Santé

**Description** : Professionnels de santé avec historisation des changements

**Type SCD** : Type 2 (historisation complète)

**Alimentation** : Mensuelle

**Volumétrie** : ~1,048,575 lignes

#### Structure

| Colonne | Type | Contrainte | Description |
|---------|------|------------|-------------|
| `sk_professionnel` | BIGSERIAL | PRIMARY KEY | **Clé substitut** (auto-générée, unique) |
| `identifiant` | VARCHAR(20) | NOT NULL | **Business Key** (RPPS/ADELI) - **Peut se répéter** |
| `civilite` | VARCHAR(10) | - | M./Mme/Dr/Pr |
| `nom_anonyme` | VARCHAR(8) | - | Nom hashé SHA-256 (8 car) - **RGPD** |
| `prenom_anonyme` | VARCHAR(8) | - | Prénom hashé SHA-256 (8 car) - **RGPD** |
| `profession` | VARCHAR(100) | - | Médecin, Infirmier, Pharmacien, etc. |
| `categorie_professionnelle` | VARCHAR(50) | - | Libéral, Salarié, etc. |
| `fk_specialite` | BIGINT | FK → dim_specialite | **Clé étrangère** vers spécialité |
| `mode_exercice` | VARCHAR(20) | - | Libéral/Salarié/Mixte |
| `fk_organisation` | VARCHAR(20) | - | FINESS établissement principal |
| `date_debut_validite` | DATE | NOT NULL | **SCD Type 2** : Début période validité |
| `date_fin_validite` | DATE | - | **SCD Type 2** : Fin période (NULL = actuel) |
| `est_actuel` | BOOLEAN | DEFAULT TRUE | **SCD Type 2** : TRUE si version actuelle |
| `date_chargement` | TIMESTAMP | DEFAULT NOW() | Date de création de la ligne |

#### Index

- `PRIMARY KEY` : `sk_professionnel`
- `INDEX` : `identifiant`, `est_actuel (WHERE TRUE)`, `fk_organisation`

#### Business Rules (SCD Type 2)

- ✅ Ligne "Inconnu" : `sk_professionnel = -1`
- ✅ Un identifiant peut avoir **plusieurs versions** (historique)
- ✅ `est_actuel = TRUE` : Version actuelle
- ✅ `date_fin_validite = NULL` : Version actuelle
- ✅ Nouvelle version créée si changement de spécialité/établissement

#### Exemple SCD Type 2

```sql
-- Historique du professionnel RPPS 123456
sk_professionnel | identifiant | nom_anonyme | fk_specialite | date_debut    | date_fin   | est_actuel
-----------------|-------------|-------------|---------------|---------------|------------|------------
142              | 123456      | a3f2d1c8    | 5 (Cardio)    | 2020-01-01    | 2023-06-30 | FALSE
857              | 123456      | a3f2d1c8    | 12 (Chirurgie)| 2023-07-01    | NULL       | TRUE

-- Requête version actuelle
SELECT * FROM dim_professionnel WHERE identifiant = '123456' AND est_actuel = TRUE;
-- → sk_professionnel = 857

-- Requête version à une date donnée (2022-03-15)
SELECT * FROM dim_professionnel 
WHERE identifiant = '123456' 
  AND date_debut_validite <= '2022-03-15'
  AND (date_fin_validite >= '2022-03-15' OR date_fin_validite IS NULL);
-- → sk_professionnel = 142 (il était cardiologue en 2022)
```

---

### 3. `dim_temps` - Dimension Temporelle

**Description** : Calendrier complet avec jours fériés français

**Type SCD** : Non applicable (dimension de référence fixe)

**Alimentation** : Unique (pré-génération 2015-2030)

**Volumétrie** : 5,845 lignes (16 ans × 365.25 jours)

#### Structure

| Colonne | Type | Contrainte | Description |
|---------|------|------------|-------------|
| `sk_temps` | BIGINT | PRIMARY KEY | **Clé substitut** format YYYYMMDD (ex: 20230515) |
| `date_complete` | DATE | UNIQUE NOT NULL | **Business Key** (date complète) |
| `jour` | INT | NOT NULL | Jour du mois (1-31) |
| `mois` | INT | NOT NULL | Mois (1-12) |
| `trimestre` | INT | NOT NULL | Trimestre (1-4) |
| `semestre` | INT | NOT NULL | Semestre (1-2) |
| `annee` | INT | NOT NULL | Année (2015-2030) |
| `semaine_annee` | INT | NOT NULL | Semaine de l'année (1-53) |
| `jour_semaine` | INT | NOT NULL | Jour de la semaine (1=Lundi, 7=Dimanche) |
| `nom_jour` | VARCHAR(10) | - | Lundi, Mardi, etc. |
| `nom_mois` | VARCHAR(20) | - | Janvier, Février, etc. |
| `est_weekend` | BOOLEAN | - | TRUE si samedi ou dimanche |
| `est_ferie` | BOOLEAN | - | TRUE si jour férié français |
| `saison` | VARCHAR(20) | - | Printemps/Été/Automne/Hiver |
| `date_chargement` | TIMESTAMP | DEFAULT NOW() | Date de création |

#### Index

- `PRIMARY KEY` : `sk_temps`
- `UNIQUE` : `date_complete`
- `INDEX` : `date_complete`, `annee + mois`, `annee + trimestre`

#### Business Rules

- ✅ Ligne "Inconnu" : `sk_temps = -1`
- ✅ Jours fériés français : 1er janvier, 1er mai, 8 mai, 14 juillet, 15 août, 1er novembre, 11 novembre, 25 décembre
- ✅ Weekend : Samedi (6) et Dimanche (7)
- ✅ Clé format YYYYMMDD pour faciliter les tris

#### Exemple

```sql
sk_temps | date_complete | jour | mois | trimestre | annee | jour_semaine | nom_jour | est_weekend | est_ferie
---------|---------------|------|------|-----------|-------|--------------|----------|-------------|----------
-1       | NULL          | 0    | 0    | 0         | 0     | 0            | Inconnu  | FALSE       | FALSE
20230101 | 2023-01-01    | 1    | 1    | 1         | 2023  | 7            | Dimanche | TRUE        | TRUE (Jour de l'An)
20230515 | 2023-05-15    | 15   | 5    | 2         | 2023  | 1            | Lundi    | FALSE       | FALSE
20231225 | 2023-12-25    | 25   | 12   | 4         | 2023  | 1            | Lundi    | FALSE       | TRUE (Noël)
```

---

### 4. `dim_specialite` - Dimension Spécialité Médicale

**Description** : Référentiel des spécialités médicales avec classification

**Type SCD** : Type 1 (pas d'historisation)

**Alimentation** : Mensuelle

**Volumétrie** : 94 lignes

#### Structure

| Colonne | Type | Contrainte | Description |
|---------|------|------------|-------------|
| `sk_specialite` | BIGSERIAL | PRIMARY KEY | **Clé substitut** |
| `code_specialite` | VARCHAR(10) | UNIQUE NOT NULL | **Business Key** (code spécialité) |
| `fonction` | VARCHAR(100) | - | Fonction : Médecin généraliste, Infirmier, etc. |
| `specialite` | VARCHAR(100) | - | Spécialité détaillée : Cardiologie, Dermatologie, etc. |
| `categorie` | VARCHAR(50) | - | **Classification** : Médecine générale, Soins infirmiers, etc. |
| `date_chargement` | TIMESTAMP | DEFAULT NOW() | Date de création |

#### Catégories (30+)

- Médecine générale
- Médecine spécialisée
- Soins infirmiers
- Chirurgie
- Pharmacie
- Rééducation
- Santé mentale
- Imagerie médicale
- Dentaire
- Médecine alternative
- ... (voir stg_specialites.sql pour la liste complète)

#### Exemple

```sql
sk_specialite | code_specialite | fonction              | specialite   | categorie
--------------|-----------------|-----------------------|--------------|-------------------
-1            | INCONNU         | Inconnu               | NULL         | Autre
1             | SM26            | Infirmier             | NULL         | Soins infirmiers
2             | SM54            | Médecin spécialiste   | Cardiologie  | Medecine specialisee
```

---

### 5. `dim_diagnostic` - Dimension Diagnostic CIM-10

**Description** : Référentiel des diagnostics médicaux (Classification CIM-10)

**Type SCD** : Type 1 (pas d'historisation)

**Alimentation** : Mensuelle

**Volumétrie** : ~15,491 lignes

#### Structure

| Colonne | Type | Contrainte | Description |
|---------|------|------------|-------------|
| `sk_diagnostic` | BIGSERIAL | PRIMARY KEY | **Clé substitut** |
| `code_diagnostic` | VARCHAR(10) | UNIQUE NOT NULL | **Business Key** (code CIM-10) |
| `libelle_diagnostic` | VARCHAR(255) | - | Description du diagnostic |
| `categorie_cim10` | VARCHAR(5) | - | 3 premiers caractères du code (ex: J06) |
| `chapitre_cim10` | VARCHAR(100) | - | Chapitre CIM-10 (21 chapitres) |
| `source_donnee` | VARCHAR(50) | - | Source : PostgreSQL/Hospitalisation/Etablissement |
| `date_chargement` | TIMESTAMP | DEFAULT NOW() | Date de création |

#### Index

- `PRIMARY KEY` : `sk_diagnostic`
- `UNIQUE` : `code_diagnostic`
- `INDEX` : `code_diagnostic`, `categorie_cim10`

#### Chapitres CIM-10 (21)

1. Maladies infectieuses et parasitaires (A00-B99)
2. Tumeurs (C00-D48)
3. Maladies du sang (D50-D89)
4. Maladies endocriniennes (E00-E90)
5. Troubles mentaux (F00-F99)
6. Maladies du système nerveux (G00-G99)
7. Maladies de l'œil (H00-H59)
8. Maladies de l'oreille (H60-H95)
9. **Maladies de l'appareil circulatoire (I00-I99)**
10. **Maladies de l'appareil respiratoire (J00-J99)**
... (21 chapitres au total)

#### Exemple

```sql
sk_diagnostic | code_diagnostic | libelle_diagnostic                    | categorie_cim10 | chapitre_cim10
--------------|-----------------|---------------------------------------|-----------------|----------------------------
-1            | INCONNU         | Diagnostic inconnu                    | INC             | Inconnu
42            | J06.9           | Infection aiguë des voies respiratoires| J06             | Maladies appareil respiratoire
125           | I10             | Hypertension essentielle (primaire)   | I10             | Maladies appareil circulatoire
```

---

### 6. `dim_etablissement` - Dimension Établissement de Santé

**Description** : Établissements de santé référencés FINESS

**Type SCD** : Type 1 (pas d'historisation)

**Alimentation** : Mensuelle

**Volumétrie** : ~416,000 lignes (mais seulement ~201 dans les faits actuels)

#### Structure

| Colonne | Type | Contrainte | Description |
|---------|------|------------|-------------|
| `sk_etablissement` | BIGSERIAL | PRIMARY KEY | **Clé substitut** |
| `finess` | VARCHAR(20) | UNIQUE NOT NULL | **Business Key** (numéro FINESS) |
| `nom_etablissement` | VARCHAR(255) | - | Raison sociale |
| `type_etablissement` | VARCHAR(50) | - | **Classification auto** : CHU/Hôpital/Clinique/EHPAD/etc. |
| `categorie` | VARCHAR(100) | - | Public/Privé/Médico-social/Non déterminé |
| `region` | VARCHAR(100) | - | Région française (13 régions) |
| `departement` | VARCHAR(3) | - | Département (01-95, 2A, 2B, 971-976) |
| `adresse` | VARCHAR(255) | - | Adresse complète |
| `code_postal` | VARCHAR(10) | - | Code postal |
| `ville` | VARCHAR(100) | - | Commune |
| `date_chargement` | TIMESTAMP | DEFAULT NOW() | Date de création |

#### Index

- `PRIMARY KEY` : `sk_etablissement`
- `UNIQUE` : `finess`
- `INDEX` : `finess`, `region`

#### Classification Automatique

**Types détectés** (basé sur le nom) :
- **CHU** : si nom contient "CHU" ou "UNIVERSITAIRE"
- **Hôpital Public** : si "CH ", "HOPITAL", "HOSP"
- **Clinique Privée** : si "CLINIQUE"
- **EHPAD** : si "EHPAD"
- **Centre de Santé** : si "CENTRE" + "SANTE"
- **CIAS** : si "CIAS" ou "CCAS"
- **Conseil Départemental** : si "CONSEIL" + "DEPARTEMENTAL"
- **Autre établissement** : par défaut

**Catégories** :
- **Public** : CHU, CH, Hôpital, Conseil Départemental
- **Privé** : Clinique, Cabinet
- **Médico-social** : EHPAD, Maison retraite, CIAS

#### Exemple

```sql
sk_etablissement | finess    | nom_etablissement                   | type_etablissement        | categorie     | region
-----------------|-----------|-------------------------------------|---------------------------|---------------|---------------
-1               | INCONNU   | Etablissement inconnu               | Autre etablissement       | Non determine | Non renseigne
1                | 180036014 | CHNO DES QUINZE-VINGTS PARIS       | Hopital Public            | Public        | Ile-de-France
2                | 200009181 | CIAS AIME                           | Centre Communal Action... | Medico-social | Auvergne-Rhone-Alpes
```

---

### 7. `dim_localisation` - Dimension Localisation Géographique

**Description** : Lieux consolidés (patients, établissements, décès)

**Type SCD** : Type 1 (pas d'historisation)

**Alimentation** : Mensuelle

**Volumétrie** : ~50,000 lignes

#### Structure

| Colonne | Type | Contrainte | Description |
|---------|------|------------|-------------|
| `sk_localisation` | BIGSERIAL | PRIMARY KEY | **Clé substitut** |
| `code_lieu` | VARCHAR(10) | NOT NULL | **Business Key** (code INSEE ou postal) |
| `nom_lieu` | VARCHAR(100) | - | Nom du lieu |
| `code_postal` | VARCHAR(10) | - | Code postal |
| `ville` | VARCHAR(100) | - | Commune |
| `departement` | VARCHAR(3) | - | Département (01-95, 2A, 2B) |
| `region` | VARCHAR(100) | - | Région (13 régions + Outre-mer) |
| `pays` | VARCHAR(2) | - | Code pays (FR par défaut) |
| `type_lieu` | VARCHAR(50) | - | Patient/Hospitalisation/Deces/Etablissement |
| `latitude` | DECIMAL(10,8) | - | Coordonnées GPS (si disponible) |
| `longitude` | DECIMAL(11,8) | - | Coordonnées GPS (si disponible) |
| `date_chargement` | TIMESTAMP | DEFAULT NOW() | Date de création |

#### Contrainte

- `UNIQUE(code_lieu, type_lieu)` : Même code peut exister pour différents types

#### Index

- `PRIMARY KEY` : `sk_localisation`
- `UNIQUE` : `code_lieu + type_lieu`
- `INDEX` : `code_lieu`, `region`, `type_lieu`

#### Régions (13 + Outre-mer + Corse)

- Île-de-France
- Provence-Alpes-Côte d'Azur
- Auvergne-Rhône-Alpes
- Nouvelle-Aquitaine
- Occitanie
- Hauts-de-France
- Normandie
- Grand Est
- Bourgogne-Franche-Comté
- Pays de la Loire
- Bretagne
- Centre-Val de Loire
- **Corse** (2A Corse-du-Sud, 2B Haute-Corse)
- **Outre-mer** (971-976)

#### Exemple

```sql
sk_localisation | code_lieu | nom_lieu | code_postal | ville | departement | region      | type_lieu
----------------|-----------|----------|-------------|-------|-------------|-------------|----------
-1              | INCONNU   | Inconnu  | NULL        | NULL  | NULL        | Non renseigne| Inconnu
1               | 75001     | Paris 1er| 75001       | Paris | 75          | Ile-de-France| Patient
2               | 20000     | Ajaccio  | 20000       | Ajaccio| 2A         | Corse       | Deces
```

---

### 8. `dim_mutuelle` - Dimension Mutuelle/Assurance

**Description** : Organismes de protection sociale

**Type SCD** : Type 1 (pas d'historisation)

**Alimentation** : Mensuelle

**Volumétrie** : 255 lignes

#### Structure

| Colonne | Type | Contrainte | Description |
|---------|------|------------|-------------|
| `sk_mutuelle` | BIGSERIAL | PRIMARY KEY | **Clé substitut** |
| `id_mut` | INT | UNIQUE NOT NULL | **Business Key** (ID mutuelle source) |
| `nom_mutuelle` | VARCHAR(255) | - | Nom de la mutuelle |
| `adresse` | VARCHAR(255) | - | Adresse siège social |
| `type_mutuelle` | VARCHAR(50) | - | **Classification** : CMU/Assurance/Mutuelle/Autre |
| `date_chargement` | TIMESTAMP | DEFAULT NOW() | Date de création |

#### Index

- `PRIMARY KEY` : `sk_mutuelle`
- `UNIQUE` : `id_mut`
- `INDEX` : `id_mut`

#### Classification Automatique

Basée sur le nom :
- **CMU** : si nom contient "CMU"
- **Assurance** : si "ASSURANCE"
- **Mutuelle** : si "MUTUELLE"
- **Autre** : par défaut

#### Exemple

```sql
sk_mutuelle | id_mut | nom_mutuelle         | type_mutuelle | adresse
------------|--------|----------------------|---------------|--------
-1          | -1     | Aucune mutuelle      | Autre         | NULL
1           | 12     | CMU-C Complémentaire | CMU           | Paris
2           | 45     | Mutuelle AXA Santé   | Mutuelle      | Lyon
3           | 78     | Assurance Maladie    | Assurance     | Marseille
```

---

## ⭐ FAITS (Tables de Mesures)

### 1. `fait_consultation` - Fait Consultation Médicale

**Description** : Consultations médicales au CHU

**Grain** : **1 ligne = 1 consultation**

**Alimentation** : Quotidienne (incrémental)

**Volumétrie** : ~1,027,000 lignes

#### Structure

| Colonne | Type | Contrainte | Description |
|---------|------|------------|-------------|
| `sk_fait_consultation` | BIGSERIAL | PRIMARY KEY | Clé technique |
| **Clés Étrangères (FK)** ||||
| `sk_patient` | BIGINT | NOT NULL, FK → dim_patient | Patient ayant consulté |
| `sk_professionnel` | BIGINT | NOT NULL, FK → dim_professionnel | Professionnel consulté |
| `sk_diagnostic` | BIGINT | NOT NULL, FK → dim_diagnostic | Diagnostic posé |
| `sk_mutuelle` | BIGINT | FK → dim_mutuelle | Mutuelle du patient |
| `sk_temps` | BIGINT | NOT NULL, FK → dim_temps | Date de la consultation |
| **Dimensions Dégénérées** ||||
| `num_consultation` | INT | - | Numéro consultation (business key) |
| `heure_debut` | TIME | - | Heure début consultation |
| `heure_fin` | TIME | - | Heure fin consultation |
| `motif` | VARCHAR(255) | - | Motif de consultation |
| **Mesures (Métriques)** ||||
| `duree_consultation` | INT | - | **MESURE** : Durée en minutes |
| `nombre_consultations` | INT | DEFAULT 1 | **MESURE** : Compteur (= 1) |
| `date_chargement` | TIMESTAMP | DEFAULT NOW() | Date de chargement |

#### Index

- `PRIMARY KEY` : `sk_fait_consultation`
- `INDEX` : `sk_patient`, `sk_professionnel`, `sk_diagnostic`, `sk_temps`

#### Business Rules

- ✅ FK NULL → -1 (Inconnu)
- ✅ `nombre_consultations = 1` (compteur pour SUM)
- ✅ Mesures **additives** (SUM possible)

#### Requêtes Analytiques

```sql
-- Top 10 spécialités par nombre de consultations
SELECT 
    s.categorie,
    SUM(fc.nombre_consultations) AS nb_consultations,
    AVG(fc.duree_consultation) AS duree_moyenne_min
FROM fait_consultation fc
JOIN dim_professionnel p ON fc.sk_professionnel = p.sk_professionnel AND p.est_actuel = TRUE
JOIN dim_specialite s ON p.fk_specialite = s.sk_specialite
GROUP BY s.categorie
ORDER BY nb_consultations DESC
LIMIT 10;
```

---

### 2. `fait_hospitalisation` - Fait Hospitalisation

**Description** : Séjours hospitaliers au CHU

**Grain** : **1 ligne = 1 hospitalisation**

**Alimentation** : Mensuelle

**Volumétrie** : ~2,500 lignes

#### Structure

| Colonne | Type | Contrainte | Description |
|---------|------|------------|-------------|
| `sk_fait_hospitalisation` | BIGSERIAL | PRIMARY KEY | Clé technique |
| **Clés Étrangères (FK)** ||||
| `sk_patient` | BIGINT | NOT NULL, FK → dim_patient | Patient hospitalisé |
| `sk_etablissement` | BIGINT | NOT NULL, FK → dim_etablissement | Établissement d'hospitalisation |
| `sk_diagnostic` | BIGINT | NOT NULL, FK → dim_diagnostic | Diagnostic principal |
| `sk_temps` | BIGINT | NOT NULL, FK → dim_temps | Date d'admission |
| `sk_localisation` | BIGINT | NOT NULL, FK → dim_localisation | Lieu de l'établissement |
| **Dimensions Dégénérées** ||||
| `num_hospitalisation` | INT | - | Numéro hospitalisation (business key) |
| **Mesures (Métriques)** ||||
| `jour_hospitalisation` | INT | - | **MESURE** : Durée séjour en jours (DMS) |
| `nombre_hospitalisations` | INT | DEFAULT 1 | **MESURE** : Compteur (= 1) |
| `date_chargement` | TIMESTAMP | DEFAULT NOW() | Date de chargement |

#### Index

- `PRIMARY KEY` : `sk_fait_hospitalisation`
- `INDEX` : `sk_patient`, `sk_etablissement`, `sk_diagnostic`, `sk_temps`, `sk_localisation`

#### Indicateurs Métier

- **DMS** (Durée Moyenne Séjour) : `AVG(jour_hospitalisation)`
- **Taux occupation** : Si données disponibles
- **Court séjour** : < 3 jours
- **Moyen séjour** : 3-7 jours
- **Long séjour** : > 7 jours

#### Requêtes Analytiques

```sql
-- DMS par région
SELECT 
    l.region,
    AVG(fh.jour_hospitalisation) AS dms,
    COUNT(*) AS nb_sejours
FROM fait_hospitalisation fh
JOIN dim_localisation l ON fh.sk_localisation = l.sk_localisation
GROUP BY l.region
ORDER BY dms DESC;
```

---

### 3. `fait_deces` - Fait Décès

**Description** : Décès en France (INSEE)

**Grain** : **1 ligne = 1 décès**

**Alimentation** : Annuelle

**Volumétrie** : ~25,088,000 lignes ⚠️ **GROS VOLUME**

#### Structure

| Colonne | Type | Contrainte | Description |
|---------|------|------------|-------------|
| `sk_fait_deces` | BIGSERIAL | PRIMARY KEY | Clé technique |
| **Clés Étrangères (FK)** ||||
| `sk_patient` | BIGINT | FK → dim_patient | Patient décédé (peut être NULL si non matché) |
| `sk_localisation` | BIGINT | NOT NULL, FK → dim_localisation | Lieu du décès |
| `sk_temps` | BIGINT | NOT NULL, FK → dim_temps | Date du décès |
| **Dimensions Dégénérées** ||||
| `code_lieu_deces` | VARCHAR(10) | - | Code INSEE lieu décès |
| `numero_acte_deces` | VARCHAR(20) | - | Numéro acte de décès |
| **Mesures (Métriques)** ||||
| `age_deces` | INT | - | **MESURE** : Âge au moment du décès |
| `nombre_deces` | INT | DEFAULT 1 | **MESURE** : Compteur (= 1) |
| `date_chargement` | TIMESTAMP | DEFAULT NOW() | Date de chargement |

#### Index

- `PRIMARY KEY` : `sk_fait_deces`
- `INDEX` : `sk_patient`, `sk_localisation`, `sk_temps`

#### Business Rules

- ⚠️ `sk_patient` **peut être NULL** (décès non matché avec patients CHU)
- ✅ Tous les décès INSEE présents (même hors CHU)
- ✅ Matching fuzzy sur nom/prénom/date_naissance

#### Requêtes Analytiques

```sql
-- Mortalité par région et tranche d'âge
SELECT 
    l.region,
    p.tranche_age,
    COUNT(*) AS nb_deces,
    AVG(fd.age_deces) AS age_moyen
FROM fait_deces fd
JOIN dim_localisation l ON fd.sk_localisation = l.sk_localisation
LEFT JOIN dim_patient p ON fd.sk_patient = p.sk_patient
GROUP BY l.region, p.tranche_age
ORDER BY l.region, p.tranche_age;
```

---

### 4. `fait_satisfaction` - Fait Satisfaction e-Satis

**Description** : Enquêtes de satisfaction patients (e-Satis 48h MCO)

**Grain** : **1 ligne = 1 établissement × 1 année**

**Alimentation** : Annuelle

**Volumétrie** : ~5,000 lignes

#### Structure

| Colonne | Type | Contrainte | Description |
|---------|------|------------|-------------|
| `sk_fait_satisfaction` | BIGSERIAL | PRIMARY KEY | Clé technique |
| **Clés Étrangères (FK)** ||||
| `sk_etablissement` | BIGINT | NOT NULL, FK → dim_etablissement | Établissement évalué |
| `sk_temps` | BIGINT | NOT NULL, FK → dim_temps | Année de l'enquête |
| `sk_localisation` | BIGINT | NOT NULL, FK → dim_localisation | Localisation établissement |
| **Mesures (Scores de Satisfaction)** ||||
| `score_global` | DECIMAL(5,2) | - | **MESURE** : Score global (/100) |
| `score_accueil` | DECIMAL(5,2) | - | **MESURE** : Score accueil (/100) |
| `score_pec_infirmiers` | DECIMAL(5,2) | - | **MESURE** : Score prise en charge infirmiers |
| `score_pec_medecins` | DECIMAL(5,2) | - | **MESURE** : Score prise en charge médecins |
| `score_chambre` | DECIMAL(5,2) | - | **MESURE** : Score chambre |
| `score_repas` | DECIMAL(5,2) | - | **MESURE** : Score repas |
| `score_sortie` | DECIMAL(5,2) | - | **MESURE** : Score organisation sortie |
| `taux_recommandation` | DECIMAL(5,2) | - | **MESURE** : % patients qui recommanderaient |
| `nombre_reponses` | INT | - | **MESURE** : Nombre de réponses exploitables |
| **Dimensions Dégénérées** ||||
| `classement` | VARCHAR(2) | - | A/B/C/D/DI (classes de satisfaction) |
| `evolution` | VARCHAR(10) | - | Évolution vs année précédente |
| `date_chargement` | TIMESTAMP | DEFAULT NOW() | Date de chargement |

#### Index

- `PRIMARY KEY` : `sk_fait_satisfaction`
- `INDEX` : `sk_etablissement`, `sk_temps`, `sk_localisation`

#### Requêtes Analytiques

```sql
-- Évolution satisfaction par région
SELECT 
    l.region,
    t.annee,
    AVG(fs.score_global) AS score_moyen,
    AVG(fs.taux_recommandation) AS taux_reco_moyen,
    COUNT(DISTINCT fs.sk_etablissement) AS nb_etablissements
FROM fait_satisfaction fs
JOIN dim_localisation l ON fs.sk_localisation = l.sk_localisation
JOIN dim_temps t ON fs.sk_temps = t.sk_temps
GROUP BY l.region, t.annee
ORDER BY l.region, t.annee;
```

---

### 5. `fait_qualite_soins` - Fait Qualité des Soins (IPAQSS)

**Description** : Indicateurs qualité et sécurité des soins

**Grain** : **1 ligne = 1 établissement × 1 année × 1 indicateur**

**Alimentation** : Annuelle

**Volumétrie** : ~3,000 lignes

#### Structure

| Colonne | Type | Contrainte | Description |
|---------|------|------------|-------------|
| `sk_fait_qualite` | BIGSERIAL | PRIMARY KEY | Clé technique |
| **Clés Étrangères (FK)** ||||
| `sk_etablissement` | BIGINT | NOT NULL, FK → dim_etablissement | Établissement évalué |
| `sk_temps` | BIGINT | NOT NULL, FK → dim_temps | Année de l'indicateur |
| `sk_localisation` | BIGINT | NOT NULL, FK → dim_localisation | Localisation établissement |
| **Mesures (Indicateurs IPAQSS)** ||||
| `ratio_ete_ortho` | DECIMAL(10,6) | - | **MESURE** : Ratio événements thrombo-emboliques (orthopédie) |
| `alerte_ete` | INT | - | **MESURE** : 0=Normal, 1=Alerte |
| `ratio_iso_ortho` | DECIMAL(10,6) | - | **MESURE** : Ratio infections site opératoire (orthopédie) |
| `alerte_iso` | INT | - | **MESURE** : 0=Normal, 1=Alerte |
| **Dimensions Dégénérées** ||||
| `evolution_ete` | VARCHAR(10) | - | Évolution indicateur ETE |
| `date_chargement` | TIMESTAMP | DEFAULT NOW() | Date de chargement |

#### Index

- `PRIMARY KEY` : `sk_fait_qualite`
- `INDEX` : `sk_etablissement`, `sk_temps`, `sk_localisation`

#### Indicateurs IPAQSS

- **ETE** : Événements Thrombo-Emboliques
- **ISO** : Infections Site Opératoire
- **Alertes** : Si ratio > seuil critique

#### Requêtes Analytiques

```sql
-- Établissements en alerte qualité
SELECT 
    e.nom_etablissement,
    e.region,
    t.annee,
    fq.ratio_ete_ortho,
    fq.alerte_ete,
    fq.ratio_iso_ortho,
    fq.alerte_iso
FROM fait_qualite_soins fq
JOIN dim_etablissement e ON fq.sk_etablissement = e.sk_etablissement
JOIN dim_temps t ON fq.sk_temps = t.sk_temps
WHERE fq.alerte_ete = 1 OR fq.alerte_iso = 1
ORDER BY t.annee DESC, e.region;
```

---

## 📊 VUES ANALYTIQUES

### 1. `v_analyse_consultations`

**Description** : Vue agrégée des consultations par profil patient et spécialité

**Grain** : Sexe × Tranche_age × Profession × Diagnostic × Année × Mois

```sql
CREATE VIEW v_analyse_consultations AS
SELECT 
    p.sexe,
    p.tranche_age,
    prof.profession,
    d.categorie_cim10,
    t.annee,
    t.mois,
    COUNT(fc.nombre_consultations) AS nb_consultations,
    AVG(fc.duree_consultation) AS duree_moyenne_min
FROM fait_consultation fc
JOIN dim_patient p ON fc.sk_patient = p.sk_patient
JOIN dim_professionnel prof ON fc.sk_professionnel = prof.sk_professionnel
JOIN dim_diagnostic d ON fc.sk_diagnostic = d.sk_diagnostic
JOIN dim_temps t ON fc.sk_temps = t.sk_temps
GROUP BY p.sexe, p.tranche_age, prof.profession, d.categorie_cim10, t.annee, t.mois;
```

---

### 2. `v_analyse_hospitalisations`

**Description** : Vue agrégée des hospitalisations par profil et région

**Grain** : Sexe × Tranche_age × Type_etablissement × Région × Diagnostic × Année

```sql
CREATE VIEW v_analyse_hospitalisations AS
SELECT 
    p.sexe,
    p.tranche_age,
    e.type_etablissement,
    e.region,
    d.categorie_cim10,
    t.annee,
    COUNT(fh.nombre_hospitalisations) AS nb_hospitalisations,
    AVG(fh.jour_hospitalisation) AS duree_moyenne_sejour
FROM fait_hospitalisation fh
JOIN dim_patient p ON fh.sk_patient = p.sk_patient
JOIN dim_etablissement e ON fh.sk_etablissement = e.sk_etablissement
JOIN dim_diagnostic d ON fh.sk_diagnostic = d.sk_diagnostic
JOIN dim_temps t ON fh.sk_temps = t.sk_temps
GROUP BY p.sexe, p.tranche_age, e.type_etablissement, e.region, d.categorie_cim10, t.annee;
```

---

### 3. `v_analyse_deces`

**Description** : Vue agrégée des décès par région et période

**Grain** : Région × Année × Mois

```sql
CREATE VIEW v_analyse_deces AS
SELECT 
    l.region,
    t.annee,
    t.mois,
    COUNT(fd.nombre_deces) AS nb_deces,
    AVG(fd.age_deces) AS age_moyen_deces
FROM fait_deces fd
JOIN dim_localisation l ON fd.sk_localisation = l.sk_localisation
JOIN dim_temps t ON fd.sk_temps = t.sk_temps
GROUP BY l.region, t.annee, t.mois;
```

---

### 4. `v_analyse_satisfaction`

**Description** : Vue agrégée de la satisfaction par région et type d'établissement

**Grain** : Région × Type_etablissement × Année

```sql
CREATE VIEW v_analyse_satisfaction AS
SELECT 
    l.region,
    e.type_etablissement,
    t.annee,
    AVG(fs.score_global) AS score_moyen_global,
    AVG(fs.taux_recommandation) AS taux_reco_moyen,
    COUNT(DISTINCT e.sk_etablissement) AS nb_etablissements
FROM fait_satisfaction fs
JOIN dim_etablissement e ON fs.sk_etablissement = e.sk_etablissement
JOIN dim_localisation l ON fs.sk_localisation = l.sk_localisation
JOIN dim_temps t ON fs.sk_temps = t.sk_temps
GROUP BY l.region, e.type_etablissement, t.annee;
```

---

## 🔗 Diagramme de Relations

```
                    dim_temps
                        │
        ┌───────────────┼───────────────┐
        │               │               │
    dim_patient    dim_diagnostic  dim_mutuelle
        │               │               │
        └───────────┬───┴───┬───────────┘
                    │       │
              fait_consultation
                    │
        ┌───────────┴───────────┐
        │                       │
    dim_professionnel      dim_specialite
        │
        └─────────── fk_specialite


                    dim_temps
                        │
        ┌───────────────┼───────────────────┐
        │               │                   │
    dim_patient    dim_diagnostic   dim_etablissement
        │               │                   │
        │               │           dim_localisation
        └───────────┬───┴───────────┬───────┘
                    │               │
              fait_hospitalisation
              
              
                    dim_temps
                        │
        ┌───────────────┼───────────────┐
        │               │               │
    dim_patient  dim_localisation     │
        │               │               │
        └───────────────┴───────────────┘
                        │
                   fait_deces
                   

                    dim_temps
                        │
        ┌───────────────┼───────────────┐
        │               │               │
dim_etablissement  dim_localisation    │
        └───────────────┴───────────────┘
                        │
                 fait_satisfaction
                 

                    dim_temps
                        │
        ┌───────────────┼───────────────┐
        │               │               │
dim_etablissement  dim_localisation    │
        └───────────────┴───────────────┘
                        │
               fait_qualite_soins
```

---

## 📈 Volumétrie Détaillée

### Dimensions

| Table | Lignes | Taille Estimée | Croissance |
|-------|--------|----------------|------------|
| `dim_patient` | 100,001 | ~15 MB | +5K/mois |
| `dim_professionnel` | 1,048,575 | ~120 MB | +10K/mois |
| `dim_specialite` | 94 | ~10 KB | Stable |
| `dim_diagnostic` | 15,491 | ~2 MB | Stable |
| `dim_etablissement` | 201 | ~50 KB | Stable |
| `dim_localisation` | 39,724 | ~5 MB | +1K/mois |
| `dim_temps` | 5,845 | ~500 KB | Stable (2015-2030) |
| `dim_mutuelle` | 255 | ~20 KB | +5/mois |
| **TOTAL DIMS** | **~1.2M** | **~142 MB** | - |

### Faits

| Table | Lignes | Taille Estimée | Croissance |
|-------|--------|----------------|------------|
| `fait_consultation` | 2,030,131 | ~250 MB | +50K/jour |
| `fait_hospitalisation` | 4,919 | ~1 MB | +500/mois |
| `fait_deces` | 25,088,000 | ~2.5 GB | +500K/an |
| `fait_satisfaction` | ~5,000 | ~500 KB | +500/an |
| `fait_qualite_soins` | ~3,000 | ~300 KB | +300/an |
| **TOTAL FAITS** | **~27M** | **~2.75 GB** | - |

### TOTAL DWH

**Volumétrie totale** : ~28M lignes, ~3 GB

---

## 🔑 Conventions de Nommage

### Clés

| Préfixe | Type | Exemple | Description |
|---------|------|---------|-------------|
| `sk_*` | Clé substitut | `sk_patient` | Clé technique auto-générée (PRIMARY KEY) |
| `fk_*` | Clé étrangère | `fk_specialite` | Référence vers autre dimension |
| `id_*` | Business key | `id_patient` | Clé métier source (UNIQUE) |
| `code_*` | Code métier | `code_diagnostic` | Code normalisé (CIM-10, FINESS, etc.) |

### Tables

| Préfixe | Type | Exemple |
|---------|------|---------|
| `dim_*` | Dimension | `dim_patient` |
| `fait_*` | Fait | `fait_consultation` |
| `v_*` | Vue | `v_analyse_consultations` |

---

## 📋 Checklist Conformité DWH

### ✅ Dimensions

- [ ] Toutes ont une clé substitut `sk_*`
- [ ] Toutes ont une business key UNIQUE
- [ ] Toutes ont une ligne "Inconnu" (sk = -1)
- [ ] Types de données corrects
- [ ] Index sur business key
- [ ] Commentaires présents

### ✅ Faits

- [ ] Toutes ont des FK vers dimensions
- [ ] Grain clairement défini
- [ ] Mesures additives (SUM possible)
- [ ] Pas d'informations qui changent (utiliser FK)
- [ ] Index sur toutes les FK
- [ ] Commentaires sur mesures

---

## 📚 Utilisation

### Requêtes d'Analyse Types

```sql
-- 1. Consultations par spécialité et période
SELECT 
    s.categorie,
    t.annee,
    t.trimestre,
    COUNT(*) AS nb_consultations,
    AVG(fc.duree_consultation) AS duree_moyenne
FROM fait_consultation fc
JOIN dim_professionnel p ON fc.sk_professionnel = p.sk_professionnel AND p.est_actuel = TRUE
JOIN dim_specialite s ON p.fk_specialite = s.sk_specialite
JOIN dim_temps t ON fc.sk_temps = t.sk_temps
GROUP BY s.categorie, t.annee, t.trimestre;

-- 2. DMS (Durée Moyenne Séjour) par établissement
SELECT 
    e.nom_etablissement,
    e.type_etablissement,
    e.region,
    AVG(fh.jour_hospitalisation) AS dms,
    COUNT(*) AS nb_sejours
FROM fait_hospitalisation fh
JOIN dim_etablissement e ON fh.sk_etablissement = e.sk_etablissement
GROUP BY e.nom_etablissement, e.type_etablissement, e.region
HAVING COUNT(*) > 10  -- Minimum 10 séjours
ORDER BY dms DESC;

-- 3. Mortalité par région et âge
SELECT 
    l.region,
    CASE 
        WHEN fd.age_deces < 18 THEN '0-18'
        WHEN fd.age_deces BETWEEN 19 AND 65 THEN '19-65'
        ELSE '66+'
    END AS tranche_age_deces,
    COUNT(*) AS nb_deces,
    AVG(fd.age_deces) AS age_moyen
FROM fait_deces fd
JOIN dim_localisation l ON fd.sk_localisation = l.sk_localisation
GROUP BY l.region, tranche_age_deces
ORDER BY l.region, tranche_age_deces;

-- 4. Top 10 établissements satisfaction
SELECT 
    e.nom_etablissement,
    e.region,
    AVG(fs.score_global) AS score_moyen,
    AVG(fs.taux_recommandation) AS taux_reco
FROM fait_satisfaction fs
JOIN dim_etablissement e ON fs.sk_etablissement = e.sk_etablissement
GROUP BY e.nom_etablissement, e.region
ORDER BY score_moyen DESC
LIMIT 10;
```

---

## 🔒 Sécurité et RGPD

### Données Anonymisées

| Table | Colonnes Sensibles | Méthode |
|-------|-------------------|---------|
| `dim_patient` | `nom`, `prenom`, `num_secu` | SHA-256 (hash irréversible) |
| `dim_professionnel` | `nom`, `prenom` | SHA-256 (hash irréversible) |

### Hachage SHA-256

```sql
-- Exemple
Nom original : "DUPONT"
Hash SHA-256 : "a3f2d1c8f4e6b9a7..." (64 caractères)
Tronqué (8 car) : "a3f2d1c8"

-- Propriétés
✅ Irréversible (impossible de retrouver le nom)
✅ Déterministe (même nom = même hash)
✅ Collision quasi-impossible
✅ Conforme RGPD (pseudonymisation)
```

---

## 📚 Glossaire

| Terme | Définition |
|-------|------------|
| **Clé substitut (sk_*)** | Clé technique auto-générée, sans signification métier, utilisée comme PRIMARY KEY |
| **Business key** | Clé métier source (ID original), UNIQUE mais pas PRIMARY KEY |
| **SCD Type 1** | Slowly Changing Dimension Type 1 : mise à jour directe (écrase les anciennes valeurs) |
| **SCD Type 2** | Slowly Changing Dimension Type 2 : historisation complète (nouvelle ligne pour chaque changement) |
| **Grain** | Niveau de détail d'un fait (ex: 1 ligne = 1 consultation) |
| **Mesure** | Métrique numérique additive (COUNT, SUM, AVG possible) |
| **Dimension dégénérée** | Attribut descriptif stocké dans le fait (pas dans une dimension séparée) |
| **FK** | Foreign Key (clé étrangère vers une dimension) |
| **DMS** | Durée Moyenne de Séjour (indicateur hospitalier) |
| **CIM-10** | Classification Internationale des Maladies (10e révision) |
| **FINESS** | Fichier National des Établissements Sanitaires et Sociaux |
| **RPPS** | Répertoire Partagé des Professionnels de Santé |
| **ADELI** | Automatisation Des Listes (identifiant professionnel) |
| **IPAQSS** | Indicateurs Pour l'Amélioration de la Qualité et de la Sécurité des Soins |

---

**Auteur** : Équipe Big Data Groupe 3  
**Version** : 1.0  
**Date** : 2025-10-21  
**Basé sur** : `db.sql` (schéma cible PostgreSQL)

