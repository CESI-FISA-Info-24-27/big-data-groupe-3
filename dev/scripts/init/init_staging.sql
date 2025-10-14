-- ============================================
-- STAGING DuckDB - RAW DATA (zone d'atterrissage)
-- Données brutes non transformées
-- ============================================

-- Schéma: raw = données brutes
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS metadata;

-- Table de tracking
CREATE TABLE IF NOT EXISTS metadata.load_history (
    history_id INTEGER PRIMARY KEY,
    load_id INTEGER,
    source_name VARCHAR,
    table_name VARCHAR,
    load_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    row_count INTEGER,
    status VARCHAR
);

-- ============================================
-- TABLES RAW - Copie exacte des sources
-- ============================================

-- Raw Patients (depuis Postgres)
CREATE TABLE IF NOT EXISTS raw.patients (
    patient_id INTEGER,
    nom VARCHAR,
    prenom VARCHAR,
    date_naissance DATE,
    sexe VARCHAR(1),
    adresse VARCHAR,
    code_postal VARCHAR,
    ville VARCHAR,
    departement VARCHAR,
    region VARCHAR,
    date_creation TIMESTAMP
);

-- Raw Consultations (depuis Postgres)
CREATE TABLE IF NOT EXISTS raw.consultations (
    consultation_id INTEGER,
    patient_id INTEGER,
    professionnel_id INTEGER,
    etablissement_id INTEGER,
    diagnostic_id INTEGER,
    date_consultation DATE,
    duree_minutes INTEGER,
    cout DECIMAL(10,2),
    date_creation TIMESTAMP
);

-- Raw Hospitalisations (depuis Postgres)
CREATE TABLE IF NOT EXISTS raw.hospitalisations (
    hospitalisation_id INTEGER,
    patient_id INTEGER,
    etablissement_id INTEGER,
    diagnostic_id INTEGER,
    date_entree DATE,
    date_sortie DATE,
    duree_sejour INTEGER,
    cout_total DECIMAL(10,2),
    service VARCHAR,
    date_creation TIMESTAMP
);

-- Raw Diagnostics (depuis Postgres)
CREATE TABLE IF NOT EXISTS raw.diagnostics (
    diagnostic_id INTEGER,
    code_diagnostic VARCHAR,
    libelle VARCHAR,
    categorie VARCHAR,
    date_creation TIMESTAMP
);

-- Raw Professionnels (depuis Postgres)
CREATE TABLE IF NOT EXISTS raw.professionnels (
    professionnel_id INTEGER,
    nom VARCHAR,
    prenom VARCHAR,
    specialite VARCHAR,
    categorie VARCHAR,
    etablissement_id INTEGER,
    date_creation TIMESTAMP
);

-- Raw Établissements (depuis CSV)
CREATE TABLE IF NOT EXISTS raw.etablissements (
    etablissement_id INTEGER,
    nom VARCHAR,
    type_etablissement VARCHAR,
    adresse VARCHAR,
    code_postal VARCHAR,
    ville VARCHAR,
    departement VARCHAR,
    region VARCHAR,
    capacite_lits INTEGER,
    date_ouverture DATE
);

-- Raw Satisfaction (depuis CSV)
CREATE TABLE IF NOT EXISTS raw.satisfaction (
    satisfaction_id INTEGER,
    patient_id INTEGER,
    etablissement_id INTEGER,
    date_evaluation DATE,
    score_accueil INTEGER,
    score_soins INTEGER,
    score_proprete INTEGER,
    score_global INTEGER,
    commentaire TEXT,
    date_creation TIMESTAMP
);

-- Raw Décès (depuis CSV)
CREATE TABLE IF NOT EXISTS raw.deces (
    deces_id INTEGER,
    patient_id INTEGER,
    nom VARCHAR,
    prenom VARCHAR,
    date_naissance DATE,
    date_deces DATE,
    age INTEGER,
    sexe VARCHAR(1),
    commune_deces VARCHAR,
    departement_deces VARCHAR,
    region_deces VARCHAR,
    cause_deces VARCHAR,
    date_creation TIMESTAMP
);

-- Index pour performance
CREATE INDEX IF NOT EXISTS idx_patients_id ON raw.patients(patient_id);
CREATE INDEX IF NOT EXISTS idx_consultations_patient ON raw.consultations(patient_id);
CREATE INDEX IF NOT EXISTS idx_consultations_date ON raw.consultations(date_consultation);
CREATE INDEX IF NOT EXISTS idx_hospitalisations_patient ON raw.hospitalisations(patient_id);
CREATE INDEX IF NOT EXISTS idx_hospitalisations_date ON raw.hospitalisations(date_entree);
CREATE INDEX IF NOT EXISTS idx_deces_patient ON raw.deces(patient_id);
CREATE INDEX IF NOT EXISTS idx_deces_date ON raw.deces(date_deces);

-- Vue de vérification
CREATE OR REPLACE VIEW metadata.data_quality_check AS
SELECT 'patients' as table_name, COUNT(*) as row_count, COUNT(DISTINCT patient_id) as unique_ids FROM raw.patients
UNION ALL SELECT 'consultations', COUNT(*), COUNT(DISTINCT consultation_id) FROM raw.consultations
UNION ALL SELECT 'hospitalisations', COUNT(*), COUNT(DISTINCT hospitalisation_id) FROM raw.hospitalisations
UNION ALL SELECT 'diagnostics', COUNT(*), COUNT(DISTINCT diagnostic_id) FROM raw.diagnostics
UNION ALL SELECT 'professionnels', COUNT(*), COUNT(DISTINCT professionnel_id) FROM raw.professionnels
UNION ALL SELECT 'etablissements', COUNT(*), COUNT(DISTINCT etablissement_id) FROM raw.etablissements
UNION ALL SELECT 'satisfaction', COUNT(*), COUNT(DISTINCT satisfaction_id) FROM raw.satisfaction
UNION ALL SELECT 'deces', COUNT(*), COUNT(DISTINCT deces_id) FROM raw.deces;

SELECT 'STAGING (raw data) initialise avec succes!' as status;