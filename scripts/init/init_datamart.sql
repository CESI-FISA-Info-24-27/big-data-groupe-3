-- Création du schéma datamart
CREATE SCHEMA IF NOT EXISTS datamart;

COMMENT ON SCHEMA datamart IS 'Data Marts - Tables agrégées optimisées pour Power BI';

-- ========================================
-- TABLE 1: dm_consultations_agregees
-- ========================================

CREATE TABLE IF NOT EXISTS datamart.dm_consultations_agregees (
    -- Clés temporelles
    sk_temps INTEGER NOT NULL,
    date_complete DATE NOT NULL,
    annee INTEGER NOT NULL,
    trimestre INTEGER NOT NULL,
    mois INTEGER NOT NULL,
    
    -- Clés et libellés établissement
    sk_etablissement INTEGER NOT NULL,
    nom_etablissement VARCHAR(255),
    region_etablissement VARCHAR(100),
    departement_etablissement VARCHAR(10),
    
    -- Clés et libellés diagnostic
    sk_diagnostic INTEGER NOT NULL,
    code_diagnostic VARCHAR(20),
    libelle_diagnostic TEXT,
    chapitre_cim10 VARCHAR(100),
    categorie_cim10 VARCHAR(100),
    
    -- Clés et libellés professionnel
    sk_professionnel INTEGER NOT NULL,
    nom_professionnel VARCHAR(100),
    prenom_professionnel VARCHAR(100),
    specialite VARCHAR(255),
    fonction VARCHAR(100),
    
    -- Profil patient
    sexe VARCHAR(10),
    tranche_age VARCHAR(20),
    age INTEGER,
    
    -- Mesures agrégées par établissement
    nb_consultations_etablissement INTEGER NOT NULL DEFAULT 0,
    duree_totale_etablissement INTEGER DEFAULT 0,
    nb_patients_uniques_etablissement INTEGER DEFAULT 0,
    
    -- Mesures agrégées par diagnostic
    nb_consultations_diagnostic INTEGER DEFAULT 0,
    duree_totale_diagnostic INTEGER DEFAULT 0,
    nb_patients_uniques_diagnostic INTEGER DEFAULT 0,
    
    -- Mesures agrégées par professionnel
    nb_consultations_professionnel INTEGER DEFAULT 0,
    duree_totale_professionnel INTEGER DEFAULT 0,
    nb_patients_uniques_professionnel INTEGER DEFAULT 0,
    
    -- Mesures agrégées par profil patient
    nb_consultations_profil INTEGER DEFAULT 0,
    duree_totale_profil INTEGER DEFAULT 0,
    nb_patients_uniques_profil INTEGER DEFAULT 0,
    
    -- Métadonnées
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Clé primaire composite
    PRIMARY KEY (sk_temps, sk_etablissement, sk_diagnostic, sk_professionnel)
);

COMMENT ON TABLE datamart.dm_consultations_agregees IS 'Data Mart - Consultations agrégées par établissement, diagnostic, professionnel et profil patient';

-- ========================================
-- TABLE 2: dm_hospitalisations_agregees
-- ========================================

CREATE TABLE IF NOT EXISTS datamart.dm_hospitalisations_agregees (
    -- Clés temporelles
    sk_temps INTEGER NOT NULL,
    date_complete DATE NOT NULL,
    annee INTEGER NOT NULL,
    trimestre INTEGER NOT NULL,
    mois INTEGER NOT NULL,
    
    -- Clés et libellés établissement
    sk_etablissement INTEGER NOT NULL,
    nom_etablissement VARCHAR(255),
    region_etablissement VARCHAR(100),
    departement_etablissement VARCHAR(10),
    
    -- Clés et libellés diagnostic
    sk_diagnostic INTEGER NOT NULL,
    code_diagnostic VARCHAR(20),
    libelle_diagnostic TEXT,
    chapitre_cim10 VARCHAR(100),
    categorie_cim10 VARCHAR(100),
    
    -- Profil patient
    sexe VARCHAR(10),
    tranche_age VARCHAR(20),
    age INTEGER,
    
    -- Mesures agrégées par établissement
    nb_hospitalisations_etablissement INTEGER NOT NULL DEFAULT 0,
    duree_totale_etablissement INTEGER DEFAULT 0,
    nb_patients_uniques_etablissement INTEGER DEFAULT 0,
    duree_moyenne_etablissement DECIMAL(5,2) DEFAULT 0,
    
    -- Mesures agrégées par diagnostic
    nb_hospitalisations_diagnostic INTEGER DEFAULT 0,
    duree_totale_diagnostic INTEGER DEFAULT 0,
    nb_patients_uniques_diagnostic INTEGER DEFAULT 0,
    duree_moyenne_diagnostic DECIMAL(5,2) DEFAULT 0,
    
    -- Mesures agrégées par profil patient
    nb_hospitalisations_profil INTEGER DEFAULT 0,
    duree_totale_profil INTEGER DEFAULT 0,
    nb_patients_uniques_profil INTEGER DEFAULT 0,
    duree_moyenne_profil DECIMAL(5,2) DEFAULT 0,
    
    -- Mesures agrégées par région
    nb_hospitalisations_region INTEGER DEFAULT 0,
    duree_totale_region INTEGER DEFAULT 0,
    nb_patients_uniques_region INTEGER DEFAULT 0,
    duree_moyenne_region DECIMAL(5,2) DEFAULT 0,
    
    -- Métadonnées
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Clé primaire composite
    PRIMARY KEY (sk_temps, sk_etablissement, sk_diagnostic)
);

COMMENT ON TABLE datamart.dm_hospitalisations_agregees IS 'Data Mart - Hospitalisations agrégées par établissement, diagnostic et profil patient';

-- ========================================
-- TABLE 3: dm_analyse_territoriale
-- ========================================

CREATE TABLE IF NOT EXISTS datamart.dm_analyse_territoriale (
    -- Clés temporelles
    sk_temps INTEGER NOT NULL,
    date_complete DATE NOT NULL,
    annee INTEGER NOT NULL,
    trimestre INTEGER NOT NULL,
    mois INTEGER NOT NULL,
    
    -- Géographie
    region VARCHAR(100) NOT NULL,
    
    -- Indicateurs décès
    nb_deces_region INTEGER NOT NULL DEFAULT 0,
    nb_patients_deces_region INTEGER DEFAULT 0,
    nb_deces_hommes INTEGER DEFAULT 0,
    nb_deces_femmes INTEGER DEFAULT 0,
    nb_deces_0_18 INTEGER DEFAULT 0,
    nb_deces_19_30 INTEGER DEFAULT 0,
    nb_deces_31_50 INTEGER DEFAULT 0,
    nb_deces_51_65 INTEGER DEFAULT 0,
    nb_deces_66_plus INTEGER DEFAULT 0,
    
    -- Indicateurs satisfaction
    nb_reponses_satisfaction INTEGER DEFAULT 0,
    note_moyenne_satisfaction DECIMAL(5,2) DEFAULT 0,
    nb_patients_satisfaction INTEGER DEFAULT 0,
    nb_etablissements_satisfaction INTEGER DEFAULT 0,
    nb_reponses_hommes INTEGER DEFAULT 0,
    nb_reponses_femmes INTEGER DEFAULT 0,
    note_moyenne_hommes DECIMAL(5,2) DEFAULT 0,
    note_moyenne_femmes DECIMAL(5,2) DEFAULT 0,
    
    -- Métadonnées
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Clé primaire composite (avec granularité)
    PRIMARY KEY (sk_temps, region, mois)
);

COMMENT ON TABLE datamart.dm_analyse_territoriale IS 'Data Mart - Analyse territoriale avec décès par région (2019) et satisfaction par région (2020)';

-- ========================================
-- INDEX POUR PERFORMANCE
-- ========================================

-- Index pour les filtres temporels
CREATE INDEX IF NOT EXISTS idx_dm_consultations_temps ON datamart.dm_consultations_agregees(annee, trimestre, mois);
CREATE INDEX IF NOT EXISTS idx_dm_hospitalisations_temps ON datamart.dm_hospitalisations_agregees(annee, trimestre, mois);
CREATE INDEX IF NOT EXISTS idx_dm_territoriale_temps ON datamart.dm_analyse_territoriale(annee, trimestre, mois);

-- Index pour les filtres géographiques
CREATE INDEX IF NOT EXISTS idx_dm_consultations_region ON datamart.dm_consultations_agregees(region_etablissement);
CREATE INDEX IF NOT EXISTS idx_dm_hospitalisations_region ON datamart.dm_hospitalisations_agregees(region_etablissement);
CREATE INDEX IF NOT EXISTS idx_dm_territoriale_region ON datamart.dm_analyse_territoriale(region);

-- Index pour les filtres établissement
CREATE INDEX IF NOT EXISTS idx_dm_consultations_etablissement ON datamart.dm_consultations_agregees(sk_etablissement, nom_etablissement);
CREATE INDEX IF NOT EXISTS idx_dm_hospitalisations_etablissement ON datamart.dm_hospitalisations_agregees(sk_etablissement, nom_etablissement);

-- Index pour les filtres diagnostic
CREATE INDEX IF NOT EXISTS idx_dm_consultations_diagnostic ON datamart.dm_consultations_agregees(sk_diagnostic, code_diagnostic);
CREATE INDEX IF NOT EXISTS idx_dm_hospitalisations_diagnostic ON datamart.dm_hospitalisations_agregees(sk_diagnostic, code_diagnostic);

-- Index pour les filtres professionnel
CREATE INDEX IF NOT EXISTS idx_dm_consultations_professionnel ON datamart.dm_consultations_agregees(sk_professionnel, specialite);
