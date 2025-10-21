#!/usr/bin/env python3
"""
Script pour pousser les tables DWH de DuckDB vers PostgreSQL
Les tables doivent déjà exister dans PostgreSQL
Le script fait : TRUNCATE puis INSERT

Usage: python push_dwh_to_postgres.py
Configuration: Lecture depuis fichier .env
"""

import duckdb
import psycopg2
from psycopg2.extras import execute_batch
import os
import sys
from pathlib import Path

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
    'dm_consultations_agregees',
    'dm_hospitalisations_agregees',
    'dm_analyse_territoriale'
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


def push_table(duck_conn, pg_conn, table_name):
    """
    Pousse une table de DuckDB vers PostgreSQL en utilisant COPY (ultra-rapide)
    
    Stratégie :
    1. Sauvegarder la ligne "Inconnu" (sk=-1) si elle existe
    2. TRUNCATE la table PostgreSQL (vider sans DROP)
    3. COPY les données depuis un buffer CSV en mémoire (10-100x plus rapide que INSERT)
    4. Restaurer la ligne "Inconnu" si nécessaire
    """
    
    print(f"\n[{table_name}] Push en cours...")
    
    try:
        # Déterminer le schéma source et cible
        source_schema = 'datamart' if table_name.startswith('dm_') else 'dwh'
        target_schema = get_target_schema(table_name)
        
        # 1. Lire depuis DuckDB
        query = f"SELECT * FROM {source_schema}.{table_name};"
        df = duck_conn.execute(query).fetchdf()
        
        if df.empty:
            print(f"  [ATTENTION] Table vide dans DuckDB : {table_name}")
            return
        
        nb_lignes = len(df)
        print(f"  [INFO] {nb_lignes:,} lignes lues depuis DuckDB")
        
        # 2. Sauvegarder la ligne "Inconnu" (sk=-1) pour les dimensions
        cursor = pg_conn.cursor()
        unknown_row = None
        
        if table_name.startswith('dim_'):
            # Identifier la colonne clé (première colonne qui commence par "sk_")
            sk_col = [col for col in df.columns if col.startswith('sk_')][0] if any(col.startswith('sk_') for col in df.columns) else None
            
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
        # Désactiver temporairement les contraintes FK pour TRUNCATE
        truncate_sql = f"TRUNCATE TABLE {target_schema}.{table_name} CASCADE;"
        cursor.execute(truncate_sql)
        pg_conn.commit()
        print(f"  [INFO] Table PostgreSQL videe (TRUNCATE)")
        
        # 3. Utiliser COPY pour un import ultra-rapide
        import io
        import pandas as pd
        import numpy as np
        
        # Remplacer les NaN/NA par None et convertir les types correctement
        df_clean = df.copy()
        for col in df_clean.columns:
            # Convertir les float qui sont en fait des int (ex: 4.0 → 4)
            # Cela arrive souvent avec les colonnes contenant des NULL (pandas convertit int→float pour gérer NULL)
            if df_clean[col].dtype in ['float64', 'float32']:
                # Vérifier si toutes les valeurs non-NULL n'ont pas de partie décimale
                non_null = df_clean[col].dropna()
                if len(non_null) > 0:
                    try:
                        # Vérifier si toutes les valeurs sont des entiers (pas de décimales)
                        is_all_int = all(x == int(x) for x in non_null)
                        if is_all_int:
                            # Convertir en Int64 (type nullable pandas qui supporte NULL)
                            df_clean[col] = df_clean[col].astype('Int64')
                    except (ValueError, OverflowError, TypeError):
                        pass
            
            # Remplacer les NaN/NA/NaT/pd.NA par None pour CSV
            # Utiliser mask pour remplacer proprement
            df_clean[col] = df_clean[col].where(pd.notna(df_clean[col]), None)
        
        # Créer un buffer CSV en mémoire
        buffer = io.StringIO()
        df_clean.to_csv(buffer, index=False, header=False, sep='\t', na_rep='\\N')
        buffer.seek(0)
        
        # Préparer les colonnes
        colonnes = ', '.join([f'"{col}"' for col in df.columns])
        
        # COPY depuis le buffer (ultra-rapide!)
        copy_sql = f"COPY {POSTGRES_SCHEMA}.{table_name} ({colonnes}) FROM STDIN WITH (FORMAT CSV, DELIMITER E'\\t', NULL '\\N')"
        
        cursor.copy_expert(copy_sql, buffer)
        pg_conn.commit()
        
        # 4. Restaurer la ligne "Inconnu" (sk=-1) pour les dimensions
        if unknown_row and table_name.startswith('dim_'):
            try:
                # Obtenir les noms de colonnes
                cursor.execute(f"SELECT * FROM {POSTGRES_SCHEMA}.{table_name} LIMIT 0;")
                column_names = [desc[0] for desc in cursor.description]
                
                # Construire la requête INSERT avec ON CONFLICT
                placeholders = ', '.join(['%s'] * len(column_names))
                columns_str = ', '.join([f'"{col}"' for col in column_names])
                sk_col = [col for col in column_names if col.startswith('sk_')][0]
                
                insert_sql = f"""
                    INSERT INTO {POSTGRES_SCHEMA}.{table_name} ({columns_str})
                    VALUES ({placeholders})
                    ON CONFLICT ({sk_col}) DO NOTHING;
                """
                cursor.execute(insert_sql, unknown_row)
                pg_conn.commit()
                print(f"  [INFO] Ligne 'Inconnu' (sk=-1) restauree")
            except Exception as e:
                print(f"  [ATTENTION] Echec restauration ligne Inconnu: {e}")
                # Ne pas faire échouer tout le push pour ça
        
        cursor.close()
        print(f"  [OK] {table_name} pousse avec succes ({nb_lignes:,} lignes)")
        
    except Exception as e:
        print(f"  [ERREUR] {table_name}: {e}")
        pg_conn.rollback()
        raise


def main():
    """Fonction principale"""
    
    print("=" * 70)
    print("PUSH DWH : DuckDB -> PostgreSQL")
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
    print()
    
    try:
        for idx, table in enumerate(TABLES_ORDRE, 1):
            print(f"[{idx}/{len(TABLES_ORDRE)}] {table}")
            push_table(duck_conn, pg_conn, table)
        
        print()
        print("=" * 70)
        print(f"[SUCCES] {len(TABLES_ORDRE)} tables poussees avec succes !")
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

