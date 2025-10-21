"""
Script pour charger tous les fichiers CSV dans la base de données DuckDB staging
Parcourt récursivement le dossier data/csv et charge chaque fichier dans le schéma raw
"""

import duckdb
from pathlib import Path
from datetime import datetime
import re
import sys
import io

# Configurer l'encodage UTF-8 pour Windows
if sys.platform == 'win32':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')


def normalize_table_name(filename: str) -> str:
    """
    Normalise le nom du fichier pour créer un nom de table valide
    - Supprime l'extension .csv
    - Remplace les espaces et caractères spéciaux par des underscores
    - Convertit en minuscules
    """
    # Supprimer l'extension
    name = filename.replace('.csv', '').replace('.xlsx', '')
    
    # Remplacer les caractères spéciaux par des underscores
    name = re.sub(r'[^\w\s-]', '_', name)
    name = re.sub(r'[-\s]+', '_', name)
    
    # Convertir en minuscules et nettoyer les underscores multiples
    name = name.lower()
    name = re.sub(r'_+', '_', name)
    name = name.strip('_')
    
    return name


def get_relative_path_for_table(csv_path: Path, base_path: Path) -> str:
    """
    Crée un nom de table basé sur le chemin relatif du fichier
    Par exemple: data/csv/DECES EN FRANCE/deces.csv -> deces_en_france_deces
    """
    relative_path = csv_path.relative_to(base_path)
    
    # Obtenir les parties du chemin sans le fichier CSV racine
    parts = list(relative_path.parent.parts)
    
    # Ajouter le nom du fichier
    filename = normalize_table_name(csv_path.stem)
    
    # Si on est dans un sous-dossier, inclure le nom du dossier parent
    if parts:
        # Normaliser les noms de dossiers
        folder_parts = [normalize_table_name(part) for part in parts]
        table_name = '_'.join(folder_parts + [filename])
    else:
        table_name = filename
    
    return table_name


def load_csv_to_duckdb(csv_path: Path, table_name: str, con: duckdb.DuckDBPyConnection, load_id: int, history_id: int):
    """
    Charge un fichier CSV dans DuckDB
    """
    try:
        print(f"  Chargement de {csv_path.name} -> raw.{table_name}")
        
        # Supprimer la table si elle existe déjà
        con.execute(f"DROP TABLE IF EXISTS raw.{table_name}")
        
        # Charger le CSV avec DuckDB (auto-détection des types)
        # DuckDB gère automatiquement les CSV avec différents délimiteurs et encodages
        query = f"""
        CREATE TABLE raw.{table_name} AS 
        SELECT * FROM read_csv_auto('{str(csv_path).replace(chr(92), '/')}',
            header=true,
            ignore_errors=true,
            sample_size=-1
        )
        """
        
        con.execute(query)
        
        # Compter les lignes
        row_count = con.execute(f"SELECT COUNT(*) FROM raw.{table_name}").fetchone()[0]
        
        # Enregistrer dans l'historique de chargement
        con.execute("""
            INSERT INTO metadata.load_history (history_id, load_id, source_name, table_name, load_timestamp, row_count, status)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (history_id, load_id, str(csv_path), table_name, datetime.now(), row_count, 'SUCCESS'))
        
        print(f"    [OK] {row_count} lignes chargees")
        return True, row_count
        
    except Exception as e:  # pylint: disable=broad-except  # On capture toutes les erreurs pour continuer le traitement
        print(f"    [ERREUR] {str(e)}")
        
        # Enregistrer l'échec
        con.execute("""
            INSERT INTO metadata.load_history (history_id, load_id, source_name, table_name, load_timestamp, row_count, status)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (history_id, load_id, str(csv_path), table_name, datetime.now(), 0, f'ERROR: {str(e)}'))
        
        return False, 0


def main():
    """
    Fonction principale qui orchestre le chargement de tous les CSV
    """
    # Chemins
    project_root = Path(__file__).parent.parent
    csv_base_path = project_root / 'data' / 'csv'
    staging_db_path = project_root / 'data' / 'duckdb' / 'staging.duckdb'
    
    print("=" * 80)
    print("CHARGEMENT DES CSV DANS LA BASE STAGING")
    print("=" * 80)
    print(f"Base de donnees: {staging_db_path}")
    print(f"Dossier source: {csv_base_path}")
    print()
    
    # Vérifier que le dossier CSV existe
    if not csv_base_path.exists():
        print(f"[ERREUR] Le dossier {csv_base_path} n'existe pas")
        return
    
    # Se connecter à DuckDB
    con = duckdb.connect(str(staging_db_path))
    
    # S'assurer que les schémas existent
    con.execute("CREATE SCHEMA IF NOT EXISTS raw")
    con.execute("CREATE SCHEMA IF NOT EXISTS metadata")
    
    # Recréer la table d'historique avec la bonne structure
    con.execute("DROP TABLE IF EXISTS metadata.load_history")
    con.execute("""
        CREATE TABLE metadata.load_history (
            history_id INTEGER PRIMARY KEY,
            load_id INTEGER,
            source_name VARCHAR,
            table_name VARCHAR,
            load_timestamp TIMESTAMP,
            row_count INTEGER,
            status VARCHAR
        )
    """)
    
    # Variable pour générer les history_id
    history_counter = 1
    
    # Obtenir le prochain load_id
    result = con.execute("SELECT COALESCE(MAX(load_id), 0) + 1 FROM metadata.load_history").fetchone()
    load_id = result[0]
    
    print(f"Load ID: {load_id}")
    print()
    
    # Trouver tous les fichiers CSV
    csv_files = list(csv_base_path.rglob('*.csv'))
    
    # Filtrer les fichiers temporaires Excel
    csv_files = [f for f in csv_files if not f.name.startswith('~$')]
    
    if not csv_files:
        print("[ATTENTION] Aucun fichier CSV trouve")
        return
    
    print(f"[INFO] {len(csv_files)} fichiers CSV trouves\n")
    
    # Charger chaque fichier
    success_count = 0
    error_count = 0
    total_rows = 0
    
    for csv_file in sorted(csv_files):
        # Créer un nom de table basé sur le chemin
        table_name = get_relative_path_for_table(csv_file, csv_base_path)
        
        # Charger le fichier
        success, row_count = load_csv_to_duckdb(csv_file, table_name, con, load_id, history_counter)
        history_counter += 1
        
        if success:
            success_count += 1
            total_rows += row_count
        else:
            error_count += 1
    
    print()
    print("=" * 80)
    print("RESUME")
    print("=" * 80)
    print(f"[OK] Fichiers charges avec succes: {success_count}")
    print(f"[ERREUR] Fichiers en erreur: {error_count}")
    print(f"[INFO] Total de lignes chargees: {total_rows:,}")
    print()
    
    # Afficher les tables creees
    print("Tables creees dans le schema 'raw':")
    tables = con.execute("""
        SELECT table_name, 
               (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='raw' AND table_name=t.table_name) as nb_colonnes
        FROM information_schema.tables t
        WHERE table_schema = 'raw'
        ORDER BY table_name
    """).fetchall()
    
    for table, nb_cols in tables:
        row_count = con.execute(f"SELECT COUNT(*) FROM raw.{table}").fetchone()[0]
        print(f"  - {table}: {row_count:,} lignes, {nb_cols} colonnes")
    
    print()
    print("[SUCCES] Chargement termine!")
    
    # Fermer la connexion
    con.close()


if __name__ == "__main__":
    main()
