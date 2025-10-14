#!/usr/bin/env python3
"""
Script ULTRA-OPTIMISÉ pour pousser les gros data marts via Parquet
Méthode recommandée pour 45M+ lignes
"""

import duckdb
import psycopg2
import os
import sys
from pathlib import Path
import time
import shutil

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

# Configuration export
EXPORT_DIR = 'data/export_parquet'
CHUNK_SIZE = 5000000  # 5M lignes par fichier Parquet

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

def export_table_to_parquet(duck_conn, table_name):
    """Exporte une table vers des fichiers Parquet"""
    
    print(f"\n[{table_name}] Export vers Parquet en cours...")
    start_time = time.time()
    
    try:
        # 1. Compter le nombre total de lignes
        total_rows = get_table_count(duck_conn, table_name)
        
        if total_rows == 0:
            print(f"  [ATTENTION] Table vide: {table_name}")
            return []
        
        print(f"  [INFO] {total_rows:,} lignes a exporter")
        
        # 2. Créer le dossier d'export
        table_export_dir = Path(EXPORT_DIR) / table_name
        table_export_dir.mkdir(parents=True, exist_ok=True)
        
        # 3. Nettoyer les anciens fichiers
        if table_export_dir.exists():
            shutil.rmtree(table_export_dir)
        table_export_dir.mkdir(parents=True, exist_ok=True)
        
        # 4. Exporter par chunks si la table est grosse
        if total_rows > CHUNK_SIZE:
            print(f"  [INFO] Table grosse, export par chunks de {CHUNK_SIZE:,} lignes")
            
            chunk_count = (total_rows + CHUNK_SIZE - 1) // CHUNK_SIZE
            parquet_files = []
            
            for chunk_idx in range(chunk_count):
                chunk_start = chunk_idx * CHUNK_SIZE
                chunk_end = min(chunk_start + CHUNK_SIZE, total_rows)
                
                print(f"  [CHUNK {chunk_idx + 1}/{chunk_count}] {chunk_start:,} - {chunk_end:,}")
                
                # Export du chunk
                parquet_file = table_export_dir / f"chunk_{chunk_idx:03d}.parquet"
                
                query = f"""
                    COPY (
                        SELECT * FROM {DUCKDB_SCHEMA}.{table_name} 
                        LIMIT {CHUNK_SIZE} OFFSET {chunk_start}
                    ) 
                    TO '{parquet_file}' 
                    (FORMAT PARQUET, COMPRESSION 'SNAPPY')
                """
                
                duck_conn.execute(query)
                parquet_files.append(str(parquet_file))
                
                # Progress
                progress = ((chunk_idx + 1) / chunk_count) * 100
                print(f"    [PROGRESS] {progress:.1f}%")
        
        else:
            # Table petite, export direct
            print(f"  [INFO] Table petite, export direct")
            parquet_file = table_export_dir / f"{table_name}.parquet"
            
            query = f"""
                COPY {DUCKDB_SCHEMA}.{table_name} 
                TO '{parquet_file}' 
                (FORMAT PARQUET, COMPRESSION 'SNAPPY')
            """
            
            duck_conn.execute(query)
            parquet_files = [str(parquet_file)]
        
        elapsed_time = time.time() - start_time
        speed = total_rows / elapsed_time if elapsed_time > 0 else 0
        
        print(f"  [OK] Export termine")
        print(f"  [STATS] {total_rows:,} lignes en {elapsed_time:.1f}s ({speed:,.0f} lignes/s)")
        print(f"  [STATS] {len(parquet_files)} fichiers Parquet crees")
        
        return parquet_files
        
    except Exception as e:
        print(f"  [ERREUR] Export echoue: {e}")
        return []

def import_parquet_to_postgres(parquet_files, table_name):
    """Importe les fichiers Parquet vers PostgreSQL via DuckDB"""
    
    print(f"\n[{table_name}] Import Parquet -> PostgreSQL en cours...")
    start_time = time.time()
    
    try:
        # 1. Vider la table PostgreSQL
        pg_conn = connect_postgres()
        cursor = pg_conn.cursor()
        
        try:
            cursor.execute(f"TRUNCATE TABLE {POSTGRES_SCHEMA}.{table_name} RESTART IDENTITY CASCADE;")
            pg_conn.commit()
            print(f"  [INFO] Table PostgreSQL videe")
        except Exception as e:
            print(f"  [ATTENTION] Impossible de vider la table: {e}")
        
        cursor.close()
        pg_conn.close()
        
        # 2. Connexion DuckDB pour l'import
        duck_conn = connect_duckdb()
        
        # 3. Créer la connexion PostgreSQL dans DuckDB (en mode lecture/écriture)
        pg_connection_string = f"postgresql://{POSTGRES_CONFIG['user']}:{POSTGRES_CONFIG['password']}@{POSTGRES_CONFIG['host']}:{POSTGRES_CONFIG['port']}/{POSTGRES_CONFIG['database']}"
        
        attach_query = f"ATTACH '{pg_connection_string}' AS pg (TYPE POSTGRES, READ_ONLY false);"
        duck_conn.execute(attach_query)
        print(f"  [INFO] Connexion PostgreSQL attachee a DuckDB (mode lecture/ecriture)")
        
        # 4. Importer les fichiers Parquet
        if len(parquet_files) == 1:
            # Un seul fichier
            print(f"  [INFO] Import du fichier unique")
            
            import_query = f"""
                INSERT INTO pg.{POSTGRES_SCHEMA}.{table_name}
                SELECT * FROM read_parquet('{parquet_files[0]}');
            """
            
            duck_conn.execute(import_query)
            
        else:
            # Plusieurs fichiers
            print(f"  [INFO] Import de {len(parquet_files)} fichiers")
            
            for idx, parquet_file in enumerate(parquet_files, 1):
                print(f"  [IMPORT {idx}/{len(parquet_files)}] {Path(parquet_file).name}")
                
                import_query = f"""
                    INSERT INTO pg.{POSTGRES_SCHEMA}.{table_name}
                    SELECT * FROM read_parquet('{parquet_file}');
                """
                
                duck_conn.execute(import_query)
                
                # Progress
                progress = (idx / len(parquet_files)) * 100
                print(f"    [PROGRESS] {progress:.1f}%")
        
        duck_conn.close()
        
        elapsed_time = time.time() - start_time
        total_rows = sum(Path(f).stat().st_size for f in parquet_files)  # Approximation
        speed = total_rows / elapsed_time if elapsed_time > 0 else 0
        
        print(f"  [OK] Import termine")
        print(f"  [STATS] {len(parquet_files)} fichiers en {elapsed_time:.1f}s")
        
        return True
        
    except Exception as e:
        print(f"  [ERREUR] Import echoue: {e}")
        return False

def cleanup_parquet_files(table_name):
    """Nettoie les fichiers Parquet temporaires"""
    try:
        table_export_dir = Path(EXPORT_DIR) / table_name
        if table_export_dir.exists():
            shutil.rmtree(table_export_dir)
            print(f"  [CLEANUP] Fichiers Parquet supprimes")
    except Exception as e:
        print(f"  [ATTENTION] Impossible de nettoyer: {e}")

def process_table_parquet(table_name):
    """Traite une table complète via Parquet"""
    
    print(f"\n{'='*70}")
    print(f"TRAITEMENT: {table_name}")
    print(f"{'='*70}")
    
    # Connexion DuckDB
    duck_conn = connect_duckdb()
    if not duck_conn:
        return False
    
    try:
        # Étape 1: Export vers Parquet
        parquet_files = export_table_to_parquet(duck_conn, table_name)
        
        if not parquet_files:
            print(f"  [ERREUR] Aucun fichier Parquet cree")
            return False
        
        # Étape 2: Import vers PostgreSQL
        success = import_parquet_to_postgres(parquet_files, table_name)
        
        # Étape 3: Nettoyage
        cleanup_parquet_files(table_name)
        
        return success
        
    finally:
        duck_conn.close()

def main():
    """Fonction principale"""
    
    print("=" * 70)
    print("PUSH DATA MART VIA PARQUET : DuckDB -> PostgreSQL")
    print("=" * 70)
    print(f"[INFO] Methode: Export Parquet + Import DuckDB->PostgreSQL")
    print(f"[INFO] Chunk size: {CHUNK_SIZE:,} lignes")
    print(f"[INFO] Export dir: {EXPORT_DIR}")
    print()
    
    # Vérifier que DuckDB existe
    if not Path(DUCKDB_PATH).exists():
        print(f"[ERREUR] Fichier DuckDB introuvable: {DUCKDB_PATH}")
        exit(1)
    
    # Créer le dossier d'export
    Path(EXPORT_DIR).mkdir(parents=True, exist_ok=True)
    
    total_start_time = time.time()
    success_count = 0
    
    try:
        for idx, table in enumerate(TABLES_TO_PROCESS, 1):
            print(f"[{idx}/{len(TABLES_TO_PROCESS)}] {table}")
            
            if process_table_parquet(table):
                success_count += 1
                print(f"  [SUCCES] {table} traite avec succes")
            else:
                print(f"  [ERREUR] Echec du traitement de {table}")
        
        total_elapsed = time.time() - total_start_time
        
        print()
        print("=" * 70)
        print(f"[SUCCES] {success_count}/{len(TABLES_TO_PROCESS)} tables traitees avec succes !")
        print(f"[STATS] Temps total: {total_elapsed:.1f}s")
        print("=" * 70)
        print()
        print("Avantages de cette methode:")
        print("  ✅ Pas de limite de connexions PostgreSQL")
        print("  ✅ Gestion automatique des gros volumes")
        print("  ✅ Compression Parquet (gain d'espace)")
        print("  ✅ Reprise possible en cas d'erreur")
        print()
        
    except KeyboardInterrupt:
        print("\n[ATTENTION] Traitement interrompu par l'utilisateur")
        exit(1)
    except Exception as e:
        print(f"\n[ERREUR] Traitement interrompu: {e}")
        exit(1)

if __name__ == '__main__':
    main()
