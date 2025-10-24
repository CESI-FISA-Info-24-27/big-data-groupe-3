#!/usr/bin/env python3
"""
Script OPTIMISÉ pour pousser les tables DWH de DuckDB vers PostgreSQL
AMÉLIORATIONS :
- Traitement par batch pour éviter les erreurs de mémoire (OOM)
- Support des très grandes tables (25M+ lignes)
- Monitoring de la progression
- Gestion intelligente de la mémoire

Usage: python push_dwh_to_postgres.py
Configuration: Lecture depuis fichier .env
"""

import duckdb
import psycopg2
from psycopg2.extras import execute_batch
import os
import sys
from pathlib import Path
import time

# Essayer de charger dotenv, mais optionnel
try:
    from dotenv import load_dotenv
    load_dotenv()
    print("[INFO] Fichier .env charge")
except:
    print("[INFO] python-dotenv non installe ou .env absent, utilisation valeurs par defaut")

# Configuration PostgreSQL depuis .env (préfixe DWH_POSTGRES_)
POSTGRES_CONFIG = {
    'host': os.getenv('DWH_POSTGRES_HOST', os.getenv('POSTGRES_HOST', 'localhost')),
    'port': int(os.getenv('DWH_POSTGRES_PORT', os.getenv('POSTGRES_PORT', '5432'))),
    'database': os.getenv('DWH_POSTGRES_DB', os.getenv('POSTGRES_DB', 'healthcare_dwh')),
    'user': os.getenv('DWH_POSTGRES_USER', os.getenv('POSTGRES_USER', 'admin')),
    'password': os.getenv('DWH_POSTGRES_PASSWORD', os.getenv('POSTGRES_PASSWORD', 'admin'))
}

# Configuration DuckDB
DUCKDB_PATH = 'data/duckdb/staging.duckdb'

# NOUVELLE CONFIGURATION : Tailles de batch selon le type de table
BATCH_CONFIG = {
    'fait_deces': 50000,        # Table très volumineuse (25M+ lignes)
    'fait_consultation': 100000, # Table volumineuse
    'fait_hospitalisation': 100000,
    'fait_satisfaction': 100000,
    'fait_qualite_soins': 100000,
    'default': 200000            # Taille par défaut pour les dimensions
}

# Schema PostgreSQL cible (dynamique selon la table)
def get_target_schema(table_name):
    """Détermine le schéma cible selon le nom de la table"""
    if table_name.startswith('dm_'):
        return 'datamart'
    else:
        return 'dwh'

POSTGRES_SCHEMA = 'dwh'  # Valeur par défaut

# Afficher la config (sans le mot de passe)
print(f"[CONFIG] PostgreSQL:")
print(f"  Host: {POSTGRES_CONFIG['host']}")
print(f"  Port: {POSTGRES_CONFIG['port']}")
print(f"  Database: {POSTGRES_CONFIG['database']}")
print(f"  User: {POSTGRES_CONFIG['user']}")
print(f"  Schema: {POSTGRES_SCHEMA}")
print()

# Tables à exporter (dans l'ordre des dépendances FK)
TABLES_ORDRE = [
    # Dimensions d'abord (pas de FK entre elles, sauf dim_professionnel → dim_specialite)
    'dim_temps',
    'dim_specialite',
    'dim_mutuelle',
    'dim_diagnostic',
    'dim_localisation',
    'dim_etablissement',
    'dim_patient',
    'dim_professionnel',
    # Faits ensuite (avec FK vers dimensions)
    'fait_consultation',
    'fait_hospitalisation',
    'fait_deces',
    'fait_satisfaction',
    'fait_qualite_soins',
    # Data Marts pour Power BI
    'dm_consultations_analysis',
    'dm_hospitalisations_analysis',
    'dm_deces_analysis',
    'dm_satisfaction_analysis'
]


def connect_duckdb():
    """Connexion à DuckDB"""
    try:
        conn = duckdb.connect(DUCKDB_PATH, read_only=True)
        print(f"[OK] Connecte a DuckDB: {DUCKDB_PATH}")
        return conn
    except Exception as e:
        print(f"[ERREUR] Connexion DuckDB: {e}")
        exit(1)


def connect_postgres():
    """Connexion à PostgreSQL"""
    try:
        conn = psycopg2.connect(**POSTGRES_CONFIG)
        print(f"[OK] Connecte a PostgreSQL: {POSTGRES_CONFIG['host']}:{POSTGRES_CONFIG['port']}/{POSTGRES_CONFIG['database']}")
        print(f"[INFO] Schema cible: {POSTGRES_SCHEMA}")
        return conn
    except Exception as e:
        print(f"[ERREUR] Connexion PostgreSQL: {e}")
        print(f"[INFO] Verifiez votre fichier .env et que PostgreSQL est demarre")
        exit(1)


def get_table_count(duck_conn, table_name):
    """Obtenir le nombre de lignes dans une table DuckDB"""
    source_schema = 'datamart' if table_name.startswith('dm_') else 'dwh'
    query = f"SELECT COUNT(*) as cnt FROM {source_schema}.{table_name};"
    result = duck_conn.execute(query).fetchone()
    return result[0] if result else 0


def push_table_batch(duck_conn, pg_conn, table_name):
    """
    Pousse une table de DuckDB vers PostgreSQL en utilisant COPY avec traitement par BATCH
    
    OPTIMISATIONS :
    - Traitement par lots pour éviter le OOM (Out Of Memory)
    - Taille de batch adaptative selon la table
    - Monitoring de la progression en temps réel
    - Gestion mémoire optimisée
    
    Stratégie :
    1. Compter le nombre total de lignes
    2. TRUNCATE la table PostgreSQL
    3. Traiter par batch avec COPY (ultra-rapide)
    4. Afficher la progression
    """
    
    print(f"\n[{table_name}] Push en cours...")
    start_time = time.time()
    
    try:
        # Déterminer le schéma source et cible
        source_schema = 'datamart' if table_name.startswith('dm_') else 'dwh'
        target_schema = get_target_schema(table_name)
        
        # 1. Compter le total de lignes
        total_rows = get_table_count(duck_conn, table_name)
        
        if total_rows == 0:
            print(f"  [ATTENTION] Table vide dans DuckDB : {table_name}")
            return
        
        print(f"  [INFO] {total_rows:,} lignes totales a traiter")
        
        # Déterminer la taille de batch
        batch_size = BATCH_CONFIG.get(table_name, BATCH_CONFIG['default'])
        print(f"  [INFO] Taille de batch : {batch_size:,} lignes")
        
        # 2. Sauvegarder la ligne "Inconnu" (sk=-1) pour les dimensions
        cursor = pg_conn.cursor()
        unknown_row = None
        sk_col = None
        
        if table_name.startswith('dim_'):
            # Obtenir les colonnes de la table
            test_query = f"SELECT * FROM {source_schema}.{table_name} LIMIT 1;"
            test_df = duck_conn.execute(test_query).fetchdf()
            sk_col = [col for col in test_df.columns if col.startswith('sk_')][0] if any(col.startswith('sk_') for col in test_df.columns) else None
            
            if sk_col:
                try:
                    # Sauvegarder la ligne -1 si elle existe
                    cursor.execute(f"SELECT * FROM {target_schema}.{table_name} WHERE {sk_col} = -1;")
                    unknown_row = cursor.fetchone()
                    if unknown_row:
                        print(f"  [INFO] Ligne 'Inconnu' (sk=-1) sauvegardee")
                except:
                    pass
        
        # 3. TRUNCATE la table PostgreSQL (vider sans DROP)
        truncate_sql = f"TRUNCATE TABLE {target_schema}.{table_name} CASCADE;"
        cursor.execute(truncate_sql)
        pg_conn.commit()
        print(f"  [INFO] Table PostgreSQL videe (TRUNCATE)")
        
        # 4. Traiter par BATCH avec COPY
        import io
        import pandas as pd
        import numpy as np
        
        offset = 0
        total_inserted = 0
        batch_num = 1
        
        while offset < total_rows:
            batch_start = time.time()
            
            # Lire un batch depuis DuckDB
            query = f"""
                SELECT * FROM {source_schema}.{table_name}
                ORDER BY 1  -- Ordre stable pour pagination
                LIMIT {batch_size} OFFSET {offset};
            """
            df = duck_conn.execute(query).fetchdf()
            
            if df.empty:
                break
            
            nb_lignes_batch = len(df)
            
            # Nettoyer les données (même logique que l'original)
            df_clean = df.copy()
            for col in df_clean.columns:
                # Convertir les float qui sont en fait des int
                if df_clean[col].dtype in ['float64', 'float32']:
                    non_null = df_clean[col].dropna()
                    if len(non_null) > 0:
                        try:
                            is_all_int = all(x == int(x) for x in non_null)
                            if is_all_int:
                                df_clean[col] = df_clean[col].astype('Int64')
                        except (ValueError, OverflowError, TypeError):
                            pass
                
                # Remplacer les NaN/NA/NaT/pd.NA par None
                df_clean[col] = df_clean[col].where(pd.notna(df_clean[col]), None)
            
            # Créer un buffer CSV en mémoire
            buffer = io.StringIO()
            df_clean.to_csv(buffer, index=False, header=False, sep='\t', na_rep='\\N')
            buffer.seek(0)
            
            # Préparer les colonnes
            colonnes = ', '.join([f'"{col}"' for col in df.columns])
            
            # COPY depuis le buffer
            copy_sql = f"COPY {target_schema}.{table_name} ({colonnes}) FROM STDIN WITH (FORMAT CSV, DELIMITER E'\\t', NULL '\\N')"
            
            cursor.copy_expert(copy_sql, buffer)
            pg_conn.commit()
            
            # Libérer la mémoire
            del df
            del df_clean
            del buffer
            
            # Mise à jour des compteurs
            total_inserted += nb_lignes_batch
            offset += batch_size
            batch_num += 1
            
            # Afficher la progression
            progress_pct = (total_inserted / total_rows) * 100
            batch_time = time.time() - batch_start
            elapsed_time = time.time() - start_time
            
            print(f"    Batch {batch_num-1}: {nb_lignes_batch:,} lignes en {batch_time:.1f}s | "
                  f"Total: {total_inserted:,}/{total_rows:,} ({progress_pct:.1f}%) | "
                  f"Temps écoulé: {elapsed_time:.1f}s")
        
        # 5. Restaurer la ligne "Inconnu" (sk=-1) pour les dimensions
        if unknown_row and table_name.startswith('dim_') and sk_col:
            try:
                # Obtenir les noms de colonnes
                cursor.execute(f"SELECT * FROM {target_schema}.{table_name} LIMIT 0;")
                column_names = [desc[0] for desc in cursor.description]
                
                # Construire la requête INSERT avec ON CONFLICT
                placeholders = ', '.join(['%s'] * len(column_names))
                columns_str = ', '.join([f'"{col}"' for col in column_names])
                
                insert_sql = f"""
                    INSERT INTO {target_schema}.{table_name} ({columns_str})
                    VALUES ({placeholders})
                    ON CONFLICT ({sk_col}) DO NOTHING;
                """
                cursor.execute(insert_sql, unknown_row)
                pg_conn.commit()
                print(f"  [INFO] Ligne 'Inconnu' (sk=-1) restauree")
            except Exception as e:
                print(f"  [ATTENTION] Echec restauration ligne Inconnu: {e}")
        
        cursor.close()
        
        total_time = time.time() - start_time
        print(f"  [OK] {table_name} pousse avec succes!")
        print(f"       Total: {total_inserted:,} lignes en {total_time:.1f}s ({total_inserted/total_time:.0f} lignes/s)")
        
    except Exception as e:
        print(f"  [ERREUR] {table_name}: {e}")
        pg_conn.rollback()
        raise


def main():
    """Fonction principale"""
    
    print("=" * 70)
    print("PUSH DWH OPTIMISÉ : DuckDB -> PostgreSQL (Traitement par BATCH)")
    print("=" * 70)
    print()
    
    # Vérifier que DuckDB existe
    if not Path(DUCKDB_PATH).exists():
        print(f"[ERREUR] Fichier DuckDB introuvable: {DUCKDB_PATH}")
        print(f"[INFO] Executez d'abord: cd dbt && dbt run --select marts.dwh")
        exit(1)
    
    # Connexions
    duck_conn = connect_duckdb()
    pg_conn = connect_postgres()
    
    print(f"\n[INFO] Push de {len(TABLES_ORDRE)} tables en cours...")
    print(f"[INFO] Ordre: Dimensions puis Faits (pour respecter FK)")
    print(f"[INFO] Mode: Traitement par BATCH (évite les erreurs de mémoire)")
    print()
    
    start_total = time.time()
    
    try:
        for idx, table in enumerate(TABLES_ORDRE, 1):
            print(f"\n{'='*70}")
            print(f"[{idx}/{len(TABLES_ORDRE)}] {table}")
            print(f"{'='*70}")
            push_table_batch(duck_conn, pg_conn, table)
        
        total_duration = time.time() - start_total
        
        print()
        print("=" * 70)
        print(f"[SUCCES] {len(TABLES_ORDRE)} tables poussees avec succes !")
        print(f"[INFO] Temps total: {total_duration:.1f}s ({total_duration/60:.1f} minutes)")
        print("=" * 70)
        print()
        print("Verification dans PostgreSQL :")
        print(f"  psql -h {POSTGRES_CONFIG['host']} -U {POSTGRES_CONFIG['user']} -d {POSTGRES_CONFIG['database']}")
        print(f"  \\dt {POSTGRES_SCHEMA}.*")
        print()
        
    except Exception as e:
        print()
        print("=" * 70)
        print(f"[ERREUR] Push interrompu: {e}")
        print("=" * 70)
        exit(1)
    
    finally:
        # Fermer les connexions
        duck_conn.close()
        pg_conn.close()
        print("[INFO] Connexions fermees")


if __name__ == '__main__':
    main()
