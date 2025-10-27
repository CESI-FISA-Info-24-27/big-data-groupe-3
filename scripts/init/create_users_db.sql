-- ============================================================================
-- Script de création des utilisateurs PostgreSQL
-- ============================================================================

-- ============================================================================
-- 1. UTILISATEUR ETL
-- ============================================================================
-- Utilisateur pour pousser les données dans DWH et DataMarts
-- Privilèges : SELECT, INSERT, TRUNCATE sur schémas dwh et datamart

CREATE USER etl_user WITH PASSWORD 'MDP_A_Changer!';

-- Privilèges sur schéma dwh
GRANT USAGE ON SCHEMA dwh TO etl_user;
GRANT SELECT, INSERT, TRUNCATE ON ALL TABLES IN SCHEMA dwh TO etl_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA dwh GRANT SELECT, INSERT, TRUNCATE ON TABLES TO etl_user;

-- Privilèges sur schéma datamart
GRANT USAGE ON SCHEMA datamart TO etl_user;
GRANT SELECT, INSERT, TRUNCATE ON ALL TABLES IN SCHEMA datamart TO etl_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA datamart GRANT SELECT, INSERT, TRUNCATE ON TABLES TO etl_user;


-- ============================================================================
-- 2. UTILISATEUR LECTURE GLOBALE DATAMART
-- ============================================================================
-- Utilisateur avec droits de lecture sur TOUTES les tables du schéma datamart
-- Privilèges : SELECT uniquement sur schéma datamart

CREATE USER datamart_reader WITH PASSWORD 'MDP_A_Changer!';

GRANT USAGE ON SCHEMA datamart TO datamart_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA datamart TO datamart_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA datamart GRANT SELECT ON TABLES TO datamart_reader;


-- ============================================================================
-- 3. UTILISATEUR DATAMART CONSULTATIONS
-- ============================================================================
-- Utilisateur avec droits de lecture uniquement sur le datamart consultations
-- Privilèges : SELECT sur table dm_consultations_analysis

CREATE USER dm_consultations_reader WITH PASSWORD 'MDP_A_Changer!';

GRANT USAGE ON SCHEMA datamart TO dm_consultations_reader;
GRANT SELECT ON datamart.dm_consultations_analysis TO dm_consultations_reader;


-- ============================================================================
-- 4. UTILISATEUR DATAMART HOSPITALISATIONS
-- ============================================================================
-- Utilisateur avec droits de lecture uniquement sur le datamart hospitalisations
-- Privilèges : SELECT sur table dm_hospitalisations_analysis

CREATE USER dm_hospitalisations_reader WITH PASSWORD 'MDP_A_Changer!';

GRANT USAGE ON SCHEMA datamart TO dm_hospitalisations_reader;
GRANT SELECT ON datamart.dm_hospitalisations_analysis TO dm_hospitalisations_reader;


-- ============================================================================
-- 5. UTILISATEUR DATAMART DÉCÈS
-- ============================================================================
-- Utilisateur avec droits de lecture uniquement sur le datamart décès
-- Privilèges : SELECT sur table dm_deces_analysis

CREATE USER dm_deces_reader WITH PASSWORD 'MDP_A_Changer!';

GRANT USAGE ON SCHEMA datamart TO dm_deces_reader;
GRANT SELECT ON datamart.dm_deces_analysis TO dm_deces_reader;


-- ============================================================================
-- 6. UTILISATEUR DATAMART SATISFACTION
-- ============================================================================
-- Utilisateur avec droits de lecture uniquement sur le datamart satisfaction
-- Privilèges : SELECT sur table dm_satisfaction_analysis

CREATE USER dm_satisfaction_reader WITH PASSWORD 'MDP_A_Changer!';

GRANT USAGE ON SCHEMA datamart TO dm_satisfaction_reader;
GRANT SELECT ON datamart.dm_satisfaction_analysis TO dm_satisfaction_reader;

