-- ============================================
-- ODS DuckDB - CLEANED DATA (données nettoyées)
-- Données transformées et prêtes pour le DWH
-- ============================================

-- Schéma: clean = données nettoyées
CREATE SCHEMA IF NOT EXISTS clean;
CREATE SCHEMA IF NOT EXISTS metadata;

-- Table de tracking
CREATE TABLE IF NOT EXISTS metadata.transform_history (
    transform_id INTEGER PRIMARY KEY,
    model_name VARCHAR,
    transform_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    row_count INTEGER,
    status VARCHAR
);

-- ============================================
-- TABLES CLEANED - Données nettoyées via dbt
-- ============================================

-- Cleaned Patients
CREATE TABLE IF NOT EXISTS clean.patients (
    patient_key VARCHAR PRIMARY KEY,
    patient_id INTEGER,
    nom_complet VARCHAR,
    date_naissance DATE,
    age INTEGER,
    sexe VARCHAR(10),
    code_postal VARCHAR,
    ville VARCHAR,
    departement VARCHAR,
    region VARCHAR,
    est_actif BOOLEAN,
    date_chargement TIMESTAMP
);

-- Cleaned Consultations
CREATE TABLE IF NOT EXISTS clean.consultations (
    consultation_key VARCHAR PRIMARY KEY,
    consultation_id INTEGER,
    patient_id INTEGER,
    professionnel_id INTEGER,
    etablissement_id INTEGER,
    diagnostic_id INTEGER,
    date_consultation DATE,
    annee INTEGER,
    mois INTEGER,
    jour INTEGER,
    duree_minutes INTEGER,
    cout DECIMAL(10,2),
    date_chargement TIMESTAMP
);

-- Cleaned Hospitalisations
CREATE TABLE IF NOT EXISTS clean.hospitalisations (
    hospitalisation_key VARCHAR PRIMARY KEY,
    hospitalisation_id INTEGER,
    patient_id INTEGER,
    etablissement_id INTEGER,
    diagnostic_id INTEGER,
    date_entree DATE,
    date_sortie DATE,
    duree_sejour INTEGER,
    cout_total DECIMAL(10,2),
    service VARCHAR,
    annee INTEGER,
    mois INTEGER,
    date_chargement TIMESTAMP
);

-- Cleaned Établissements
CREATE TABLE IF NOT EXISTS clean.etablissements (
    etablissement_key VARCHAR PRIMARY KEY,
    etablissement_id INTEGER,
    nom VARCHAR,
    type_etablissement VARCHAR,
    ville VARCHAR,
    departement VARCHAR,
    region VARCHAR,
    capacite_lits INTEGER,
    date_chargement TIMESTAMP
);

-- Cleaned Satisfaction
CREATE TABLE IF NOT EXISTS clean.satisfaction (
    satisfaction_key VARCHAR PRIMARY KEY,
    satisfaction_id INTEGER,
    etablissement_id INTEGER,
    date_evaluation DATE,
    score_global INTEGER,
    annee INTEGER,
    date_chargement TIMESTAMP
);

-- Cleaned Décès
CREATE TABLE IF NOT EXISTS clean.deces (
    deces_key VARCHAR PRIMARY KEY,
    deces_id INTEGER,
    patient_id INTEGER,
    date_deces DATE,
    age INTEGER,
    sexe VARCHAR(10),
    region_deces VARCHAR,
    annee INTEGER,
    date_chargement TIMESTAMP
);

-- Cleaned Professionnels
CREATE TABLE IF NOT EXISTS clean.professionnels (
    professionnel_key VARCHAR PRIMARY KEY,
    professionnel_id INTEGER,
    nom_complet VARCHAR,
    specialite VARCHAR,
    categorie VARCHAR,
    date_chargement TIMESTAMP
);

-- Cleaned Diagnostics
CREATE TABLE IF NOT EXISTS clean.diagnostics (
    diagnostic_key VARCHAR PRIMARY KEY,
    diagnostic_id INTEGER,
    code_diagnostic VARCHAR,
    libelle VARCHAR,
    categorie VARCHAR,
    date_chargement TIMESTAMP
);

-- Vue de vérification
CREATE OR REPLACE VIEW metadata.data_quality_check AS
SELECT 'patients' as table_name, COUNT(*) as row_count FROM clean.patients
UNION ALL SELECT 'consultations', COUNT(*) FROM clean.consultations
UNION ALL SELECT 'hospitalisations', COUNT(*) FROM clean.hospitalisations
UNION ALL SELECT 'etablissements', COUNT(*) FROM clean.etablissements
UNION ALL SELECT 'satisfaction', COUNT(*) FROM clean.satisfaction
UNION ALL SELECT 'deces', COUNT(*) FROM clean.deces
UNION ALL SELECT 'professionnels', COUNT(*) FROM clean.professionnels
UNION ALL SELECT 'diagnostics', COUNT(*) FROM clean.diagnostics;

SELECT 'ODS (cleaned data) initialise avec succes!' as status;