#!/usr/bin/env python3
"""
Script pour corriger les schémas des tables datamart existantes
Résout les problèmes de types de données (ex: sexe VARCHAR(1) -> VARCHAR(10))
"""

import psycopg2
import os

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

POSTGRES_SCHEMA = 'datamart'

def fix_datamart_schemas():
    """Corrige les schémas des tables datamart"""
    
    print("=" * 70)
    print("CORRECTION DES SCHEMAS DATAMART")
    print("=" * 70)
    print()
    
    try:
        # Connexion PostgreSQL
        conn = psycopg2.connect(**POSTGRES_CONFIG)
        conn.autocommit = True  # Pour ALTER TABLE
        cursor = conn.cursor()
        
        print(f"[OK] Connecte a PostgreSQL: {POSTGRES_CONFIG['host']}:{POSTGRES_CONFIG['port']}/{POSTGRES_CONFIG['database']}")
        print()
        
        # Corrections à appliquer
        corrections = [
            # Table: dm_consultations_agregees
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_consultations_agregees ALTER COLUMN sexe TYPE VARCHAR(10);",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_consultations_agregees ALTER COLUMN tranche_age TYPE VARCHAR(50);",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_consultations_agregees ALTER COLUMN region_etablissement TYPE VARCHAR(100);",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_consultations_agregees ALTER COLUMN departement_etablissement TYPE VARCHAR(10);",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_consultations_agregees ALTER COLUMN nom_etablissement TYPE VARCHAR(500);",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_consultations_agregees ALTER COLUMN libelle_diagnostic TYPE TEXT;",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_consultations_agregees ALTER COLUMN chapitre_cim10 TYPE VARCHAR(200);",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_consultations_agregees ALTER COLUMN categorie_cim10 TYPE VARCHAR(200);",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_consultations_agregees ALTER COLUMN specialite TYPE VARCHAR(500);",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_consultations_agregees ALTER COLUMN fonction TYPE VARCHAR(200);",
            
            # Table: dm_hospitalisations_agregees
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_hospitalisations_agregees ALTER COLUMN sexe TYPE VARCHAR(10);",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_hospitalisations_agregees ALTER COLUMN tranche_age TYPE VARCHAR(50);",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_hospitalisations_agregees ALTER COLUMN region_etablissement TYPE VARCHAR(100);",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_hospitalisations_agregees ALTER COLUMN departement_etablissement TYPE VARCHAR(10);",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_hospitalisations_agregees ALTER COLUMN nom_etablissement TYPE VARCHAR(500);",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_hospitalisations_agregees ALTER COLUMN libelle_diagnostic TYPE TEXT;",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_hospitalisations_agregees ALTER COLUMN chapitre_cim10 TYPE VARCHAR(200);",
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_hospitalisations_agregees ALTER COLUMN categorie_cim10 TYPE VARCHAR(200);",
            
            # Table: dm_analyse_territoriale
            f"ALTER TABLE {POSTGRES_SCHEMA}.dm_analyse_territoriale ALTER COLUMN region TYPE VARCHAR(100);",
        ]
        
        print(f"[INFO] Application de {len(corrections)} corrections...")
        
        for i, correction in enumerate(corrections, 1):
            try:
                print(f"  [{i}/{len(corrections)}] Execution: {correction.split('ALTER COLUMN ')[1].split(' TYPE')[0]}")
                cursor.execute(correction)
                print(f"    [OK] Correction appliquee")
            except Exception as e:
                if "does not exist" in str(e) or "doesn't exist" in str(e):
                    print(f"    [SKIP] Table/colonne n'existe pas encore")
                elif "already exists" in str(e):
                    print(f"    [SKIP] Correction deja appliquee")
                else:
                    print(f"    [ATTENTION] {e}")
        
        cursor.close()
        conn.close()
        
        print()
        print("=" * 70)
        print("[SUCCES] Corrections des schemas appliquees !")
        print("=" * 70)
        print()
        print("Vous pouvez maintenant relancer le push des data marts")
        print()
        
        return True
        
    except Exception as e:
        print()
        print("=" * 70)
        print(f"[ERREUR] Correction echouee: {e}")
        print("=" * 70)
        return False

if __name__ == '__main__':
    success = fix_datamart_schemas()
    exit(0 if success else 1)
