#!/usr/bin/env python3
"""
Script SIMPLE pour pousser les data marts
Utilise DROP + CREATE au lieu de TRUNCATE pour éviter les conflits
"""

import duckdb
import psycopg2
import os
import sys
from pathlib import Path
import time
import pandas as pd
import io

# Essayer de charger dotenv
try:
    from dotenv import load_dotenv
    load_dotenv()
    print("[INFO] Fichier .env charge")
except:
    print("[INFO] python-dotenv non installe ou .env absent, utilisation valeurs par defaut")

# Configuration PostgreSQL
POSTGRES_CONFIG = {
    'host': os.getenv('DWH_POSTGRES_HOST', os.getenv('POSTGRES_HOST', 'localhost')),
    'port': int(os.getenv('DWH_POSTGRES_PORT', os.getenv('POSTGRES_PORT', '5432'))),
    'database': os.getenv('DWH_POSTGRES_DB', os.getenv('POSTGRES_DB', 'healthcare_dwh')),
    'user': os.getenv('DWH_POSTGRES_USER', os.getenv('POSTGRES_USER', 'admin')),
    'password': os.getenv('DWH_POSTGRES_PASSWORD', os.getenv('POSTGRES_PASSWORD', 'admin'))
}

# Configuration DuckDB
DUCKDB_PATH = 'data/duckdb/staging.duckdb'
DUCKDB_SCHEMA = 'datamart'
POSTGRES_SCHEMA = 'datamart'

# Tables à traiter (par ordre de priorité)
TABLES_TO_PROCESS = [
    'dm_analyse_territoriale',      # ~30K lignes
    'dm_hospitalisations_agregees', # ~6K lignes
    'dm_consultations_agregees'     # ~45M lignes (le gros morceau)
]

def connect_duckdb():
    """Connexion à DuckDB"""
    try:
        conn = duckdb.connect(DUCKDB_PATH, read_only=True)
        print(f"[OK] Connecte a DuckDB: {DUCKDB_PATH}")
        return conn
    except Exception as e:
        print(f"[ERREUR] Connexion DuckDB: {e}")
        return None

def connect_postgres():
    """Connexion à PostgreSQL"""
    try:
        conn = psycopg2.connect(**POSTGRES_CONFIG)
        print(f"[OK] Connecte a PostgreSQL: {POSTGRES_CONFIG['host']}:{POSTGRES_CONFIG['port']}/{POSTGRES_CONFIG['database']}")
        return conn
    except Exception as e:
        print(f"[ERREUR] Connexion PostgreSQL: {e}")
        return None

def get_table_count(duck_conn, table_name):
    """Compte le nombre de lignes dans une table"""
    try:
        query = f"SELECT COUNT(*) FROM {DUCKDB_SCHEMA}.{table_name};"
        result = duck_conn.execute(query).fetchone()
        return result[0] if result else 0
    except:
        return 0

def drop_and_recreate_table(pg_conn, table_name):
    """Supprime et recrée une table PostgreSQL"""
    
    cursor = pg_conn.cursor()
    
    try:
        # 1. Supprimer la table si elle existe
        drop_sql = f"DROP TABLE IF EXISTS {POSTGRES_SCHEMA}.{table_name} CASCADE;"
        cursor.execute(drop_sql)
        pg_conn.commit()
        print(f"  [INFO] Table {table_name} supprimee")
        
        # 2. Recréer la table en copiant la structure depuis init_datamart.sql
        # Pour simplifier, on va utiliser CREATE TABLE AS SELECT avec LIMIT 0
        print(f"  [INFO] Recreation de la table {table_name}...")
        print(f"  [ATTENTION] Executez d'abord: psql -h localhost -U admin -d healthcare_dwh -f scripts/init/init_datamart.sql")
        print(f"  [ATTENTION] Puis relancez ce script")
        
        return False  # Indique qu'il faut recréer manuellement
        
    except Exception as e:
        print(f"  [ERREUR] Impossible de recreer la table: {e}")
        pg_conn.rollback()
        return False
    finally:
        cursor.close()

def push_table_simple(duck_conn, pg_conn, table_name):
    """Push une table avec méthode simple"""
    
    print(f"\n[{table_name}] Push simple en cours...")
    start_time = time.time()
    
    try:
        # 1. Compter le nombre total de lignes
        total_rows = get_table_count(duck_conn, table_name)
        
        if total_rows == 0:
            print(f"  [ATTENTION] Table vide: {table_name}")
            return True
        
        print(f"  [INFO] {total_rows:,} lignes a transferer")
        
        # 2. Lire toutes les données depuis DuckDB
        query = f"SELECT * FROM {DUCKDB_SCHEMA}.{table_name};"
        df = duck_conn.execute(query).fetchdf()
        
        if df.empty:
            print(f"  [ATTENTION] DataFrame vide")
            return True
        
        # 3. Nettoyer les données
        df_clean = df.copy()
        for col in df_clean.columns:
            if df_clean[col].dtype in ['float64', 'float32']:
                non_null = df_clean[col].dropna()
                if len(non_null) > 0:
                    try:
                        is_all_int = all(x == int(x) for x in non_null)
                        if is_all_int:
                            df_clean[col] = df_clean[col].astype('Int64')
                    except:
                        pass
            df_clean[col] = df_clean[col].where(pd.notna(df_clean[col]), None)
        
        # 4. Créer buffer CSV
        buffer = io.StringIO()
        df_clean.to_csv(buffer, index=False, header=False, sep='\t', na_rep='\\N')
        buffer.seek(0)
        
        # 5. COPY vers PostgreSQL
        cursor = pg_conn.cursor()
        
        try:
            colonnes = ', '.join([f'"{col}"' for col in df.columns])
            copy_sql = f"COPY {POSTGRES_SCHEMA}.{table_name} ({colonnes}) FROM STDIN WITH (FORMAT CSV, DELIMITER E'\\t', NULL '\\N')"
            
            cursor.copy_expert(copy_sql, buffer)
            pg_conn.commit()
            
            elapsed_time = time.time() - start_time
            speed = len(df) / elapsed_time if elapsed_time > 0 else 0
            
            print(f"  [OK] {table_name} pousse avec succes")
            print(f"  [STATS] {len(df):,} lignes en {elapsed_time:.1f}s ({speed:,.0f} lignes/s)")
            
            return True
            
        except psycopg2.IntegrityError as e:
            if "duplicate key" in str(e):
                print(f"  [ERREUR] Conflits de cles detectes: {e}")
                print(f"  [SOLUTION] La table PostgreSQL doit etre recreee proprement")
                pg_conn.rollback()
                return False
            else:
                raise
        
        finally:
            cursor.close()
        
    except Exception as e:
        print(f"  [ERREUR] Push echoue: {e}")
        pg_conn.rollback()
        return False

def main():
    """Fonction principale"""
    
    print("=" * 70)
    print("PUSH DATA MART SIMPLE : DuckDB -> PostgreSQL")
    print("=" * 70)
    print()
    
    # Vérifier que DuckDB existe
    if not Path(DUCKDB_PATH).exists():
        print(f"[ERREUR] Fichier DuckDB introuvable: {DUCKDB_PATH}")
        exit(1)
    
    # Connexions
    duck_conn = connect_duckdb()
    pg_conn = connect_postgres()
    
    if not duck_conn or not pg_conn:
        exit(1)
    
    total_start_time = time.time()
    success_count = 0
    
    try:
        for idx, table in enumerate(TABLES_TO_PROCESS, 1):
            print(f"[{idx}/{len(TABLES_TO_PROCESS)}] {table}")
            
            # Essayer de pousser la table
            if push_table_simple(duck_conn, pg_conn, table):
                success_count += 1
            else:
                print(f"  [SOLUTION] Pour {table}:")
                print(f"    1. psql -h localhost -U admin -d healthcare_dwh")
                print(f"    2. DROP TABLE IF EXISTS {POSTGRES_SCHEMA}.{table} CASCADE;")
                print(f"    3. \\i scripts/init/init_datamart.sql")
                print(f"    4. Relancer ce script")
                break  # Arrêter si erreur
        
        total_elapsed = time.time() - total_start_time
        
        print()
        print("=" * 70)
        print(f"[RESULTAT] {success_count}/{len(TABLES_TO_PROCESS)} tables poussees avec succes")
        print(f"[STATS] Temps total: {total_elapsed:.1f}s")
        print("=" * 70)
        
    except KeyboardInterrupt:
        print("\n[ATTENTION] Push interrompu par l'utilisateur")
    except Exception as e:
        print(f"\n[ERREUR] Push interrompu: {e}")
    
    finally:
        # Fermer les connexions
        duck_conn.close()
        pg_conn.close()
        print("[INFO] Connexions fermees")

if __name__ == '__main__':
    main()
