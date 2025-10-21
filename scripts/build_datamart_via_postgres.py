#!/usr/bin/env python3
"""
Script optimisé pour créer le datamart directement dans PostgreSQL
via l'extension DuckDB Postgres, sans passer par DuckDB local

Architecture :
1. Le DWH est déjà dans PostgreSQL (pusé par push_dwh_to_postgres.py)
2. DuckDB se connecte à PostgreSQL en lecture/écriture
3. DuckDB crée le datamart directement dans PostgreSQL en lisant depuis le DWH
4. Plus besoin de transférer les données volumineuses !

Avantages :
- ✅ Pas de création du datamart dans DuckDB local (gain de temps/espace)
- ✅ Pas de transfert de données massives (45M+ lignes)
- ✅ Tout se passe dans PostgreSQL via DuckDB
- ✅ Beaucoup plus rapide et optimisé

Usage: python build_datamart_via_postgres.py
"""

import duckdb
import os
import sys
import time

# Essayer de charger dotenv
try:
    from dotenv import load_dotenv
    load_dotenv()
    print("[INFO] Fichier .env chargé")
except:
    print("[INFO] python-dotenv non installé ou .env absent, utilisation valeurs par défaut")

# Configuration PostgreSQL
POSTGRES_CONFIG = {
    'host': os.getenv('DWH_POSTGRES_HOST', os.getenv('POSTGRES_HOST', 'localhost')),
    'port': int(os.getenv('DWH_POSTGRES_PORT', os.getenv('POSTGRES_PORT', '5432'))),
    'database': os.getenv('DWH_POSTGRES_DB', os.getenv('POSTGRES_DB', 'healthcare_dwh')),
    'user': os.getenv('DWH_POSTGRES_USER', os.getenv('POSTGRES_USER', 'admin')),
    'password': os.getenv('DWH_POSTGRES_PASSWORD', os.getenv('POSTGRES_PASSWORD', 'admin'))
}

# Schémas PostgreSQL
DWH_SCHEMA = 'dwh'
DATAMART_SCHEMA = 'datamart'

# Tables du datamart à créer (dans l'ordre)
DATAMART_TABLES = [
    'dm_analyse_territoriale',      # ~30K lignes
    'dm_hospitalisations_agregees', # ~6K lignes
    'dm_consultations_agregees'     # ~45M lignes (le gros morceau)
]


def create_postgres_connection_string():
    """Créer la chaîne de connexion PostgreSQL"""
    return (f"postgresql://{POSTGRES_CONFIG['user']}:{POSTGRES_CONFIG['password']}"
            f"@{POSTGRES_CONFIG['host']}:{POSTGRES_CONFIG['port']}/{POSTGRES_CONFIG['database']}")


def connect_duckdb_with_postgres():
    """
    Créer une connexion DuckDB en mémoire et attacher PostgreSQL
    """
    try:
        # Connexion DuckDB en mémoire (pas de fichier local)
        duck_conn = duckdb.connect(':memory:')
        print("[OK] DuckDB en mémoire créé")
        
        # Installer l'extension postgres si nécessaire
        duck_conn.execute("INSTALL postgres;")
        duck_conn.execute("LOAD postgres;")
        print("[OK] Extension postgres chargée")
        
        # Attacher PostgreSQL en lecture/écriture
        pg_connection_string = create_postgres_connection_string()
        attach_query = f"ATTACH '{pg_connection_string}' AS pg (TYPE POSTGRES, READ_ONLY false);"
        duck_conn.execute(attach_query)
        
        print(f"[OK] PostgreSQL attaché : {POSTGRES_CONFIG['host']}:{POSTGRES_CONFIG['port']}/{POSTGRES_CONFIG['database']}")
        print("[INFO] Mode : Lecture/Écriture")
        
        return duck_conn
        
    except Exception as e:
        print(f"[ERREUR] Connexion impossible : {e}")
        print(f"[INFO] Vérifiez que PostgreSQL est démarré et accessible")
        return None


def get_datamart_query(table_name):
    """
    Retourner la requête SQL compilée pour créer un datamart
    
    Note : Les requêtes sont adaptées depuis les modèles dbt
    avec les références {{ ref('...') }} remplacées par pg.dwh.table
    """
    
    queries = {
        'dm_consultations_agregees': """
            WITH consultations_base AS (
                SELECT 
                    fc.sk_temps,
                    fc.sk_diagnostic,
                    fc.sk_professionnel,
                    fc.sk_patient,
                    fc.sk_mutuelle,
                    
                    -- Dimensions descriptives
                    dt.date_complete,
                    dt.annee,
                    dt.trimestre,
                    dt.mois,
                    
                    -- Pas de sk_etablissement dans fait_consultation, on utilise -1 (Inconnu)
                    -1 as sk_etablissement,
                    'Etablissement Inconnu' as nom_etablissement,
                    'Non renseigne' as region_etablissement,
                    '00' as departement_etablissement,
                    
                    dd.code_diagnostic,
                    dd.libelle_diagnostic,
                    dd.chapitre_cim10,
                    dd.categorie_cim10,
                    
                    dp.nom as nom_professionnel,
                    dp.prenom as prenom_professionnel,
                    ds.specialite,
                    ds.fonction,
                    
                    dp2.sexe,
                    dp2.tranche_age,
                    dp2.age,
                    
                    -- Mesures
                    fc.nombre_consultations,
                    fc.duree_consultation
                    
                FROM pg.dwh.fait_consultation fc
                LEFT JOIN pg.dwh.dim_temps dt ON fc.sk_temps = dt.sk_temps
                LEFT JOIN pg.dwh.dim_diagnostic dd ON fc.sk_diagnostic = dd.sk_diagnostic
                LEFT JOIN pg.dwh.dim_professionnel dp ON fc.sk_professionnel = dp.sk_professionnel
                LEFT JOIN pg.dwh.dim_specialite ds ON dp.fk_specialite = ds.sk_specialite
                LEFT JOIN pg.dwh.dim_patient dp2 ON fc.sk_patient = dp2.sk_patient
                WHERE dp.est_actuel = true
            ),
            
            agreg_etablissement AS (
                SELECT 
                    sk_temps,
                    sk_etablissement,
                    nom_etablissement,
                    region_etablissement,
                    departement_etablissement,
                    annee,
                    trimestre,
                    mois,
                    date_complete,
                    
                    SUM(nombre_consultations) as nb_consultations_etablissement,
                    SUM(duree_consultation) as duree_totale_etablissement,
                    COUNT(DISTINCT sk_patient) as nb_patients_uniques_etablissement,
                    COUNT(DISTINCT sk_professionnel) as nb_professionnels_etablissement
                    
                FROM consultations_base
                GROUP BY 1,2,3,4,5,6,7,8,9
            ),
            
            agreg_diagnostic AS (
                SELECT 
                    sk_temps,
                    sk_etablissement,
                    sk_diagnostic,
                    code_diagnostic,
                    libelle_diagnostic,
                    chapitre_cim10,
                    categorie_cim10,
                    annee,
                    trimestre,
                    mois,
                    date_complete,
                    
                    SUM(nombre_consultations) as nb_consultations_diagnostic,
                    SUM(duree_consultation) as duree_totale_diagnostic,
                    COUNT(DISTINCT sk_patient) as nb_patients_uniques_diagnostic
                    
                FROM consultations_base
                GROUP BY 1,2,3,4,5,6,7,8,9,10,11
            ),
            
            agreg_professionnel AS (
                SELECT 
                    sk_temps,
                    sk_professionnel,
                    nom_professionnel,
                    prenom_professionnel,
                    specialite,
                    fonction,
                    annee,
                    trimestre,
                    mois,
                    date_complete,
                    
                    SUM(nombre_consultations) as nb_consultations_professionnel,
                    SUM(duree_consultation) as duree_totale_professionnel,
                    COUNT(DISTINCT sk_patient) as nb_patients_uniques_professionnel,
                    COUNT(DISTINCT sk_etablissement) as nb_etablissements_professionnel
                    
                FROM consultations_base
                GROUP BY 1,2,3,4,5,6,7,8,9,10
            ),
            
            agreg_patient AS (
                SELECT 
                    sk_temps,
                    sexe,
                    tranche_age,
                    age,
                    annee,
                    trimestre,
                    mois,
                    date_complete,
                    
                    SUM(nombre_consultations) as nb_consultations_profil,
                    SUM(duree_consultation) as duree_totale_profil,
                    COUNT(DISTINCT sk_patient) as nb_patients_uniques_profil,
                    COUNT(DISTINCT sk_etablissement) as nb_etablissements_profil
                    
                FROM consultations_base
                WHERE sexe != 'I' AND tranche_age != 'Non renseigne'
                GROUP BY 1,2,3,4,5,6,7,8
            ),
            
            final AS (
                SELECT 
                    -- Clés temporelles
                    cb.sk_temps,
                    cb.date_complete,
                    cb.annee,
                    cb.trimestre,
                    cb.mois,
                    
                    -- Clés et libellés établissement
                    cb.sk_etablissement,
                    cb.nom_etablissement,
                    cb.region_etablissement,
                    cb.departement_etablissement,
                    
                    -- Clés et libellés diagnostic
                    cb.sk_diagnostic,
                    cb.code_diagnostic,
                    cb.libelle_diagnostic,
                    cb.chapitre_cim10,
                    cb.categorie_cim10,
                    
                    -- Clés et libellés professionnel
                    cb.sk_professionnel,
                    cb.nom_professionnel,
                    cb.prenom_professionnel,
                    cb.specialite,
                    cb.fonction,
                    
                    -- Profil patient
                    cb.sexe,
                    cb.tranche_age,
                    cb.age,
                    
                    -- Mesures agrégées
                    COALESCE(ae.nb_consultations_etablissement, 0) as nb_consultations_etablissement,
                    COALESCE(ae.duree_totale_etablissement, 0) as duree_totale_etablissement,
                    COALESCE(ae.nb_patients_uniques_etablissement, 0) as nb_patients_uniques_etablissement,
                    
                    COALESCE(ad.nb_consultations_diagnostic, 0) as nb_consultations_diagnostic,
                    COALESCE(ad.duree_totale_diagnostic, 0) as duree_totale_diagnostic,
                    COALESCE(ad.nb_patients_uniques_diagnostic, 0) as nb_patients_uniques_diagnostic,
                    
                    COALESCE(aprof.nb_consultations_professionnel, 0) as nb_consultations_professionnel,
                    COALESCE(aprof.duree_totale_professionnel, 0) as duree_totale_professionnel,
                    COALESCE(aprof.nb_patients_uniques_professionnel, 0) as nb_patients_uniques_professionnel,
                    
                    COALESCE(apat.nb_consultations_profil, 0) as nb_consultations_profil,
                    COALESCE(apat.duree_totale_profil, 0) as duree_totale_profil,
                    COALESCE(apat.nb_patients_uniques_profil, 0) as nb_patients_uniques_profil,
                    
                    -- Métadonnées
                    CURRENT_TIMESTAMP as date_chargement
                    
                FROM consultations_base cb
                LEFT JOIN agreg_etablissement ae ON cb.sk_temps = ae.sk_temps AND cb.sk_etablissement = ae.sk_etablissement
                LEFT JOIN agreg_diagnostic ad ON cb.sk_temps = ad.sk_temps AND cb.sk_etablissement = ad.sk_etablissement AND cb.sk_diagnostic = ad.sk_diagnostic
                LEFT JOIN agreg_professionnel aprof ON cb.sk_temps = aprof.sk_temps AND cb.sk_professionnel = aprof.sk_professionnel
                LEFT JOIN agreg_patient apat ON cb.sk_temps = apat.sk_temps AND cb.sexe = apat.sexe AND cb.tranche_age = apat.tranche_age
            )
            
            SELECT * FROM final
        """,
        
        'dm_analyse_territoriale': """
            WITH deces_base AS (
                SELECT 
                    fd.sk_temps,
                    fd.sk_localisation,
                    fd.sk_patient,
                    
                    -- Dimensions descriptives
                    dt.date_complete,
                    dt.annee,
                    dt.trimestre,
                    dt.mois,
                    
                    dl.region,
                    dl.departement,
                    dl.ville,
                    dl.code_postal,
                    
                    dp.sexe,
                    dp.tranche_age,
                    dp.age,
                    
                    -- Mesures
                    fd.nombre_deces
                    
                FROM pg.dwh.fait_deces fd
                LEFT JOIN pg.dwh.dim_temps dt ON fd.sk_temps = dt.sk_temps
                LEFT JOIN pg.dwh.dim_localisation dl ON fd.sk_localisation = dl.sk_localisation
                LEFT JOIN pg.dwh.dim_patient dp ON fd.sk_patient = dp.sk_patient
                WHERE dl.region IS NOT NULL AND dl.region != 'Non renseigne'
            ),
            
            satisfaction_base AS (
                SELECT 
                    fs.sk_temps,
                    fs.sk_etablissement,
                    fs.sk_localisation,
                    
                    -- Dimensions descriptives
                    dt.date_complete,
                    dt.annee,
                    dt.trimestre,
                    dt.mois,
                    
                    de.region as region_etablissement,
                    de.departement as departement_etablissement,
                    de.nom_etablissement,
                    
                    -- Pas de sk_patient dans fait_satisfaction
                    'I' as sexe,
                    'Non renseigne' as tranche_age,
                    0 as age,
                    
                    -- Mesures satisfaction
                    fs.score_global as note_satisfaction,
                    fs.nombre_reponses
                    
                FROM pg.dwh.fait_satisfaction fs
                LEFT JOIN pg.dwh.dim_temps dt ON fs.sk_temps = dt.sk_temps
                LEFT JOIN pg.dwh.dim_etablissement de ON fs.sk_etablissement = de.sk_etablissement
                WHERE de.region IS NOT NULL AND de.region != 'Non renseigne'
            ),
            
            agreg_deces_region AS (
                SELECT 
                    sk_temps,
                    region,
                    annee,
                    trimestre,
                    mois,
                    date_complete,
                    
                    SUM(nombre_deces) as nb_deces_region,
                    COUNT(DISTINCT sk_patient) as nb_patients_deces_region,
                    
                    SUM(CASE WHEN sexe = 'M' THEN nombre_deces ELSE 0 END) as nb_deces_hommes,
                    SUM(CASE WHEN sexe = 'F' THEN nombre_deces ELSE 0 END) as nb_deces_femmes,
                    
                    SUM(CASE WHEN tranche_age = '0-18' THEN nombre_deces ELSE 0 END) as nb_deces_0_18,
                    SUM(CASE WHEN tranche_age = '19-30' THEN nombre_deces ELSE 0 END) as nb_deces_19_30,
                    SUM(CASE WHEN tranche_age = '31-50' THEN nombre_deces ELSE 0 END) as nb_deces_31_50,
                    SUM(CASE WHEN tranche_age = '51-65' THEN nombre_deces ELSE 0 END) as nb_deces_51_65,
                    SUM(CASE WHEN tranche_age = '66+' THEN nombre_deces ELSE 0 END) as nb_deces_66_plus
                    
                FROM deces_base
                GROUP BY 1,2,3,4,5,6
            ),
            
            agreg_satisfaction_region AS (
                SELECT 
                    sk_temps,
                    region_etablissement,
                    annee,
                    trimestre,
                    mois,
                    date_complete,
                    
                    SUM(nombre_reponses) as nb_reponses_satisfaction,
                    AVG(note_satisfaction) as note_moyenne_satisfaction,
                    0 as nb_patients_satisfaction,
                    COUNT(DISTINCT sk_etablissement) as nb_etablissements_satisfaction,
                    
                    SUM(CASE WHEN sexe = 'M' THEN nombre_reponses ELSE 0 END) as nb_reponses_hommes,
                    SUM(CASE WHEN sexe = 'F' THEN nombre_reponses ELSE 0 END) as nb_reponses_femmes,
                    AVG(CASE WHEN sexe = 'M' THEN note_satisfaction END) as note_moyenne_hommes,
                    AVG(CASE WHEN sexe = 'F' THEN note_satisfaction END) as note_moyenne_femmes
                    
                FROM satisfaction_base
                GROUP BY 1,2,3,4,5,6
            ),
            
            final AS (
                SELECT 
                    -- Clés temporelles
                    COALESCE(dr.sk_temps, sr.sk_temps) as sk_temps,
                    COALESCE(dr.date_complete, sr.date_complete) as date_complete,
                    COALESCE(dr.annee, sr.annee) as annee,
                    COALESCE(dr.trimestre, sr.trimestre) as trimestre,
                    COALESCE(dr.mois, sr.mois) as mois,
                    
                    -- Géographie
                    COALESCE(dr.region, sr.region_etablissement) as region,
                    
                    -- Indicateurs décès
                    COALESCE(dr.nb_deces_region, 0) as nb_deces_region,
                    COALESCE(dr.nb_patients_deces_region, 0) as nb_patients_deces_region,
                    COALESCE(dr.nb_deces_hommes, 0) as nb_deces_hommes,
                    COALESCE(dr.nb_deces_femmes, 0) as nb_deces_femmes,
                    COALESCE(dr.nb_deces_0_18, 0) as nb_deces_0_18,
                    COALESCE(dr.nb_deces_19_30, 0) as nb_deces_19_30,
                    COALESCE(dr.nb_deces_31_50, 0) as nb_deces_31_50,
                    COALESCE(dr.nb_deces_51_65, 0) as nb_deces_51_65,
                    COALESCE(dr.nb_deces_66_plus, 0) as nb_deces_66_plus,
                    
                    -- Indicateurs satisfaction
                    COALESCE(sr.nb_reponses_satisfaction, 0) as nb_reponses_satisfaction,
                    COALESCE(sr.note_moyenne_satisfaction, 0) as note_moyenne_satisfaction,
                    0 as nb_patients_satisfaction,
                    COALESCE(sr.nb_etablissements_satisfaction, 0) as nb_etablissements_satisfaction,
                    COALESCE(sr.nb_reponses_hommes, 0) as nb_reponses_hommes,
                    COALESCE(sr.nb_reponses_femmes, 0) as nb_reponses_femmes,
                    COALESCE(sr.note_moyenne_hommes, 0) as note_moyenne_hommes,
                    COALESCE(sr.note_moyenne_femmes, 0) as note_moyenne_femmes,
                    
                    -- Métadonnées
                    CURRENT_TIMESTAMP as date_chargement
                    
                FROM agreg_deces_region dr
                FULL OUTER JOIN agreg_satisfaction_region sr 
                    ON dr.sk_temps = sr.sk_temps AND dr.region = sr.region_etablissement
            )
            
            SELECT * FROM final
        """,
        
        'dm_hospitalisations_agregees': """
            WITH hospitalisations_base AS (
                SELECT 
                    fh.sk_temps,
                    fh.sk_etablissement,
                    fh.sk_diagnostic,
                    fh.sk_patient,
                    
                    -- Dimensions descriptives
                    dt.date_complete,
                    dt.annee,
                    dt.trimestre,
                    dt.mois,
                    
                    de.nom_etablissement,
                    de.region as region_etablissement,
                    de.departement as departement_etablissement,
                    
                    dd.code_diagnostic,
                    dd.libelle_diagnostic,
                    dd.chapitre_cim10,
                    dd.categorie_cim10,
                    
                    dp.sexe,
                    dp.tranche_age,
                    dp.age,
                    
                    -- Mesures
                    fh.nombre_hospitalisations,
                    fh.jour_hospitalisation
                    
                FROM pg.dwh.fait_hospitalisation fh
                LEFT JOIN pg.dwh.dim_temps dt ON fh.sk_temps = dt.sk_temps
                LEFT JOIN pg.dwh.dim_etablissement de ON fh.sk_etablissement = de.sk_etablissement
                LEFT JOIN pg.dwh.dim_diagnostic dd ON fh.sk_diagnostic = dd.sk_diagnostic
                LEFT JOIN pg.dwh.dim_patient dp ON fh.sk_patient = dp.sk_patient
            ),
            
            agreg_etablissement AS (
                SELECT 
                    sk_temps,
                    sk_etablissement,
                    nom_etablissement,
                    region_etablissement,
                    departement_etablissement,
                    annee,
                    trimestre,
                    mois,
                    date_complete,
                    
                    SUM(nombre_hospitalisations) as nb_hospitalisations_etablissement,
                    SUM(jour_hospitalisation) as duree_totale_etablissement,
                    COUNT(DISTINCT sk_patient) as nb_patients_uniques_etablissement,
                    AVG(jour_hospitalisation) as duree_moyenne_etablissement
                    
                FROM hospitalisations_base
                GROUP BY 1,2,3,4,5,6,7,8,9
            ),
            
            agreg_diagnostic AS (
                SELECT 
                    sk_temps,
                    sk_etablissement,
                    sk_diagnostic,
                    code_diagnostic,
                    libelle_diagnostic,
                    chapitre_cim10,
                    categorie_cim10,
                    annee,
                    trimestre,
                    mois,
                    date_complete,
                    
                    SUM(nombre_hospitalisations) as nb_hospitalisations_diagnostic,
                    SUM(jour_hospitalisation) as duree_totale_diagnostic,
                    COUNT(DISTINCT sk_patient) as nb_patients_uniques_diagnostic,
                    AVG(jour_hospitalisation) as duree_moyenne_diagnostic
                    
                FROM hospitalisations_base
                GROUP BY 1,2,3,4,5,6,7,8,9,10,11
            ),
            
            agreg_patient AS (
                SELECT 
                    sk_temps,
                    sexe,
                    tranche_age,
                    age,
                    annee,
                    trimestre,
                    mois,
                    date_complete,
                    
                    SUM(nombre_hospitalisations) as nb_hospitalisations_profil,
                    SUM(jour_hospitalisation) as duree_totale_profil,
                    COUNT(DISTINCT sk_patient) as nb_patients_uniques_profil,
                    COUNT(DISTINCT sk_etablissement) as nb_etablissements_profil,
                    AVG(jour_hospitalisation) as duree_moyenne_profil
                    
                FROM hospitalisations_base
                WHERE sexe != 'I' AND tranche_age != 'Non renseigne'
                GROUP BY 1,2,3,4,5,6,7,8
            ),
            
            agreg_region AS (
                SELECT 
                    sk_temps,
                    region_etablissement,
                    annee,
                    trimestre,
                    mois,
                    date_complete,
                    
                    SUM(nombre_hospitalisations) as nb_hospitalisations_region,
                    SUM(jour_hospitalisation) as duree_totale_region,
                    COUNT(DISTINCT sk_patient) as nb_patients_uniques_region,
                    COUNT(DISTINCT sk_etablissement) as nb_etablissements_region,
                    AVG(jour_hospitalisation) as duree_moyenne_region
                    
                FROM hospitalisations_base
                WHERE region_etablissement IS NOT NULL AND region_etablissement != 'Non renseigne'
                GROUP BY 1,2,3,4,5,6
            ),
            
            final AS (
                SELECT 
                    -- Clés temporelles
                    hb.sk_temps,
                    hb.date_complete,
                    hb.annee,
                    hb.trimestre,
                    hb.mois,
                    
                    -- Clés et libellés établissement
                    hb.sk_etablissement,
                    hb.nom_etablissement,
                    hb.region_etablissement,
                    hb.departement_etablissement,
                    
                    -- Clés et libellés diagnostic
                    hb.sk_diagnostic,
                    hb.code_diagnostic,
                    hb.libelle_diagnostic,
                    hb.chapitre_cim10,
                    hb.categorie_cim10,
                    
                    -- Profil patient
                    hb.sexe,
                    hb.tranche_age,
                    hb.age,
                    
                    -- Mesures agrégées par établissement
                    COALESCE(ae.nb_hospitalisations_etablissement, 0) as nb_hospitalisations_etablissement,
                    COALESCE(ae.duree_totale_etablissement, 0) as duree_totale_etablissement,
                    COALESCE(ae.nb_patients_uniques_etablissement, 0) as nb_patients_uniques_etablissement,
                    COALESCE(ae.duree_moyenne_etablissement, 0) as duree_moyenne_etablissement,
                    
                    -- Mesures agrégées par diagnostic
                    COALESCE(ad.nb_hospitalisations_diagnostic, 0) as nb_hospitalisations_diagnostic,
                    COALESCE(ad.duree_totale_diagnostic, 0) as duree_totale_diagnostic,
                    COALESCE(ad.nb_patients_uniques_diagnostic, 0) as nb_patients_uniques_diagnostic,
                    COALESCE(ad.duree_moyenne_diagnostic, 0) as duree_moyenne_diagnostic,
                    
                    -- Mesures agrégées par profil patient
                    COALESCE(apat.nb_hospitalisations_profil, 0) as nb_hospitalisations_profil,
                    COALESCE(apat.duree_totale_profil, 0) as duree_totale_profil,
                    COALESCE(apat.nb_patients_uniques_profil, 0) as nb_patients_uniques_profil,
                    COALESCE(apat.duree_moyenne_profil, 0) as duree_moyenne_profil,
                    
                    -- Mesures agrégées par région
                    COALESCE(areg.nb_hospitalisations_region, 0) as nb_hospitalisations_region,
                    COALESCE(areg.duree_totale_region, 0) as duree_totale_region,
                    COALESCE(areg.nb_patients_uniques_region, 0) as nb_patients_uniques_region,
                    COALESCE(areg.duree_moyenne_region, 0) as duree_moyenne_region,
                    
                    -- Métadonnées
                    CURRENT_TIMESTAMP as date_chargement
                    
                FROM hospitalisations_base hb
                LEFT JOIN agreg_etablissement ae ON hb.sk_temps = ae.sk_temps AND hb.sk_etablissement = ae.sk_etablissement
                LEFT JOIN agreg_diagnostic ad ON hb.sk_temps = ad.sk_temps AND hb.sk_etablissement = ad.sk_etablissement AND hb.sk_diagnostic = ad.sk_diagnostic
                LEFT JOIN agreg_patient apat ON hb.sk_temps = apat.sk_temps AND hb.sexe = apat.sexe AND hb.tranche_age = apat.tranche_age
                LEFT JOIN agreg_region areg ON hb.sk_temps = areg.sk_temps AND hb.region_etablissement = areg.region_etablissement
            )
            
            SELECT * FROM final
        """
    }
    
    return queries.get(table_name)


def drop_and_recreate_datamart_table(duck_conn, table_name):
    """
    Supprimer et recréer une table du datamart dans PostgreSQL
    """
    try:
        print("  [INFO] Suppression de la table existante si présente...")
        drop_query = f"DROP TABLE IF EXISTS pg.{DATAMART_SCHEMA}.{table_name} CASCADE;"
        duck_conn.execute(drop_query)
        print(f"  [OK] Table {table_name} supprimée")
        return True
        
    except Exception as e:
        print(f"  [ERREUR] Impossible de supprimer la table : {e}")
        return False


def build_datamart_table(duck_conn, table_name):
    """
    Créer une table du datamart directement dans PostgreSQL via DuckDB
    """
    print(f"\n{'='*70}")
    print(f"[{table_name}] Construction en cours...")
    print(f"{'='*70}")
    
    start_time = time.time()
    
    try:
        # 1. Supprimer la table existante
        if not drop_and_recreate_datamart_table(duck_conn, table_name):
            return False
        
        # 2. Récupérer la requête SQL
        query = get_datamart_query(table_name)
        if not query:
            print(f"  [ERREUR] Pas de requête disponible pour {table_name}")
            return False
        
        print("  [INFO] Exécution de la requête...")
        print(f"  [INFO] Source : pg.{DWH_SCHEMA}.*")
        print(f"  [INFO] Destination : pg.{DATAMART_SCHEMA}.{table_name}")
        
        # 3. Créer la table dans PostgreSQL via CREATE TABLE AS
        create_query = f"""
            CREATE TABLE pg.{DATAMART_SCHEMA}.{table_name} AS
            {query}
        """
        
        duck_conn.execute(create_query)
        
        # 4. Compter les lignes créées
        count_query = f"SELECT COUNT(*) FROM pg.{DATAMART_SCHEMA}.{table_name};"
        result = duck_conn.execute(count_query).fetchone()
        nb_lignes = result[0] if result else 0
        
        elapsed_time = time.time() - start_time
        speed = nb_lignes / elapsed_time if elapsed_time > 0 else 0
        
        print(f"  [OK] Table créée avec succès")
        print(f"  [STATS] {nb_lignes:,} lignes en {elapsed_time:.1f}s ({speed:,.0f} lignes/s)")
        
        return True
        
    except Exception as e:
        print(f"  [ERREUR] Échec : {e}")
        return False


def main():
    """Fonction principale"""
    
    print("=" * 70)
    print("BUILD DATAMART VIA POSTGRES : Optimisé")
    print("=" * 70)
    print()
    print("[ARCHITECTURE]")
    print("  1. DWH déjà présent dans PostgreSQL (schéma 'dwh')")
    print("  2. DuckDB se connecte à PostgreSQL via extension postgres")
    print("  3. DuckDB crée le datamart dans PostgreSQL (schéma 'datamart')")
    print("  4. Plus de transfert de données volumineuses !")
    print()
    print(f"[CONFIG] PostgreSQL : {POSTGRES_CONFIG['host']}:{POSTGRES_CONFIG['port']}/{POSTGRES_CONFIG['database']}")
    print(f"[CONFIG] Schéma source : {DWH_SCHEMA}")
    print(f"[CONFIG] Schéma destination : {DATAMART_SCHEMA}")
    print()
    
    # Connexion DuckDB + PostgreSQL
    duck_conn = connect_duckdb_with_postgres()
    if not duck_conn:
        print("[ERREUR] Impossible de se connecter")
        sys.exit(1)
    
    print()
    print(f"[INFO] {len(DATAMART_TABLES)} tables à créer")
    print()
    
    total_start_time = time.time()
    success_count = 0
    
    try:
        for idx, table in enumerate(DATAMART_TABLES, 1):
            print(f"\n[{idx}/{len(DATAMART_TABLES)}] {table}")
            
            if build_datamart_table(duck_conn, table):
                success_count += 1
            else:
                print(f"  [ATTENTION] Échec pour {table}, passage au suivant...")
        
        total_elapsed = time.time() - total_start_time
        
        print()
        print("=" * 70)
        print(f"[RÉSULTAT] {success_count}/{len(DATAMART_TABLES)} tables créées avec succès")
        print(f"[STATS] Temps total : {total_elapsed:.1f}s ({total_elapsed/60:.1f} min)")
        print("=" * 70)
        print()
        
        if success_count == len(DATAMART_TABLES):
            print("✅ SUCCÈS ! Datamart créé directement dans PostgreSQL")
            print()
            print("Avantages de cette méthode :")
            print("  ✅ Pas de création du datamart dans DuckDB local")
            print("  ✅ Pas de transfert de 45M+ lignes")
            print("  ✅ Tout se passe dans PostgreSQL via DuckDB")
            print("  ✅ Beaucoup plus rapide et optimisé")
            print()
            print("Vérification dans PostgreSQL :")
            print(f"  psql -h {POSTGRES_CONFIG['host']} -U {POSTGRES_CONFIG['user']} -d {POSTGRES_CONFIG['database']}")
            print(f"  \\dt {DATAMART_SCHEMA}.*")
            print(f"  SELECT COUNT(*) FROM {DATAMART_SCHEMA}.dm_consultations_agregees;")
        else:
            print(f"⚠️  {len(DATAMART_TABLES) - success_count} table(s) en échec")
        
    except KeyboardInterrupt:
        print("\n[ATTENTION] Traitement interrompu par l'utilisateur")
        sys.exit(1)
    except Exception as e:
        print(f"\n[ERREUR] Traitement interrompu : {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    
    finally:
        # Fermer la connexion DuckDB
        duck_conn.close()
        print("\n[INFO] Connexion fermée")


if __name__ == '__main__':
    main()

