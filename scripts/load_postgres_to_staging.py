"""
Script pour charger toutes les tables PostgreSQL dans la base de données DuckDB staging
Charge toutes les tables du schéma public dans le schéma raw de DuckDB
"""

import duckdb
import psycopg2
from pathlib import Path
from datetime import datetime
import sys
import io
import os
from dotenv import load_dotenv

# Configurer l'encodage UTF-8 pour Windows
if sys.platform == 'win32':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

# Charger les variables d'environnement
load_dotenv()


def get_postgres_connection():
    """
    Crée une connexion PostgreSQL à partir des variables d'environnement
    """
    return psycopg2.connect(
        host=os.getenv('SOURCE_POSTGRES_HOST', 'localhost'),
        port=os.getenv('SOURCE_POSTGRES_PORT', '5432'),
        database=os.getenv('SOURCE_POSTGRES_DB'),
        user=os.getenv('SOURCE_POSTGRES_USER'),
        password=os.getenv('SOURCE_POSTGRES_PASSWORD')
    )


def get_postgres_tables(pg_conn):
    """
    Récupère la liste de toutes les tables du schéma public
    """
    cursor = pg_conn.cursor()
    cursor.execute("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_type = 'BASE TABLE'
        ORDER BY table_name
    """)
    tables = [row[0] for row in cursor.fetchall()]
    cursor.close()
    return tables


def load_postgres_table_to_duckdb(table_name: str, pg_conn, duckdb_conn):
    """
    Charge une table PostgreSQL dans DuckDB
    """
    # Commencer une nouvelle transaction pour cette table
    pg_conn.rollback()
    
    try:
        print(f"  Chargement de {table_name} depuis PostgreSQL...")
        
        # Normaliser le nom de table pour DuckDB (minuscules, sans guillemets)
        duckdb_table_name = table_name.lower()
        
        # Supprimer la table DuckDB si elle existe
        duckdb_conn.execute(f"DROP TABLE IF EXISTS raw.{duckdb_table_name}")
        
        # Récupérer toutes les données de PostgreSQL avec guillemets pour gérer la casse
        pg_cursor = pg_conn.cursor()
        pg_cursor.execute(f'SELECT * FROM public."{table_name}"')
        
        # Récupérer les noms de colonnes
        column_names = [desc[0] for desc in pg_cursor.description]
        
        # Récupérer toutes les lignes
        rows = pg_cursor.fetchall()
        pg_cursor.close()
        
        if not rows:
            print(f"    [ATTENTION] Table {table_name} est vide")
            # Créer une table vide avec la même structure
            pg_cursor = pg_conn.cursor()
            pg_cursor.execute(f"""
                SELECT column_name, data_type 
                FROM information_schema.columns 
                WHERE table_schema = 'public' 
                AND table_name = %s
                ORDER BY ordinal_position
            """, (table_name,))
            columns_info = pg_cursor.fetchall()
            pg_cursor.close()
            
            # Mapper les types PostgreSQL vers DuckDB
            type_mapping = {
                'integer': 'INTEGER',
                'bigint': 'BIGINT',
                'smallint': 'SMALLINT',
                'numeric': 'DECIMAL',
                'real': 'REAL',
                'double precision': 'DOUBLE',
                'character varying': 'VARCHAR',
                'character': 'VARCHAR',
                'text': 'VARCHAR',
                'timestamp without time zone': 'TIMESTAMP',
                'timestamp with time zone': 'TIMESTAMPTZ',
                'date': 'DATE',
                'boolean': 'BOOLEAN',
                'json': 'JSON',
                'jsonb': 'JSON',
                'uuid': 'UUID'
            }
            
            columns_def = []
            for col_name, col_type in columns_info:
                duckdb_type = type_mapping.get(col_type, 'VARCHAR')
                columns_def.append(f"{col_name} {duckdb_type}")
            
            create_table_sql = f"CREATE TABLE raw.{duckdb_table_name} ({', '.join(columns_def)})"
            duckdb_conn.execute(create_table_sql)
            
            return True, 0
        
        # Créer la table dans DuckDB avec les données
        # Utiliser un DataFrame pandas pour faciliter le transfert
        import pandas as pd
        df = pd.DataFrame(rows, columns=column_names)
        
        duckdb_conn.execute(f"CREATE TABLE raw.{duckdb_table_name} AS SELECT * FROM df")
        
        row_count = len(rows)
        print(f"    [OK] {row_count} lignes chargées")
        
        return True, row_count
        
    except Exception as e:
        print(f"    [ERREUR] {str(e)}")
        pg_conn.rollback()  # Nettoyer la transaction en erreur
        return False, 0


def main():
    """
    Fonction principale
    """
    print("=" * 80)
    print("CHARGEMENT DES TABLES POSTGRESQL DANS LA BASE STAGING")
    print("=" * 80)
    
    # Chemins
    project_root = Path(__file__).parent.parent
    staging_db_path = project_root / 'data' / 'duckdb' / 'staging.duckdb'
    
    print(f"Base de données DuckDB: {staging_db_path}")
    print(f"PostgreSQL: {os.getenv('SOURCE_POSTGRES_HOST')}:{os.getenv('SOURCE_POSTGRES_PORT')}/{os.getenv('SOURCE_POSTGRES_DB')}")
    print()
    
    # Se connecter à PostgreSQL
    try:
        print("Connexion à PostgreSQL...")
        pg_conn = get_postgres_connection()
        print("  [OK] Connecté à PostgreSQL")
    except Exception as e:
        print(f"  [ERREUR] Impossible de se connecter à PostgreSQL: {e}")
        return
    
    # Se connecter à DuckDB
    try:
        print("Connexion à DuckDB...")
        duckdb_conn = duckdb.connect(str(staging_db_path))
        print("  [OK] Connecté à DuckDB")
    except Exception as e:
        print(f"  [ERREUR] Impossible de se connecter à DuckDB: {e}")
        pg_conn.close()
        return
    
    # Créer le schéma raw s'il n'existe pas
    duckdb_conn.execute("CREATE SCHEMA IF NOT EXISTS raw")
    
    print()
    
    # Récupérer la liste des tables
    try:
        tables = get_postgres_tables(pg_conn)
        print(f"[INFO] {len(tables)} tables trouvées dans PostgreSQL\n")
        
        if not tables:
            print("[ATTENTION] Aucune table trouvée dans le schéma public")
            pg_conn.close()
            duckdb_conn.close()
            return
        
    except Exception as e:
        print(f"[ERREUR] Impossible de récupérer la liste des tables: {e}")
        pg_conn.close()
        duckdb_conn.close()
        return
    
    # Charger chaque table
    success_count = 0
    error_count = 0
    total_rows = 0
    
    for table_name in tables:
        success, row_count = load_postgres_table_to_duckdb(table_name, pg_conn, duckdb_conn)
        
        if success:
            success_count += 1
            total_rows += row_count
        else:
            error_count += 1
    
    print()
    print("=" * 80)
    print("RÉSUMÉ")
    print("=" * 80)
    print(f"[OK] Tables chargées avec succès: {success_count}")
    print(f"[ERREUR] Tables en erreur: {error_count}")
    print(f"[INFO] Total de lignes chargées: {total_rows:,}")
    print()
    
    # Afficher les tables créées
    print("Tables créées dans le schéma 'raw':")
    tables_result = duckdb_conn.execute("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'raw'
        ORDER BY table_name
    """).fetchall()
    
    for (table,) in tables_result:
        row_count = duckdb_conn.execute(f"SELECT COUNT(*) FROM raw.{table}").fetchone()[0]
        col_count = duckdb_conn.execute(f"""
            SELECT COUNT(*) 
            FROM information_schema.columns 
            WHERE table_schema='raw' AND table_name='{table}'
        """).fetchone()[0]
        print(f"  - {table}: {row_count:,} lignes, {col_count} colonnes")
    
    print()
    print("[SUCCÈS] Chargement terminé!")
    
    # Fermer les connexions
    pg_conn.close()
    duckdb_conn.close()


if __name__ == "__main__":
    main()
