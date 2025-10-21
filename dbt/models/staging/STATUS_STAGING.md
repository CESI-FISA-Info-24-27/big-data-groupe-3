# Status Staging - Phase 1 RÉVISÉE ✅

**Dernière mise à jour** : 2025-10-13

## 📊 Résumé

**16 modèles staging créés et révisés** couvrant les tables principales pour alimenter le DWH.

**Volume total** : 30M+ lignes nettoyées et standardisées.

**Modifications apportées** :
- ✅ stg_specialites.sql **REFAIT** avec classification catégorie
- ✅ stg_patient.sql **CORRIGÉ** (parsing dates robuste, cast Poid/Taille)
- ✅ stg_etablissement_sante.sql **AMÉLIORÉ** (gestion Corse 2A/2B)
- ✅ stg_laboratoire.sql **CORRIGÉ** (extraction explicite colonnes)
- ✅ stg_salle.sql **CORRIGÉ** (extraction explicite colonnes)
- ❌ stg_date.sql **SUPPRIMÉ** (table raw.date inutilisable)

---

## ✅ Modèles créés

### Core Business (PostgreSQL) - 12 modèles

| Modèle | Source | Lignes | Statut | Destination DWH |
|--------|--------|--------|--------|-----------------|
| ✅ `stg_patient` | `raw.patient` | 100k | **CORRIGÉ** | → dim_patient |
| ✅ `stg_professionnel_sante` | `raw.professionnel_de_sante` | 1M+ | **VÉRIFIÉ** | → dim_professionnel |
| ✅ `stg_consultation` | `raw.consultation` | 1M+ | ✅ OK | → fait_consultation |
| ✅ `stg_prescription` | `raw.prescription` | 2M+ | ✅ OK | → (enrichissement) |
| ✅ `stg_medicaments` | `raw.medicaments` | 15k | **VÉRIFIÉ** | → (référentiel) |
| ✅ `stg_diagnostic` | `raw.diagnostic` | 15k | ✅ OK | → dim_diagnostic |
| ✅ `stg_mutuelle` | `raw.mutuelle` | 254 | ✅ OK | → dim_mutuelle |
| ✅ `stg_adher` | `raw.adher` | 193k | ✅ OK | → (enrichissement patient) |
| ✅ `stg_specialites` | `raw.specialites` | 93 | **REFAIT** | → dim_specialite |
| ✅ `stg_salle` | `raw.salle` | 201k | **CORRIGÉ** | → (référentiel) |
| ✅ `stg_laboratoire` | `raw.laboratoire` | 677 | **CORRIGÉ** | → (référentiel) |
| ❌ ~~`stg_date`~~ | ~~`raw.date`~~ | ~~164k~~ | **SUPPRIMÉ** | ❌ Inutilisable |

### Décès (CSV) - 1 modèle

| Modèle | Source | Lignes | Statut | Destination DWH |
|--------|--------|--------|--------|-----------------|
| ✅ `stg_deces` | `raw.deces_en_france_deces` | 25M+ | ✅ OK | → fait_deces |

### Établissements (CSV) - 3 modèles

| Modèle | Source | Lignes | Statut | Destination DWH |
|--------|--------|--------|--------|-----------------|
| ✅ `stg_etablissement_sante` | `raw.etablissement_de_sante_etablissement_sante` | 416k | **AMÉLIORÉ** | → dim_etablissement |
| ✅ `stg_etablissement_professionnel` | `raw.etablissement_de_sante_professionnel_sante` | 1M+ | ✅ OK | → (ODS professionnel) |
| ✅ `stg_etablissement_activite` | `raw.etablissement_de_sante_activite_professionnel_sante` | 1.8M+ | ✅ OK | → (ODS professionnel) |

### Hospitalisations (CSV) - 1 modèle

| Modèle | Source | Lignes | Statut | Destination DWH |
|--------|--------|--------|--------|-----------------|
| ✅ `stg_hospitalisation` | `raw.hospitalisation_hospitalisations` | 2.5k | ✅ OK | → fait_hospitalisation |

---

## 🔄 Transformations appliquées

### Nettoyage standard (tous les modèles)

- ✅ **TRIM** : Suppression espaces superflus
- ✅ **UPPER** : Standardisation casse (noms, codes)
- ✅ **CAST** : Types de données corrects
- ✅ **Filtrage NULL** : Suppression lignes sans business key
- ✅ **Timestamp** : `loaded_at` ajouté partout

### Transformations métier détaillées

#### `stg_patient` ⭐ **CORRIGÉ**

**Problème identifié** :
- Date en VARCHAR dans raw (format mixte "4/6/1980" ou "7/25/2013")
- Poid en VARCHAR (contient "54.3")
- Taille en VARCHAR (contient "162")

**Corrections apportées** :
```sql
-- Parsing robuste des dates (multi-format)
coalesce(
    try_strptime("Date", '%m/%d/%Y'),
    try_strptime("Date", '%d/%m/%Y'),
    try_cast("Date" as date)
) as date_naissance

-- Cast explicites
try_cast("Poid" as decimal(5,2)) as poids
try_cast("Taille" as integer) as taille
```

- ✅ Calcul `age` depuis date_naissance
- ✅ Classification `tranche_age` (0-18, 19-30, 31-50, 51-65, 66+)
- ✅ Pays par défaut = 'FR'
- ✅ Préparation pseudonymisation num_secu

#### `stg_professionnel_sante` ✅ **VÉRIFIÉ**

- ✅ Contient bien les 8 colonnes dont `code_specialite`
- ✅ Standardisation civilité, nom, prénom
- ✅ Préparation SCD Type 2

#### `stg_specialites` ⭐ **REFAIT COMPLÈTEMENT**

**Avant** : ❌ Faisait juste `SELECT *`

**Maintenant** : ✅ Nettoyage complet + classification

```sql
-- Nettoyage
trim(upper(Code_specialite)) as code_specialite
trim(Fonction) as fonction
trim(Specialite) as specialite

-- Classification automatique par catégorie
case
    when lower(Fonction) like '%medecin generaliste%' then 'Medecine generale'
    when lower(Fonction) like '%medecin%' and Specialite is not null then 'Medecine specialisee'
    when lower(Fonction) like '%infirmier%' then 'Soins infirmiers'
    when lower(Fonction) like '%kinesitherapeute%' then 'Reeducation'
    when lower(Fonction) like '%osteopathe%' then 'Medecine alternative'
    when lower(Fonction) like '%dentiste%' then 'Dentaire'
    when lower(Fonction) like '%pharmacien%' then 'Pharmacie'
    when lower(Fonction) like '%psychologue%' then 'Sante mentale'
    when lower(Fonction) like '%radiologue%' then 'Imagerie medicale'
    -- ... 20+ catégories
    else 'Autre'
end as categorie
```

**Catégories supportées** : 30+ spécialités médicales identifiées

#### `stg_consultation` ✅ **OK**

- ✅ **Calcul automatique** `duree_consultation_minutes`
- ✅ Cast TIME pour heures
- ✅ Filtrage consultations complètes

#### `stg_hospitalisation` ✅ **OK**

- ✅ **Calcul automatique** `jour_hospitalisation` (durée séjour)
- ✅ Validation dates admission/sortie

#### `stg_deces` ✅ **OK**

- ✅ Nettoyage données sensibles (25M lignes)
- ✅ Parsing dates avec TRY_CAST
- ✅ Calcul age_deces
- ✅ Préparation matching avec patients

#### `stg_etablissement_sante` ⭐ **AMÉLIORÉ**

**Correction apportée** : Gestion Corse (2A/2B)

```sql
-- Département calculé (gérer Corse 2A/2B)
case
    when substring(trim(code_postal), 1, 2) = '20' and length(trim(code_postal)) >= 3 then
        case
            when try_cast(substring(trim(code_postal), 3, 1) as integer) < 2 then '2A'
            else '2B'
        end
    when length(trim(code_postal)) >= 2 then substring(trim(code_postal), 1, 2)
    else null
end as departement
```

- ✅ Extraction des 24 colonnes du schéma RAW
- ✅ **Calcul département** avec gestion Corse

#### `stg_mutuelle` ✅ **OK**

- ✅ **Classification automatique** type_mutuelle (CMU/Assurance/Mutuelle)

#### `stg_adher` ✅ **OK**

- ✅ **Calcul automatique** `statut_adhesion` (ACTIF/INACTIF)

#### `stg_diagnostic` ✅ **OK**

- ✅ **Extraction automatique** `categorie_cim10` (3 premiers caractères)
- ✅ Tag source_donnee

#### `stg_medicaments` ✅ **VÉRIFIÉ**

- ✅ Extraction des 12 colonnes
- ✅ Nettoyage tous champs VARCHAR
- ✅ Date AMM en VARCHAR (format source conservé)

#### `stg_laboratoire` ⭐ **CORRIGÉ**

**Avant** : ❌ Faisait `SELECT *`

**Maintenant** : ✅ Extraction explicite des 3 colonnes

```sql
cast(Id_labo as integer) as id_labo
trim(Laboratoire) as nom_laboratoire
coalesce(trim(Pays), 'NON RENSEIGNE') as pays
```

#### `stg_salle` ⭐ **CORRIGÉ**

**Avant** : ❌ Faisait `SELECT *`

**Maintenant** : ✅ Extraction explicite des 5 colonnes

```sql
trim(Id_salle) as id_salle
cast(Num_consultation as bigint) as num_consultation
trim(Code_bloc) as code_bloc
trim(Num_etage) as num_etage
trim(Num_salle) as num_salle
```

#### ~~`stg_date`~~ ❌ **SUPPRIMÉ**

**Raison** :
- Table raw.date contient seulement `date1` et `date2` en VARCHAR
- Format: "01/12/2018", "02/12/2018" sans signification métier claire
- Pas exploitable pour créer dim_temps
- dim_temps sera généré programmatiquement (2015-2030) dans la couche DWH

---

## 🧪 Tests DBT configurés

### Tests d'unicité (Business Keys)

- `stg_patient.id_patient`
- `stg_professionnel_sante.identifiant`
- `stg_consultation.num_consultation`
- `stg_medicaments.code_cis`
- `stg_diagnostic.code_diagnostic`
- `stg_mutuelle.id_mut`
- `stg_specialites.code_specialite` ⭐ **AJOUTÉ**
- `stg_salle.id_salle`
- `stg_laboratoire.id_labo` ⭐ **AJOUTÉ**
- `stg_etablissement_sante.finess_site`
- `stg_hospitalisation.num_hospitalisation`

### Tests de non-nullité (Clés étrangères)

- `stg_prescription`: id_consultation, code_cis
- `stg_adher`: id_patient, id_mut
- `stg_etablissement_professionnel`: identifiant, finess
- `stg_deces.date_deces`

---

## 📋 Tables satisfaction CSV - Stratégie

**31 tables satisfaction/qualité** ne sont **PAS** traitées dans STAGING.

**Raison** :
- Tables lexique = dictionnaires (NAME, LABEL) - pas de données métier
- Tables données = consolidation complexe nécessaire

**Traitement** :
- ✅ Consolidation directe dans **ODS** via :
  - `int_satisfaction_esatis48h.sql`
  - `int_satisfaction_esatisca.sql`
  - `ods_satisfaction_unifie.sql`
  - `ods_qualite_soins_unifie.sql`

---

## 🚀 Commandes pour tester

### Exécuter tous les modèles staging

```bash
cd dbt
dbt run --select tag:staging
```

### Exécuter par groupe

```bash
# Core business uniquement
dbt run --select stg_patient stg_professionnel_sante stg_consultation

# Établissements
dbt run --select stg_etablissement_*

# Dimensions de référence
dbt run --select stg_diagnostic stg_mutuelle stg_specialites

# Nouveaux modèles corrigés
dbt run --select stg_specialites stg_patient stg_laboratoire stg_salle
```

### Tester la qualité des données

```bash
# Tous les tests staging
dbt test --select tag:staging

# Tests d'un modèle spécifique
dbt test --select stg_specialites
```

---

## 📈 Volumétrie attendue dans staging.duckdb

| Table STAGING | Lignes attendues | Note |
|--------------|------------------|------|
| `stg_patient` | ~100,000 | Filtrage NULL sur id_patient |
| `stg_professionnel_sante` | ~1,048,000 | Filtrage NULL sur identifiant |
| `stg_consultation` | ~1,027,000 | Filtrage NULL sur clés |
| `stg_prescription` | ~2,007,000 | FK vers consultation |
| `stg_diagnostic` | ~15,490 | Référentiel CIM-10 |
| `stg_mutuelle` | 254 | Référentiel complet |
| `stg_adher` | ~193,000 | Relations patient-mutuelle |
| `stg_specialites` | 93 | Référentiel complet ⭐ |
| `stg_salle` | ~201,000 | Référentiel salles ⭐ |
| `stg_laboratoire` | 677 | Référentiel laboratoires ⭐ |
| `stg_medicaments` | ~15,455 | Référentiel médicaments |
| `stg_deces` | ~25,088,000 | Grosse table ! |
| `stg_hospitalisation` | ~2,500 | Petite table |
| `stg_etablissement_sante` | ~416,000 | Référentiel FINESS |
| `stg_etablissement_professionnel` | ~1,042,000 | Relations pro-établissement |
| `stg_etablissement_activite` | ~1,800,000 | Activités professionnels |

**Total** : ~30M+ lignes

---

## ✅ Prochaines étapes - Phase 2 : ODS

1. **ODS Patient** : Joindre `stg_patient` + `stg_mutuelle` + `stg_adher` ✅ FAIT
2. **ODS Professionnel** : Joindre `stg_professionnel_sante` + `stg_etablissement_professionnel` + `stg_specialites` ✅ FAIT
3. **ODS Consultation** : Enrichir consultations avec patient + professionnel + diagnostic ✅ FAIT
4. **ODS Hospitalisation** : Enrichir hospitalisations ✅ FAIT
5. **ODS Satisfaction** : UNION des 31 tables satisfaction CSV ✅ FAIT
6. **ODS Localisation** : Consolidation géographique multi-sources ✅ FAIT

---

## 📝 Notes techniques

### Compatibilité DuckDB

Les modèles staging utilisent des fonctions compatibles DuckDB :
- `date_part()` au lieu de `EXTRACT()`
- `substring()` au lieu de `SUBSTR()`
- `try_cast()` pour conversions sûres
- `try_strptime()` pour parsing dates
- `coalesce()` pour fallback
- `cast()` standard SQL

### Performance

- Modèles matérialisés en `table` (pas `view`) pour performance
- Filtrage précoce des lignes invalides (WHERE)
- Pas de jointures dans staging (principe 1:1 avec raw)

### Qualité

- ✅ **Aucun modèle ne fait `SELECT *` sans transformation**
- ✅ Toutes les colonnes explicitement extraites
- ✅ Types de données corrects
- ✅ Nettoyage appliqué (TRIM, UPPER, CAST)
- ✅ Business keys validées

### Documentation

- Tous les modèles documentés dans `schema.yml`
- Business keys identifiées
- Tests configurés
- Descriptions avec volumétrie

---

## ✨ Améliorations apportées

### Corrections majeures

1. ⭐ **stg_specialites** : Refait complètement avec 30+ catégories
2. ⭐ **stg_patient** : Parsing dates robuste + cast Poid/Taille
3. ⭐ **stg_etablissement_sante** : Gestion Corse 2A/2B
4. ⭐ **stg_laboratoire** : Extraction explicite colonnes
5. ⭐ **stg_salle** : Extraction explicite colonnes
6. ⭐ **stg_date** : Supprimé (inutilisable)

### Qualité du code

✅ **Respect des bonnes pratiques DBT**
- 1 modèle = 1 table raw
- Pas de jointures (réservées pour ODS)
- Nettoyage simple uniquement
- CTE (with) pour lisibilité
- Commentaires explicites
- **Pas de `SELECT *` sauvage**

✅ **Prêt pour production**
- Tests configurés
- Documentation complète
- Business keys validées
- Transformations documentées
- Types de données corrects

---

## 🎯 Prochaine phase : DWH (dimensions + faits)

Une fois STAGING validé :
1. Créer les 8 dimensions avec clés substituts (sk_*)
2. Créer les 5 tables de faits avec FK
3. Implémenter SCD Type 2 pour dim_professionnel
4. Générer dim_temps programmatiquement (2015-2030)
5. Créer les datamarts (vues agrégées)

**Voir** : `ANALYSE_CONFORMITE_DWH.md` et `PLAN_REVISION_STAGING.md`
