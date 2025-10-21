#!/usr/bin/env python3
"""
Script pour exporter les tables DWH de DuckDB vers PostgreSQL
Usage: python export_dwh_to_postgres.py

Ce script :
1. Lit les tables DWH depuis DuckDB (schéma 'dwh')
2. Les exporte vers PostgreSQL (schéma 'datawarehouse')
3. Gère l'upsert (INSERT ou UPDATE selon si la table existe)
"""

import duckdb
import psycopg2
from psycopg2.extras import execute_batch
import os
import sys
from datetime import datetime

# Configuration PostgreSQL (depuis variables d'environnement ou valeurs par défaut)
POSTGRES_CONFIG = {
    'host': os.getenv('DWH_POSTGRES_HOST', 'localhost'),
    'port': int(os.getenv('DWH_POSTGRES_PORT', '5432')),
    'database': os.getenv('DWH_POSTGRES_DB', 'dwh'),
    'user': os.getenv('DWH_POSTGRES_USER', 'admin'),
    'password': os.getenv('DWH_POSTGRES_PASSWORD', 'admin')
}

# Configuration DuckDB
DUCKDB_PATH = 'data/duckdb/staging.duckdb'
DUCKDB_SCHEMA = 'dwh'

# Schema PostgreSQL cible
POSTGRES_SCHEMA = 'datawarehouse'

# Tables à exporter (dans l'ordre des dépendances)
TABLES_A_EXPORTER = {
    'dimensions': [
        'dim_temps',
        'dim_specialite',
        'dim_mutuelle',
        'dim_diagnostic',
        'dim_localisation',
        'dim_etablissement',
        'dim_patient',
        'dim_professionnel'
    ],
    'faits': [
        'fait_consultation',
        'fait_hospitalisation',
        'fait_deces',
        'fait_satisfaction',
        'fait_qualite_soins'
    ]
}


def connect_duckdb():
    """Connexion à DuckDB"""
    try:
        conn = duckdb.connect(DUCKDB_PATH, read_only=True)
        print(f"[OK] Connecte a DuckDB: {DUCKDB_PATH}")
        return conn
    except Exception as e:
        print(f"[ERREUR] Connexion DuckDB: {e}")
        sys.exit(1)


def connect_postgres():
    """Connexion à PostgreSQL"""
    try:
        conn = psycopg2.connect(**POSTGRES_CONFIG)
        print(f"[OK] Connecte a PostgreSQL: {POSTGRES_CONFIG['host']}:{POSTGRES_CONFIG['port']}/{POSTGRES_CONFIG['database']}")
        return conn
    except Exception as e:
        print(f"[ERREUR] Connexion PostgreSQL: {e}")
        print(f"[INFO] Verifiez vos credentials PostgreSQL")
        sys.exit(1)


def create_schema_if_not_exists(pg_conn):
    """Créer le schéma datawarehouse s'il n'existe pas"""
    try:
        cursor = pg_conn.cursor()
        cursor.execute(f"CREATE SCHEMA IF NOT EXISTS {POSTGRES_SCHEMA};")
        pg_conn.commit()
        cursor.close()
        print(f"[OK] Schema '{POSTGRES_SCHEMA}' verifie/cree")
    except Exception as e:
        print(f"[ERREUR] Creation schema: {e}")
        pg_conn.rollback()


def export_table(duck_conn, pg_conn, table_name):
    """
    Exporte une table de DuckDB vers PostgreSQL
    
    Stratégie :
    1. DROP + CREATE TABLE (mode simple, réinitialise la table)
    2. INSERT par batch de 10000 lignes
    """
    
    print(f"\n[{table_name}] Export en cours...")
    
    try:
        # 1. Lire depuis DuckDB
        query = f"SELECT * FROM {DUCKDB_SCHEMA}.{table_name};"
        df = duck_conn.execute(query).fetchdf()
        
        if df.empty:
            print(f"  [ATTENTION] Table vide : {table_name}")
            return
        
        nb_lignes = len(df)
        print(f"  [INFO] {nb_lignes:,} lignes lues depuis DuckDB")
        
        # 2. DROP la table PostgreSQL si elle existe
        cursor = pg_conn.cursor()
        cursor.execute(f"DROP TABLE IF EXISTS {POSTGRES_SCHEMA}.{table_name} CASCADE;")
        pg_conn.commit()
        
        # 3. Créer la table PostgreSQL depuis le DataFrame pandas
        # Utiliser DuckDB pour générer le CREATE TABLE
        create_table_sql = duck_conn.execute(
            f"SELECT sql FROM duckdb_tables() WHERE schema_name = '{DUCKDB_SCHEMA}' AND table_name = '{table_name}';"
        ).fetchone()
        
        if create_table_sql:
            # Adapter le SQL pour PostgreSQL (remplacer dwh. par datawarehouse.)
            sql_postgres = create_table_sql[0].replace(f'{DUCKDB_SCHEMA}.', f'{POSTGRES_SCHEMA}.')
            cursor.execute(sql_postgres)
            pg_conn.commit()
        else:
            # Fallback : utiliser pandas to_sql
            print(f"  [INFO] Creation table avec pandas...")
        
        # 4. Insérer les données par batch
        print(f"  [INFO] Insertion des donnees...")
        
        # Préparer la requête INSERT
        colonnes = ', '.join([f'"{col}"' for col in df.columns])
        placeholders = ', '.join(['%s'] * len(df.columns))
        insert_sql = f"INSERT INTO {POSTGRES_SCHEMA}.{table_name} ({colonnes}) VALUES ({placeholders});"
        
        # Convertir DataFrame en liste de tuples
        data = [tuple(row) for row in df.itertuples(index=False, name=None)]
        
        # INSERT par batch de 10000
        batch_size = 10000
        for i in range(0, len(data), batch_size):
            batch = data[i:i + batch_size]
            execute_batch(cursor, insert_sql, batch, page_size=1000)
            pg_conn.commit()
            print(f"  [PROGRES] {min(i + batch_size, nb_lignes):,} / {nb_lignes:,} lignes inserees")
        
        cursor.close()
        print(f"  [OK] {table_name} exporte avec succes ({nb_lignes:,} lignes)")
        
    except Exception as e:
        print(f"  [ERREUR] {table_name}: {e}")
        pg_conn.rollback()
        raise


def main():
    """Fonction principale"""
    
    print("="*60)
    print("EXPORT DWH : DuckDB → PostgreSQL")
    print("="*60)
    print()
    
    # Vérifier que DuckDB existe
    if not os.path.exists(DUCKDB_PATH):
        print(f"[ERREUR] Fichier DuckDB introuvable: {DUCKDB_PATH}")
        print(f"[INFO] Executez d'abord: dbt run")
        sys.exit(1)
    
    # Connexions
    duck_conn = connect_duckdb()
    pg_conn = connect_postgres()
    
    # Créer le schéma PostgreSQL
    create_schema_if_not_exists(pg_conn)
    
    # Exporter toutes les tables
    total_tables = sum(len(tables) for tables in TABLES_A_EXPORTER.values())
    current = 0
    
    print(f"\n[INFO] Export de {total_tables} tables en cours...")
    print()
    
    try:
        # 1. Exporter les dimensions d'abord (pas de FK)
        print("[PHASE 1/2] Export des DIMENSIONS...")
        print("-" * 60)
        for table in TABLES_A_EXPORTER['dimensions']:
            current += 1
            print(f"[{current}/{total_tables}] {table}")
            export_table(duck_conn, pg_conn, table)
        
        # 2. Exporter les faits ensuite (avec FK vers dimensions)
        print()
        print("[PHASE 2/2] Export des FAITS...")
        print("-" * 60)
        for table in TABLES_A_EXPORTER['faits']:
            current += 1
            print(f"[{current}/{total_tables}] {table}")
            export_table(duck_conn, pg_conn, table)
        
        print()
        print("="*60)
        print(f"[SUCCES] {total_tables} tables exportees avec succes !")
        print("="*60)
        
    except Exception as e:
        print()
        print("="*60)
        print(f"[ERREUR] Export interrompu: {e}")
        print("="*60)
        sys.exit(1)
    
    finally:
        # Fermer les connexions
        duck_conn.close()
        pg_conn.close()
        print()
        print("[INFO] Connexions fermees")


if __name__ == '__main__':
    main()


