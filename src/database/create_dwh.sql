-- ============================================
-- MLD - PROJET CHU
-- Schéma en Constellation
-- 5 Tables de FAITS + 8 Tables de DIMENSIONS
-- ============================================

-- ============================================
-- CRÉATION DU SCHÉMA DWH
-- ============================================

CREATE SCHEMA IF NOT EXISTS dwh;
CREATE SCHEMA IF NOT EXISTS mart;
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
-- TABLES DE DIMENSIONS
-- ============================================

-- --------------------------------------------
-- DIMENSION PATIENT
-- Source: PostgreSQL.patient
-- --------------------------------------------
CREATE TABLE dim_patient (
    sk_patient BIGSERIAL PRIMARY KEY,                      -- Auto-généré (séquence PostgreSQL)
    id_patient INT UNIQUE NOT NULL,                        -- PostgreSQL.patient.id_patient
    nom VARCHAR(50),                                       -- PostgreSQL.patient.nom (nettoyé: UPPER, TRIM)
    prenom VARCHAR(50),                                    -- PostgreSQL.patient.prenom (nettoyé: UPPER, TRIM)
    sexe VARCHAR(10),                                      -- PostgreSQL.patient.sexe (standardisé: M/F)
    date_naissance DATE,                                   -- PostgreSQL.patient.date_naissance
    age INT,                                               -- Calculé: DATEDIFF(CURRENT_DATE, date_naissance) / 365
    tranche_age VARCHAR(20),                               -- Calculé: CASE WHEN age <= 18 THEN '0-18' WHEN age <= 30...
    groupe_sanguin VARCHAR(3),                             -- PostgreSQL.patient.groupe_sanguin
    poids DECIMAL(5,2),                                    -- PostgreSQL.patient.poids
    taille INT,                                            -- PostgreSQL.patient.taille
    code_postal VARCHAR(10),                               -- PostgreSQL.patient.code_postal (nettoyé: TRIM)
    ville VARCHAR(100),                                    -- PostgreSQL.patient.ville (nettoyé: UPPER)
    pays VARCHAR(2),                                       -- PostgreSQL.patient.pays (défaut: 'FR' si NULL)
    num_secu_hash VARCHAR(64),                             -- Calculé: SHA256(PostgreSQL.patient.num_secu) - RGPD
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP,   -- Timestamp automatique du chargement
    date_modification TIMESTAMP DEFAULT CURRENT_TIMESTAMP  -- Timestamp automatique de la dernière MAJ
);

-- --------------------------------------------
-- DIMENSION SPECIALITE
-- Source: PostgreSQL.specialite
-- --------------------------------------------
CREATE TABLE dim_specialite (
    sk_specialite BIGSERIAL PRIMARY KEY,                   -- Auto-généré
    code_specialite VARCHAR(10) UNIQUE NOT NULL,           -- PostgreSQL.specialite.code_specialite
    fonction VARCHAR(100),                                 -- PostgreSQL.specialite.fonction
    specialite VARCHAR(100),                               -- PostgreSQL.specialite.specialite
    categorie VARCHAR(50),                                 -- Calculé: regroupement fonction (Médecine générale/spécialisée)
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP    -- Timestamp automatique
);

-- --------------------------------------------
-- DIMENSION PROFESSIONNEL
-- Sources: PostgreSQL.professionnel + PostgreSQL.professionnels_sante
-- --------------------------------------------
CREATE TABLE dim_professionnel (
    sk_professionnel BIGSERIAL PRIMARY KEY,                -- Auto-généré
    identifiant VARCHAR(20) NOT NULL,                      -- PostgreSQL.professionnel.identifiant (RPPS/ADELI)
    civilite VARCHAR(10),                                  -- PostgreSQL.professionnel.civilite
    nom VARCHAR(50),                                       -- PostgreSQL.professionnel.nom (nettoyé: UPPER)
    prenom VARCHAR(50),                                    -- PostgreSQL.professionnel.prenom (nettoyé: UPPER)
    profession VARCHAR(100),                               -- PostgreSQL.professionnel.profession
    categorie_professionnelle VARCHAR(50),                 -- Calculé: regroupement profession (Médecin/Infirmier/Aide-soignant...)
    fk_specialite BIGINT REFERENCES dim_specialite,        -- JOIN avec dim_specialite via code_specialite
    mode_exercice VARCHAR(20),                             -- PostgreSQL.professionnel.mode_exercice
    fk_organisation VARCHAR(20),                           -- PostgreSQL.professionnels_sante.finess (établissement rattaché)
    date_debut_validite DATE NOT NULL,                     -- Date du chargement pour SCD Type 2
    date_fin_validite DATE,                                -- NULL si actuel, sinon date du nouveau chargement
    est_actuel BOOLEAN DEFAULT TRUE,                       -- TRUE pour version actuelle, FALSE pour historique
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP    -- Timestamp du chargement
);

-- --------------------------------------------
-- DIMENSION DIAGNOSTIC
-- Sources: PostgreSQL.diagnostic + Hospitalisation.csv + Etablissement (satisfaction/qualité)
-- --------------------------------------------
CREATE TABLE dim_diagnostic (
    sk_diagnostic BIGSERIAL PRIMARY KEY,                   -- Auto-généré
    code_diagnostic VARCHAR(10) UNIQUE NOT NULL,           -- PostgreSQL.diagnostic.code OU Hospitalisation.diagnostic
    libelle_diagnostic VARCHAR(255),                       -- PostgreSQL.diagnostic.libelle OU lookup CIM-10
    categorie_cim10 VARCHAR(5),                            -- Calculé: SUBSTRING(code_diagnostic, 1, 3) - 3 premiers caractères
    chapitre_cim10 VARCHAR(100),                           -- Lookup table CIM-10 par catégorie (A00-B99 = Maladies infectieuses...)
    source_donnee VARCHAR(50),                             -- Calculé: 'PostgreSQL' / 'Hospitalisation' / 'Etablissement'
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP    -- Timestamp du chargement
);

-- --------------------------------------------
-- DIMENSION ETABLISSEMENT
-- Source: PostgreSQL.etablissement
-- --------------------------------------------
CREATE TABLE dim_etablissement (
    sk_etablissement BIGSERIAL PRIMARY KEY,                -- Auto-généré
    finess VARCHAR(20) UNIQUE NOT NULL,                    -- PostgreSQL.etablissement.finess (N° FINESS)
    nom_etablissement VARCHAR(255),                        -- PostgreSQL.etablissement.nom
    type_etablissement VARCHAR(50),                        -- PostgreSQL.etablissement.type (CH/Privé/PSPH-EBNL)
    categorie VARCHAR(100),                                -- PostgreSQL.etablissement.categorie
    region VARCHAR(100),                                   -- PostgreSQL.etablissement.region
    departement VARCHAR(3),                                -- Calculé: SUBSTRING(code_postal, 1, 2 ou 3) OU lookup INSEE
    adresse VARCHAR(255),                                  -- PostgreSQL.etablissement.adresse
    code_postal VARCHAR(10),                               -- PostgreSQL.etablissement.code_postal
    ville VARCHAR(100),                                    -- PostgreSQL.etablissement.ville
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP    -- Timestamp du chargement
);

-- --------------------------------------------
-- DIMENSION LOCALISATION
-- Sources: CONSOLIDATION de toutes les localisations (Patient, Hospitalisation, Décès, Satisfaction)
-- --------------------------------------------
CREATE TABLE dim_localisation (
    sk_localisation BIGSERIAL PRIMARY KEY,                 -- Auto-généré
    code_lieu VARCHAR(10) NOT NULL,                        -- Code INSEE OU code_postal selon source
    nom_lieu VARCHAR(100),                                 -- Nom de la commune (lookup API communes ou base INSEE)
    code_postal VARCHAR(10),                               -- Code postal associé (lookup ou extrait source)
    ville VARCHAR(100),                                    -- Nom ville (PostgreSQL.patient.ville OU Deces.lieu_deces OU lookup)
    departement VARCHAR(3),                                -- Calculé: SUBSTRING(code_postal, 1, 2) OU lookup INSEE
    region VARCHAR(100),                                   -- Lookup par département (table référentiel régions) OU sources
    pays VARCHAR(2),                                       -- Deces.csv.pays_naissance/deces OU 'FR' par défaut
    type_lieu VARCHAR(50),                                 -- Calculé: 'Patient'/'Hospitalisation'/'Deces'/'Etablissement'
    latitude DECIMAL(10,8),                                -- API géolocalisation (geocode) à partir code_postal/ville
    longitude DECIMAL(11,8),                               -- API géolocalisation (geocode) à partir code_postal/ville
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP,   -- Timestamp du chargement
    UNIQUE(code_lieu, type_lieu)                           -- Unicité par code ET type
);

-- --------------------------------------------
-- DIMENSION TEMPS
-- Source: GÉNÉRÉE programmatiquement (2015-2030)
-- --------------------------------------------
CREATE TABLE dim_temps (
    sk_temps BIGINT PRIMARY KEY,                           -- Calculé: FORMAT(date, 'YYYYMMDD') ex: 20241207
    date_complete DATE UNIQUE NOT NULL,                    -- Date générée (boucle 2015-01-01 à 2030-12-31)
    jour INT NOT NULL,                                     -- Calculé: DAY(date_complete)
    mois INT NOT NULL,                                     -- Calculé: MONTH(date_complete)
    trimestre INT NOT NULL,                                -- Calculé: CEIL(mois / 3)
    semestre INT NOT NULL,                                 -- Calculé: CEIL(mois / 6)
    annee INT NOT NULL,                                    -- Calculé: YEAR(date_complete)
    semaine_annee INT NOT NULL,                            -- Calculé: WEEK(date_complete)
    jour_semaine INT NOT NULL,                             -- Calculé: DAYOFWEEK(date_complete) 1=Lundi, 7=Dimanche
    nom_jour VARCHAR(10),                                  -- Calculé: CASE jour_semaine WHEN 1 THEN 'Lundi' WHEN 2...
    nom_mois VARCHAR(20),                                  -- Calculé: CASE mois WHEN 1 THEN 'Janvier' WHEN 2...
    est_weekend BOOLEAN,                                   -- Calculé: jour_semaine IN (6, 7) = Samedi/Dimanche
    est_ferie BOOLEAN,                                     -- Lookup table jours fériés français (1er mai, 14 juillet...)
    saison VARCHAR(20),                                    -- Calculé: CASE mois WHEN 3,4,5 THEN 'Printemps' WHEN 6,7,8...
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP    -- Timestamp du chargement
);

-- --------------------------------------------
-- DIMENSION MUTUELLE
-- Source: PostgreSQL.mutuelle
-- --------------------------------------------
CREATE TABLE dim_mutuelle (
    sk_mutuelle BIGSERIAL PRIMARY KEY,                     -- Auto-généré
    id_mut INT UNIQUE NOT NULL,                            -- PostgreSQL.mutuelle.id_mut
    nom_mutuelle VARCHAR(255),                             -- PostgreSQL.mutuelle.nom_mutuelle
    adresse VARCHAR(255),                                  -- PostgreSQL.mutuelle.adresse
    type_mutuelle VARCHAR(50),                             -- Calculé: classification nom (contient 'CMU'→'CMU', 'Assurance'→...)
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP    -- Timestamp du chargement
);


-- ============================================
-- TABLES DE FAITS
-- ============================================

-- --------------------------------------------
-- FAIT CONSULTATION
-- Source: PostgreSQL.consultation + Lookups dimensions
-- Granularité: 1 ligne = 1 consultation
-- --------------------------------------------
CREATE TABLE fait_consultation (
    sk_fait_consultation BIGSERIAL PRIMARY KEY,            -- Auto-généré
    sk_patient BIGINT NOT NULL REFERENCES dim_patient,     -- Lookup dim_patient via PostgreSQL.consultation.id_patient
    sk_professionnel BIGINT NOT NULL REFERENCES dim_professionnel, -- Lookup dim_professionnel via PostgreSQL.consultation.identifiant
    sk_diagnostic BIGINT NOT NULL REFERENCES dim_diagnostic,  -- Lookup dim_diagnostic via PostgreSQL.consultation.code_diagnostic
    sk_mutuelle BIGINT REFERENCES dim_mutuelle,            -- Lookup dim_mutuelle via PostgreSQL.consultation.id_mut (peut être NULL)
    sk_temps BIGINT NOT NULL REFERENCES dim_temps,         -- Lookup dim_temps via PostgreSQL.consultation.date_consultation
    sk_etablissement BIGINT REFERENCES dim_etablissement,  -- Lookup via dim_professionnel.fk_organisation (peut être NULL libéral)
    
    -- Dimensions dégénérées (attributs bas niveau gardés dans le fait)
    num_consultation INT,                                  -- PostgreSQL.consultation.num_consultation
    heure_debut TIME,                                      -- PostgreSQL.consultation.heure_debut
    heure_fin TIME,                                        -- PostgreSQL.consultation.heure_fin
    motif VARCHAR(255),                                    -- PostgreSQL.consultation.motif
    
    -- MESURES (métriques agrégables)
    duree_consultation INT,                                -- Calculé: TIMESTAMPDIFF(MINUTE, heure_debut, heure_fin)
    nombre_consultations INT DEFAULT 1,                    -- Constante: 1 pour COUNT (1 ligne = 1 consultation)
    
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP    -- Timestamp du chargement
);

-- --------------------------------------------
-- FAIT HOSPITALISATION
-- Source: Hospitalisation.csv + Lookups dimensions
-- Granularité: 1 ligne = 1 séjour hospitalier complet
-- --------------------------------------------
CREATE TABLE fait_hospitalisation (
    sk_fait_hospitalisation BIGSERIAL PRIMARY KEY,         -- Auto-généré
    sk_patient BIGINT NOT NULL REFERENCES dim_patient,     -- Lookup dim_patient via matching (nom, prénom, date_naissance) Hospitalisation.csv
    sk_etablissement BIGINT NOT NULL REFERENCES dim_etablissement,  -- Lookup dim_etablissement via Hospitalisation.csv (établissement/FINESS)
    sk_diagnostic BIGINT NOT NULL REFERENCES dim_diagnostic,  -- Lookup dim_diagnostic via Hospitalisation.csv.diagnostic (code CIM-10)
    sk_temps BIGINT NOT NULL REFERENCES dim_temps,         -- Lookup dim_temps via Hospitalisation.csv.date_entree (ou date_sortie)
    sk_localisation BIGINT NOT NULL REFERENCES dim_localisation,  -- Lookup dim_localisation via Hospitalisation.csv (localisation séjour)
    
    -- Dimensions dégénérées
    num_hospitalisation INT,                               -- Numéro séjour (si présent) OU généré séquentiellement
    
    -- MESURES
    jour_hospitalisation INT,                              -- Calculé: DATEDIFF(date_sortie, date_entree) depuis Hospitalisation.csv
    nombre_hospitalisations INT DEFAULT 1,                 -- Constante: 1 pour COUNT (1 ligne = 1 séjour)
    
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP    -- Timestamp du chargement
);

-- --------------------------------------------
-- FAIT DECES
-- Source: Deces.csv (INSEE Open Data)
-- Granularité: 1 ligne = 1 décès
-- --------------------------------------------
CREATE TABLE fait_deces (
    sk_fait_deces BIGSERIAL PRIMARY KEY,                   -- Auto-généré
    sk_patient BIGINT REFERENCES dim_patient,              -- Lookup dim_patient via matching (nom, prenom, date_naissance) - PEUT ÊTRE NULL si pas trouvé
    sk_localisation BIGINT NOT NULL REFERENCES dim_localisation,  -- Lookup dim_localisation via Deces.csv.code_lieu_deces
    sk_temps BIGINT NOT NULL REFERENCES dim_temps,         -- Lookup dim_temps via Deces.csv.date_deces
    
    -- Dimensions dégénérées
    code_lieu_deces VARCHAR(10),                           -- Deces.csv.code_lieu_deces (code INSEE)
    numero_acte_deces VARCHAR(20),                         -- Deces.csv.numero_acte_deces
    
    -- MESURES
    age_deces INT,                                         -- Calculé: DATEDIFF(date_deces, date_naissance) / 365 depuis Deces.csv
    nombre_deces INT DEFAULT 1,                            -- Constante: 1 pour COUNT (1 ligne = 1 décès)
    
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP    -- Timestamp du chargement
);

-- --------------------------------------------
-- FAIT SATISFACTION
-- Source: resultatsesatis*.csv + lexiqueesatis*.csv (e-Satis 48h MCO Open Data)
-- Granularité: 1 ligne = 1 établissement × 1 année
-- --------------------------------------------
CREATE TABLE fait_satisfaction (
    sk_fait_satisfaction BIGSERIAL PRIMARY KEY,            -- Auto-généré
    sk_etablissement BIGINT NOT NULL REFERENCES dim_etablissement,  -- Lookup dim_etablissement via resultats.finess
    sk_temps BIGINT NOT NULL REFERENCES dim_temps,         -- Lookup dim_temps via année fichier (1er janvier année N)
    sk_localisation BIGINT NOT NULL REFERENCES dim_localisation,  -- Lookup dim_localisation via resultats.region (région établissement)
    
    -- MESURES (scores e-Satis agrégés par établissement)
    score_global DECIMAL(5,2),                             -- resultatsesatis.score_global OU moyenne pondérée autres scores
    score_accueil DECIMAL(5,2),                            -- resultatsesatis.score_accueil (si colonne existe selon année)
    score_pec_infirmiers DECIMAL(5,2),                     -- resultatsesatis.score_pec_infirmiers (prise en charge infirmiers)
    score_pec_medecins DECIMAL(5,2),                       -- resultatsesatis.score_pec_medecins (prise en charge médecins)
    score_chambre DECIMAL(5,2),                            -- resultatsesatis.score_chambre (qualité chambre)
    score_repas DECIMAL(5,2),                              -- resultatsesatis.score_repas (qualité repas)
    score_sortie DECIMAL(5,2),                             -- resultatsesatis.score_sortie (organisation sortie)
    taux_recommandation DECIMAL(5,2),                      -- resultatsesatis.taux_recommandation (% patients recommandent)
    nombre_reponses INT,                                   -- resultatsesatis.nombre_reponses (nb questionnaires exploitables)
    
    -- Dimensions dégénérées
    classement VARCHAR(2),                                 -- resultatsesatis.classement ('A', 'B', 'C', 'D', 'DI')
    evolution VARCHAR(10),                                 -- resultatsesatis.evolution (vs année N-1: 'Hausse'/'Baisse'/'Stable')
    
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP    -- Timestamp du chargement
);

-- --------------------------------------------
-- FAIT QUALITE SOINS
-- Source: resultatsiqss*.csv + lexiqueiqss*.csv (IQSS Open Data)
-- Granularité: 1 ligne = 1 établissement × 1 année
-- --------------------------------------------
CREATE TABLE fait_qualite_soins (
    sk_fait_qualite BIGSERIAL PRIMARY KEY,                 -- Auto-généré
    sk_etablissement BIGINT NOT NULL REFERENCES dim_etablissement,  -- Lookup dim_etablissement via resultats.finess
    sk_temps BIGINT NOT NULL REFERENCES dim_temps,         -- Lookup dim_temps via année fichier (1er janvier année N)
    sk_localisation BIGINT NOT NULL REFERENCES dim_localisation,  -- Lookup dim_localisation via resultats.region
    
    -- MESURES (indicateurs qualité IQSS)
    ratio_ete_ortho DECIMAL(10,6),                         -- resultatsiqss.ratio_ete_ortho (taux événements thrombo-emboliques post-chirurgie ortho)
    alerte_ete INT,                                        -- Calculé: IF(ratio_ete_ortho > seuil_alerte, 1, 0) - seuil depuis lexique
    ratio_iso_ortho DECIMAL(10,6),                         -- resultatsiqss.ratio_iso_ortho (taux infections site opératoire post-ortho)
    alerte_iso INT,                                        -- Calculé: IF(ratio_iso_ortho > seuil_alerte, 1, 0) - seuil depuis lexique
    
    -- Dimensions dégénérées
    evolution_ete VARCHAR(10),                             -- resultatsiqss.evolution_ete (vs année N-1: 'Amélioration'/'Dégradation')
    
    date_chargement TIMESTAMP DEFAULT CURRENT_TIMESTAMP    -- Timestamp du chargement
);


-- ============================================
-- VUES UTILES POUR ANALYSES
-- ============================================

-- Vue pour analyses consultations
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

-- Vue pour analyses hospitalisations
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

-- Vue pour analyses décès
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

-- Vue pour analyses satisfaction
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
