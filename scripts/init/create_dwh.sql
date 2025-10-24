-- ============================================
-- MLD COMPLET - PROJET CHU
-- Schéma en Constellation pour PostgreSQL
-- 5 Tables de FAITS + 8 Tables de DIMENSIONS
-- ============================================

-- ============================================
-- CRÉATION DU SCHÉMA DWH
-- ============================================

CREATE SCHEMA IF NOT EXISTS dwh;
CREATE SCHEMA IF NOT EXISTS datamart;
SET search_path TO dwh, public;

-- ============================================
-- SUPPRESSION DES TABLES (si elles existent)
-- ============================================

DROP TABLE IF EXISTS fait_qualite_soins CASCADE;
DROP TABLE IF EXISTS fait_satisfaction CASCADE;
DROP TABLE IF EXISTS fait_deces CASCADE;
DROP TABLE IF EXISTS fait_hospitalisation CASCADE;
DROP TABLE IF EXISTS fait_consultation CASCADE;

DROP TABLE IF EXISTS dim_specialite CASCADE;
DROP TABLE IF EXISTS dim_mutuelle CASCADE;
DROP TABLE IF EXISTS dim_temps CASCADE;
DROP TABLE IF EXISTS dim_localisation CASCADE;
DROP TABLE IF EXISTS dim_etablissement CASCADE;
DROP TABLE IF EXISTS dim_diagnostic CASCADE;
DROP TABLE IF EXISTS dim_professionnel CASCADE;
DROP TABLE IF EXISTS dim_patient CASCADE;

-- ============================================
-- CRÉATION DES TABLES DE DIMENSIONS
-- ============================================

-- --------------------------------------------
-- DIMENSION PATIENT (SCD Type 1)
-- --------------------------------------------
CREATE TABLE dim_patient (
    sk_patient BIGSERIAL PRIMARY KEY,
    id_patient INT UNIQUE NOT NULL,  -- Business Key
    nom_anonyme VARCHAR(50),
    prenom_anonyme VARCHAR(50),
    sexe VARCHAR(10),
    date_naissance DATE,
    age INT,
    tranche_age VARCHAR(20),  -- '0-18', '19-30', '31-50', '51-65', '66+'
    groupe_sanguin VARCHAR(3),
    poids DECIMAL(5,2),
    taille INT,
    code_postal VARCHAR(10),
    ville VARCHAR(100),
    pays VARCHAR(2),
    num_secu_hash VARCHAR(64),  -- SHA256 pseudonymisé
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date_modification TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_patient_id ON dim_patient(id_patient);
CREATE INDEX idx_patient_sexe_age ON dim_patient(sexe, tranche_age);

COMMENT ON TABLE dim_patient IS 'Dimension Patient - SCD Type 1 - Alimentation mensuelle';
COMMENT ON COLUMN dim_patient.sk_patient IS 'Surrogate Key (clé technique auto-générée)';
COMMENT ON COLUMN dim_patient.id_patient IS 'Business Key (clé métier source PostgreSQL)';


-- --------------------------------------------
-- DIMENSION SPECIALITE
-- --------------------------------------------
CREATE TABLE dim_specialite (
    sk_specialite BIGSERIAL PRIMARY KEY,
    code_specialite VARCHAR(10) UNIQUE NOT NULL,  -- Business Key
    fonction VARCHAR(100),
    specialite VARCHAR(100),
    categorie VARCHAR(50),  -- 'Médecine générale', 'Médecine spécialisée'
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_specialite_code ON dim_specialite(code_specialite);

COMMENT ON TABLE dim_specialite IS 'Dimension Spécialité médicale - Alimentation mensuelle';


-- --------------------------------------------
-- DIMENSION PROFESSIONNEL (SCD Type 2)
-- --------------------------------------------
CREATE TABLE dim_professionnel (
    sk_professionnel BIGSERIAL PRIMARY KEY,
    identifiant VARCHAR(20) NOT NULL,  -- RPPS/ADELI - Business Key
    civilite VARCHAR(10),
    nom_anonyme VARCHAR(50),
    prenom_anonyme VARCHAR(50),
    profession VARCHAR(100),
    categorie_professionnelle VARCHAR(50),
    fk_specialite BIGINT REFERENCES dim_specialite(sk_specialite),
    mode_exercice VARCHAR(20),  -- 'Libéral', 'Salarié'
    fk_organisation VARCHAR(20),  -- FINESS établissement
    date_debut_validite DATE NOT NULL,
    date_fin_validite DATE,  -- NULL si version actuelle
    est_actuel BOOLEAN DEFAULT TRUE,
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_professionnel_identifiant ON dim_professionnel(identifiant);
CREATE INDEX idx_professionnel_actuel ON dim_professionnel(est_actuel) WHERE est_actuel = TRUE;
CREATE INDEX idx_professionnel_organisation ON dim_professionnel(fk_organisation);

COMMENT ON TABLE dim_professionnel IS 'Dimension Professionnel de santé - SCD Type 2 - Alimentation mensuelle';
COMMENT ON COLUMN dim_professionnel.date_fin_validite IS 'NULL = version actuelle';


-- --------------------------------------------
-- DIMENSION DIAGNOSTIC
-- --------------------------------------------
CREATE TABLE dim_diagnostic (
    sk_diagnostic BIGSERIAL PRIMARY KEY,
    code_diagnostic VARCHAR(10) UNIQUE NOT NULL,  -- Code CIM-10 - Business Key
    libelle_diagnostic VARCHAR(255),
    categorie_cim10 VARCHAR(5),  -- 3 premiers caractères
    chapitre_cim10 VARCHAR(100),
    source_donnee VARCHAR(50),  -- 'PostgreSQL', 'Hospitalisation', 'Etablissement'
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_diagnostic_code ON dim_diagnostic(code_diagnostic);
CREATE INDEX idx_diagnostic_categorie ON dim_diagnostic(categorie_cim10);

COMMENT ON TABLE dim_diagnostic IS 'Dimension Diagnostic CIM-10 consolidée - Alimentation mensuelle';


-- --------------------------------------------
-- DIMENSION ETABLISSEMENT
-- --------------------------------------------
CREATE TABLE dim_etablissement (
    sk_etablissement BIGSERIAL PRIMARY KEY,
    finess VARCHAR(20) UNIQUE NOT NULL,  -- N° FINESS - Business Key
    finess_etablissement_juridique VARCHAR(20),
    finess_site VARCHAR(20),
    nom_etablissement VARCHAR(255),
    type_etablissement VARCHAR(50),  -- 'CH', 'Privé', 'PSPH/EBNL'
    categorie VARCHAR(100),
    region VARCHAR(100),
    departement VARCHAR(3),
    adresse VARCHAR(255),
    code_postal VARCHAR(10),
    ville VARCHAR(100),
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_etablissement_finess ON dim_etablissement(finess);
CREATE INDEX idx_etablissement_region ON dim_etablissement(region);

COMMENT ON TABLE dim_etablissement IS 'Dimension Établissement de santé - Alimentation mensuelle';


-- --------------------------------------------
-- DIMENSION LOCALISATION (Consolidée)
-- --------------------------------------------
CREATE TABLE dim_localisation (
    sk_localisation BIGSERIAL PRIMARY KEY,
    code_lieu VARCHAR(10) NOT NULL,  -- Code INSEE ou postal - Business Key
    nom_lieu VARCHAR(100),
    code_postal VARCHAR(10),
    ville VARCHAR(100),
    departement VARCHAR(3),
    region VARCHAR(100),
    pays VARCHAR(2),
    type_lieu VARCHAR(50),  -- 'Patient', 'Hospitalisation', 'Deces', 'Etablissement'
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(code_lieu, type_lieu)
);

CREATE INDEX idx_localisation_code ON dim_localisation(code_lieu);
CREATE INDEX idx_localisation_region ON dim_localisation(region);
CREATE INDEX idx_localisation_type ON dim_localisation(type_lieu);

COMMENT ON TABLE dim_localisation IS 'Dimension Localisation consolidée toutes sources - Alimentation mensuelle';


-- --------------------------------------------
-- DIMENSION TEMPS (Consolidée)
-- --------------------------------------------
CREATE TABLE dim_temps (
    sk_temps BIGINT PRIMARY KEY,  -- Format YYYYMMDD (ex: 20241207)
    date_complete DATE UNIQUE NOT NULL,  -- Business Key
    jour INT NOT NULL,
    mois INT NOT NULL,
    trimestre INT NOT NULL,
    semestre INT NOT NULL,
    annee INT NOT NULL,
    semaine_annee INT NOT NULL,
    jour_semaine INT NOT NULL,  -- 1=Lundi, 7=Dimanche
    nom_jour VARCHAR(10),
    nom_mois VARCHAR(20),
    est_weekend BOOLEAN,
    est_ferie BOOLEAN,
    saison VARCHAR(20),  -- 'Printemps', 'Été', 'Automne', 'Hiver'
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_temps_date ON dim_temps(date_complete);
CREATE INDEX idx_temps_annee_mois ON dim_temps(annee, mois);
CREATE INDEX idx_temps_trimestre ON dim_temps(annee, trimestre);

COMMENT ON TABLE dim_temps IS 'Dimension Temps consolidée - Période 2015-2030 - Chargement unique';


-- --------------------------------------------
-- DIMENSION MUTUELLE
-- --------------------------------------------
CREATE TABLE dim_mutuelle (
    sk_mutuelle BIGSERIAL PRIMARY KEY,
    id_mut INT UNIQUE NOT NULL,  -- Business Key
    nom_mutuelle VARCHAR(255),
    adresse VARCHAR(255),
    type_mutuelle VARCHAR(50),  -- 'Mutuelle', 'Assurance', 'CMU'
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_mutuelle_id ON dim_mutuelle(id_mut);

COMMENT ON TABLE dim_mutuelle IS 'Dimension Mutuelle - Alimentation mensuelle';


-- ============================================
-- CRÉATION DES TABLES DE FAITS
-- ============================================

-- --------------------------------------------
-- FAIT CONSULTATION
-- --------------------------------------------
CREATE TABLE fait_consultation (
    sk_fait_consultation BIGSERIAL PRIMARY KEY,
    sk_patient BIGINT NOT NULL REFERENCES dim_patient(sk_patient),
    sk_professionnel BIGINT NOT NULL REFERENCES dim_professionnel(sk_professionnel),
    sk_diagnostic BIGINT NOT NULL REFERENCES dim_diagnostic(sk_diagnostic),
    sk_mutuelle BIGINT REFERENCES dim_mutuelle(sk_mutuelle),
    sk_temps BIGINT NOT NULL REFERENCES dim_temps(sk_temps),
    sk_etablissement BIGINT NOT NULL REFERENCES dim_etablissement(sk_etablissement),
    
    -- Dimensions dégénérées
    num_consultation INT,
    heure_debut TIME,
    heure_fin TIME,
    motif VARCHAR(255),
    
    -- MESURES
    duree_consultation INT,  -- en minutes
    nombre_consultations INT DEFAULT 1,  -- COUNT
    
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_fait_consultation_patient ON fait_consultation(sk_patient);
CREATE INDEX idx_fait_consultation_professionnel ON fait_consultation(sk_professionnel);
CREATE INDEX idx_fait_consultation_diagnostic ON fait_consultation(sk_diagnostic);
CREATE INDEX idx_fait_consultation_temps ON fait_consultation(sk_temps);
CREATE INDEX idx_fait_consultation_etablissement ON fait_consultation(sk_etablissement);

COMMENT ON TABLE fait_consultation IS 'Fait Consultation - Chargement quotidien incrémental';
COMMENT ON COLUMN fait_consultation.duree_consultation IS 'MESURE : Durée en minutes';
COMMENT ON COLUMN fait_consultation.nombre_consultations IS 'MESURE : COUNT = 1';


-- --------------------------------------------
-- FAIT HOSPITALISATION
-- --------------------------------------------
CREATE TABLE fait_hospitalisation (
    sk_fait_hospitalisation BIGSERIAL PRIMARY KEY,
    sk_patient BIGINT NOT NULL REFERENCES dim_patient(sk_patient),
    sk_etablissement BIGINT NOT NULL REFERENCES dim_etablissement(sk_etablissement),
    sk_diagnostic BIGINT NOT NULL REFERENCES dim_diagnostic(sk_diagnostic),
    sk_temps BIGINT NOT NULL REFERENCES dim_temps(sk_temps),
    sk_localisation BIGINT NOT NULL REFERENCES dim_localisation(sk_localisation),
    
    -- Dimensions dégénérées
    num_hospitalisation INT,
    
    -- MESURES
    jour_hospitalisation INT,  -- Durée séjour en jours
    nombre_hospitalisations INT DEFAULT 1,  -- COUNT
    
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_fait_hospitalisation_patient ON fait_hospitalisation(sk_patient);
CREATE INDEX idx_fait_hospitalisation_etablissement ON fait_hospitalisation(sk_etablissement);
CREATE INDEX idx_fait_hospitalisation_diagnostic ON fait_hospitalisation(sk_diagnostic);
CREATE INDEX idx_fait_hospitalisation_temps ON fait_hospitalisation(sk_temps);
CREATE INDEX idx_fait_hospitalisation_localisation ON fait_hospitalisation(sk_localisation);

COMMENT ON TABLE fait_hospitalisation IS 'Fait Hospitalisation - Chargement mensuel';
COMMENT ON COLUMN fait_hospitalisation.jour_hospitalisation IS 'MESURE : Durée séjour en jours';
COMMENT ON COLUMN fait_hospitalisation.nombre_hospitalisations IS 'MESURE : COUNT = 1';


-- --------------------------------------------
-- FAIT DECES
-- --------------------------------------------
CREATE TABLE fait_deces (
    sk_fait_deces BIGSERIAL PRIMARY KEY,
    sk_patient BIGINT REFERENCES dim_patient(sk_patient),  -- Peut être NULL
    sk_localisation BIGINT NOT NULL REFERENCES dim_localisation(sk_localisation),
    sk_temps BIGINT NOT NULL REFERENCES dim_temps(sk_temps),
    
    -- Dimensions dégénérées
    code_lieu_deces VARCHAR(10),
    numero_acte_deces VARCHAR(20),
    
    -- MESURES
    age_deces INT,
    nombre_deces INT DEFAULT 1,  -- COUNT
    
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_fait_deces_patient ON fait_deces(sk_patient);
CREATE INDEX idx_fait_deces_localisation ON fait_deces(sk_localisation);
CREATE INDEX idx_fait_deces_temps ON fait_deces(sk_temps);

COMMENT ON TABLE fait_deces IS 'Fait Décès - Chargement annuel';
COMMENT ON COLUMN fait_deces.sk_patient IS 'Peut être NULL si patient non identifié';
COMMENT ON COLUMN fait_deces.age_deces IS 'MESURE : Âge au décès';
COMMENT ON COLUMN fait_deces.nombre_deces IS 'MESURE : COUNT = 1';


-- --------------------------------------------
-- FAIT SATISFACTION (e-Satis)
-- --------------------------------------------
CREATE TABLE fait_satisfaction (
    sk_fait_satisfaction BIGSERIAL PRIMARY KEY,
    sk_etablissement BIGINT NOT NULL REFERENCES dim_etablissement(sk_etablissement),
    
    -- MESURES
    region VARCHAR(255),
	annee_enquete INT,
    score_global DECIMAL(5,2),
    score_accueil DECIMAL(5,2),
    score_pec_infirmiers DECIMAL(5,2),
    score_pec_medecins DECIMAL(5,2),
    score_chambre DECIMAL(5,2),
    score_repas DECIMAL(5,2),
    score_sortie DECIMAL(5,2),
    taux_recommandation DECIMAL(5,2),
    nombre_reponses INT,
    
    -- Dimensions dégénérées
    classement VARCHAR(2),  -- 'A', 'B', 'C', 'D', 'DI'
    evolution VARCHAR(255),
    
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_fait_satisfaction_etablissement ON fait_satisfaction(sk_etablissement);

COMMENT ON TABLE fait_satisfaction IS 'Fait Satisfaction e-Satis 48h MCO - Chargement annuel';
COMMENT ON COLUMN fait_satisfaction.score_global IS 'MESURE : Score satisfaction global';
COMMENT ON COLUMN fait_satisfaction.nombre_reponses IS 'MESURE : Nombre réponses exploitables';


-- --------------------------------------------
-- FAIT QUALITE SOINS (IQSS)
-- --------------------------------------------
CREATE TABLE fait_qualite_soins (
    sk_fait_qualite BIGSERIAL PRIMARY KEY,
    sk_etablissement BIGINT NOT NULL REFERENCES dim_etablissement(sk_etablissement),
    
    -- MESURES
	region VARCHAR(255),
	annee_enquete INT,
	annee_donnee INT,
    ratio_ete_ortho DECIMAL(10,6),  -- Événements thrombo-emboliques
    alerte_ete INT,  -- 0=Normal, 1=Alerte,
	cible BIGINT,
	observations BIGINT,
    
    -- Dimensions dégénérées
    attendu DOUBLE PRECISION,
	position_seuil VARCHAR(20),
    
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_fait_qualite_etablissement ON fait_qualite_soins(sk_etablissement);

COMMENT ON TABLE fait_qualite_soins IS 'Fait Qualité Soins IQSS - Chargement annuel';
COMMENT ON COLUMN fait_qualite_soins.ratio_ete_ortho IS 'MESURE : Ratio événements thrombo-emboliques';


-- ============================================
-- Inserts Initiaux
-- ============================================

-- ============================================
-- INSERT PAR DÉFAUT DIM_PATIENT
-- ============================================
INSERT INTO dim_patient (
    sk_patient,
    id_patient,
    nom_anonyme,
    prenom_anonyme,
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
    num_secu_hash,
    date_chargement,
    date_modification
)
VALUES (
    -1,
    -1,
    'Non renseigné',       -- VARCHAR(50)
    'Non renseigné',       -- VARCHAR(50)
    'UNK',                 -- VARCHAR(10)
    NULL,
    NULL,
    'UNK',                 -- VARCHAR(20)
    'UNK',                 -- VARCHAR(3)
    NULL,
    NULL,
    '00000',               -- VARCHAR(10)
    'Non renseigné',       -- VARCHAR(100)
    'FR',                  -- VARCHAR(2)
    '0000000000000000000000000000000000000000000000000000000000000000', -- VARCHAR(64)
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
);

-- ============================================
-- INSERT PAR DÉFAUT DIM_SPECIALITE
-- ============================================
INSERT INTO dim_specialite (
    sk_specialite,
    code_specialite,
    fonction,
    specialite,
    categorie,
    date_chargement
)
VALUES (
    -1,
    'UNKNOWN',             -- VARCHAR(10)
    'Non renseigné',       -- VARCHAR(100)
    'Non renseigné',       -- VARCHAR(100)
    'Non renseigné',       -- VARCHAR(50)
    CURRENT_TIMESTAMP
);

-- ============================================
-- INSERT PAR DÉFAUT DIM_PROFESSIONNEL
-- ============================================
INSERT INTO dim_professionnel (
    sk_professionnel,
    identifiant,
    civilite,
    nom_anonyme,
    prenom_anonyme,
    profession,
    categorie_professionnelle,
    fk_specialite,
    mode_exercice,
    fk_organisation,
    date_debut_validite,
    date_fin_validite,
    est_actuel,
    date_chargement
)
VALUES (
    -1,
    'UNKNOWN',             -- VARCHAR(20)
    'UNK',                 -- VARCHAR(10)
    'Non renseigné',       -- VARCHAR(50)
    'Non renseigné',       -- VARCHAR(50)
    'Non renseigné',       -- VARCHAR(100)
    'Non renseigné',       -- VARCHAR(50)
    -1,
    'UNK',                 -- VARCHAR(20)
    'UNKNOWN',             -- VARCHAR(20)
    CURRENT_DATE,
    NULL,
    TRUE,
    CURRENT_TIMESTAMP
);

-- ============================================
-- INSERT PAR DÉFAUT DIM_DIAGNOSTIC
-- ============================================
INSERT INTO dim_diagnostic (
    sk_diagnostic,
    code_diagnostic,
    libelle_diagnostic,
    categorie_cim10,
    chapitre_cim10,
    source_donnee,
    date_chargement
)
VALUES (
    -1,
    'UNKNOWN',             -- VARCHAR(10)
    'Non renseigné',       -- VARCHAR(255)
    'UNK',                 -- VARCHAR(5)
    'Non renseigné',       -- VARCHAR(100)
    'Non renseigné',       -- VARCHAR(50)
    CURRENT_TIMESTAMP
);

-- ============================================
-- INSERT PAR DÉFAUT DIM_ETABLISSEMENT
-- ============================================
INSERT INTO dim_etablissement (
    sk_etablissement,
    finess,
    nom_etablissement,
    type_etablissement,
    categorie,
    region,
    departement,
    adresse,
    code_postal,
    ville,
    date_chargement
)
VALUES (
    -1,
    'UNKNOWN',             -- VARCHAR(20)
    'Non renseigné',       -- VARCHAR(255)
    'Non renseigné',       -- VARCHAR(50)
    'Non renseigné',       -- VARCHAR(100)
    'Non renseigné',       -- VARCHAR(100)
    '000',                 -- VARCHAR(3)
    'Non renseigné',       -- VARCHAR(255)
    '00000',               -- VARCHAR(10)
    'Non renseigné',       -- VARCHAR(100)
    CURRENT_TIMESTAMP
);

-- ============================================
-- INSERT PAR DÉFAUT DIM_LOCALISATION
-- ============================================
INSERT INTO dim_localisation (
    sk_localisation,
    code_lieu,
    nom_lieu,
    code_postal,
    ville,
    departement,
    region,
    pays,
    type_lieu,
    latitude,
    longitude,
    date_chargement
)
VALUES (
    -1,
    'UNKNOWN',             -- VARCHAR(10)
    'Non renseigné',       -- VARCHAR(100)
    '00000',               -- VARCHAR(10)
    'Non renseigné',       -- VARCHAR(100)
    '000',                 -- VARCHAR(3)
    'Non renseigné',       -- VARCHAR(100)
    'FR',                  -- VARCHAR(2)
    'UNK',                 -- VARCHAR(50)
    0.0,
    0.0,
    CURRENT_TIMESTAMP
);

-- ============================================
-- INSERT PAR DÉFAUT DIM_MUTUELLE
-- ============================================
INSERT INTO dim_mutuelle (
    sk_mutuelle,
    id_mut,
    nom_mutuelle,
    adresse,
    type_mutuelle,
    date_chargement
)
VALUES (
    -1,
    -1,
    'Non renseigné',       -- VARCHAR(255)
    'Non renseigné',       -- VARCHAR(255)
    'UNK',                 -- VARCHAR(50)
    CURRENT_TIMESTAMP
);


-- ============================================
-- FIN DU SCRIPT MLD
-- ============================================
