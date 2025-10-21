-- Création des schémas
CREATE SCHEMA IF NOT EXISTS dwh;
CREATE SCHEMA IF NOT EXISTS datamart;

-- Partitionnement par défaut activé (Postgres 12+)
-- Les tables de faits seront partitionnées par date dans dbt

COMMENT ON SCHEMA dwh IS 'Entrepôt de données - Dimensions et Faits';
COMMENT ON SCHEMA datamart IS 'Data Marts - Agrégations métier';