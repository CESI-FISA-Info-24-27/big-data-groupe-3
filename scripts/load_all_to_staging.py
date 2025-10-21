"""
Script principal pour charger toutes les données dans le staging DuckDB
Lance les chargements CSV et PostgreSQL en parallèle
"""

import subprocess
import sys
from pathlib import Path
from datetime import datetime
import io
import concurrent.futures

# Configurer l'encodage UTF-8 pour Windows
if sys.platform == 'win32':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')


def run_script(script_name: str) -> tuple[str, int, str]:
    """
    Exécute un script Python et retourne son résultat
    """
    script_path = Path(__file__).parent / script_name
    print(f"\n{'='*80}")
    print(f"Lancement de {script_name}...")
    print(f"{'='*80}\n")
    
    start_time = datetime.now()
    
    try:
        result = subprocess.run(
            [sys.executable, str(script_path)],
            capture_output=True,
            text=True,
            encoding='utf-8'
        )
        
        # Afficher la sortie en temps réel
        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        
        duration = (datetime.now() - start_time).total_seconds()
        
        if result.returncode == 0:
            status = "✓ SUCCÈS"
        else:
            status = "✗ ERREUR"
        
        return script_name, result.returncode, status, duration
        
    except Exception as e:
        duration = (datetime.now() - start_time).total_seconds()
        print(f"[ERREUR] Impossible d'exécuter {script_name}: {e}")
        return script_name, -1, "✗ ERREUR", duration


def main():
    """
    Lance tous les chargements
    """
    print("\n" + "="*80)
    print("CHARGEMENT COMPLET DU STAGING")
    print("="*80)
    print(f"Début: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80)
    
    scripts = [
        'load_csv_to_staging.py',
        'load_postgres_to_staging.py'
    ]
    
    start_time = datetime.now()
    
    # Lancer les scripts en parallèle
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        futures = [executor.submit(run_script, script) for script in scripts]
        results = [future.result() for future in concurrent.futures.as_completed(futures)]
    
    duration_total = (datetime.now() - start_time).total_seconds()
    
    # Afficher le résumé final
    print("\n" + "="*80)
    print("RÉSUMÉ FINAL")
    print("="*80)
    
    all_success = True
    for script_name, returncode, status, duration in sorted(results):
        print(f"{status} {script_name} (durée: {duration:.1f}s)")
        if returncode != 0:
            all_success = False
    
    print("="*80)
    print(f"Durée totale: {duration_total:.1f}s")
    print(f"Fin: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    if all_success:
        print("\n✓ Tous les chargements ont réussi!")
        return 0
    else:
        print("\n✗ Certains chargements ont échoué. Vérifiez les logs ci-dessus.")
        return 1


if __name__ == "__main__":
    sys.exit(main())





