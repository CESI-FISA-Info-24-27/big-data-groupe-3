#!/usr/bin/env python3
"""
Script d'administration du pipeline CHU Data Warehouse
Permet de lancer le full build ou des étapes spécifiques

Usage:
    python admin_pipeline.py                    # Mode interactif
    python admin_pipeline.py --full             # Full build automatique
    python admin_pipeline.py --step 1           # Étape spécifique
    python admin_pipeline.py --step 1,2,3       # Plusieurs étapes
    
Étapes disponibles:
    1. Chargement des données CSV dans DuckDB (staging)
    2. Exécution dbt (création ODS et DWH dans DuckDB)
    3. Push du DWH vers PostgreSQL
    4. Création du datamart dans PostgreSQL (optimisé)
    5. Tests de validation
"""

import os
import sys
import subprocess
import time
import argparse
from pathlib import Path
from datetime import datetime

# Couleurs pour le terminal (Windows compatible)
try:
    import colorama
    colorama.init()
    GREEN = colorama.Fore.GREEN
    RED = colorama.Fore.RED
    YELLOW = colorama.Fore.YELLOW
    BLUE = colorama.Fore.BLUE
    CYAN = colorama.Fore.CYAN
    RESET = colorama.Fore.RESET
except ImportError:
    GREEN = RED = YELLOW = BLUE = CYAN = RESET = ""

# Configuration
SCRIPTS_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPTS_DIR.parent
DBT_DIR = PROJECT_ROOT / "dbt"

# Définition des étapes du pipeline
PIPELINE_STEPS = {
    1: {
        'name': 'Chargement des données CSV',
        'description': 'Charger les données CSV dans DuckDB (schéma RAW)',
        'script': 'load_all_to_staging.py',
        'estimated_time': '5 min',
        'required': True
    },
    2: {
        'name': 'Exécution dbt',
        'description': 'Créer ODS et DWH dans DuckDB (via dbt)',
        'script': 'dbt_run',
        'estimated_time': '2 min',
        'required': True
    },
    3: {
        'name': 'Push DWH vers PostgreSQL',
        'description': 'Pousser le DWH de DuckDB vers PostgreSQL',
        'script': 'push_dwh_to_postgres.py',
        'estimated_time': '3 min',
        'required': True
    },
    4: {
        'name': 'Création datamart PostgreSQL',
        'description': 'Créer le datamart directement dans PostgreSQL (optimisé)',
        'script': 'build_datamart_via_postgres.py',
        'estimated_time': '8 min',
        'required': False
    },
    5: {
        'name': 'Tests de validation',
        'description': 'Exécuter les tests dbt et de validation',
        'script': 'tests',
        'estimated_time': '1 min',
        'required': False
    }
}


def print_header(title):
    """Afficher un en-tête formaté"""
    print(f"\n{CYAN}{'=' * 70}")
    print(f"{title:^70}")
    print(f"{'=' * 70}{RESET}\n")


def print_step(step_num, status="INFO"):
    """Afficher une étape du pipeline"""
    step = PIPELINE_STEPS[step_num]
    color = BLUE if status == "INFO" else GREEN if status == "SUCCESS" else RED if status == "ERROR" else YELLOW
    
    print(f"{color}[ÉTAPE {step_num}] {step['name']}{RESET}")
    print(f"  Description : {step['description']}")
    print(f"  Temps estimé : {step['estimated_time']}")
    if status == "INFO":
        print(f"  Requis : {'Oui' if step['required'] else 'Non (optionnel)'}")
    print()


def run_command(cmd, cwd=None, description=""):
    """
    Exécuter une commande et afficher le résultat
    """
    print(f"{BLUE}[CMD] {description}{RESET}")
    print(f"  Commande : {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    print(f"  Répertoire : {cwd or 'Courant'}")
    print()
    
    start_time = time.time()
    
    try:
        # Exécuter la commande
        result = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            shell=True if isinstance(cmd, str) else False
        )
        
        elapsed = time.time() - start_time
        
        # Afficher la sortie
        if result.stdout:
            print(result.stdout)
        
        if result.returncode == 0:
            print(f"{GREEN}✅ Succès (temps: {elapsed:.1f}s){RESET}\n")
            return True
        else:
            print(f"{RED}❌ Erreur (code: {result.returncode}){RESET}")
            if result.stderr:
                print(f"{RED}Détails:{RESET}")
                print(result.stderr)
            print()
            return False
            
    except Exception as e:
        print(f"{RED}❌ Erreur d'exécution : {e}{RESET}\n")
        return False


def step_1_load_data():
    """Étape 1 : Chargement des données CSV"""
    print_step(1, "INFO")
    
    script_path = SCRIPTS_DIR / "load_all_to_staging.py"
    
    if not script_path.exists():
        print(f"{RED}❌ Script introuvable : {script_path}{RESET}\n")
        return False
    
    return run_command(
        [sys.executable, str(script_path)],
        cwd=str(PROJECT_ROOT),
        description="Chargement des données CSV dans DuckDB"
    )


def step_2_dbt_run():
    """Étape 2 : Exécution dbt"""
    print_step(2, "INFO")
    
    if not DBT_DIR.exists():
        print(f"{RED}❌ Répertoire dbt introuvable : {DBT_DIR}{RESET}\n")
        return False
    
    # Option 1 : dbt run complet
    print(f"{YELLOW}Exécution dbt run (tous les modèles)...{RESET}\n")
    
    success = run_command(
        [sys.executable, "-m", "dbt", "run"],
        cwd=str(DBT_DIR),
        description="Création des modèles dbt (staging + ODS + DWH)"
    )
    
    return success


def step_3_push_dwh():
    """Étape 3 : Push DWH vers PostgreSQL"""
    print_step(3, "INFO")
    
    script_path = SCRIPTS_DIR / "push_dwh_to_postgres.py"
    
    if not script_path.exists():
        print(f"{RED}❌ Script introuvable : {script_path}{RESET}\n")
        return False
    
    return run_command(
        [sys.executable, str(script_path)],
        cwd=str(PROJECT_ROOT),
        description="Push DWH vers PostgreSQL"
    )


def step_4_build_datamart():
    """Étape 4 : Création datamart PostgreSQL"""
    print_step(4, "INFO")
    
    script_path = SCRIPTS_DIR / "build_datamart_via_postgres.py"
    
    if not script_path.exists():
        print(f"{RED}❌ Script introuvable : {script_path}{RESET}\n")
        return False
    
    return run_command(
        [sys.executable, str(script_path)],
        cwd=str(PROJECT_ROOT),
        description="Création datamart dans PostgreSQL (optimisé)"
    )


def step_5_run_tests():
    """Étape 5 : Tests de validation"""
    print_step(5, "INFO")
    
    # Test 1 : Tests dbt
    print(f"{BLUE}[TEST 1] Tests dbt{RESET}\n")
    success_dbt = run_command(
        [sys.executable, "-m", "dbt", "test"],
        cwd=str(DBT_DIR),
        description="Exécution des tests dbt"
    )
    
    # Test 2 : Test extension Postgres
    print(f"{BLUE}[TEST 2] Test extension Postgres{RESET}\n")
    test_script = SCRIPTS_DIR / "test_datamart_postgres_extension.py"
    
    success_postgres = True
    if test_script.exists():
        success_postgres = run_command(
            [sys.executable, str(test_script)],
            cwd=str(PROJECT_ROOT),
            description="Test de l'extension PostgreSQL"
        )
    else:
        print(f"{YELLOW}⚠️  Script de test introuvable, passage...{RESET}\n")
    
    return success_dbt and success_postgres


def full_build():
    """Exécuter le pipeline complet"""
    print_header("FULL BUILD - Pipeline Complet")
    
    print(f"{CYAN}Ce processus va exécuter toutes les étapes du pipeline :{RESET}")
    print(f"  1. Chargement des données CSV")
    print(f"  2. Exécution dbt (ODS + DWH)")
    print(f"  3. Push DWH vers PostgreSQL")
    print(f"  4. Création datamart dans PostgreSQL")
    print(f"  5. Tests de validation")
    print()
    
    total_time = sum(
        int(step['estimated_time'].split()[0]) 
        for step in PIPELINE_STEPS.values()
    )
    print(f"{YELLOW}⏱️  Temps estimé total : ~{total_time} minutes{RESET}\n")
    
    start_time = time.time()
    results = {}
    
    # Exécuter toutes les étapes
    steps_to_run = [
        (1, step_1_load_data),
        (2, step_2_dbt_run),
        (3, step_3_push_dwh),
        (4, step_4_build_datamart),
        (5, step_5_run_tests)
    ]
    
    for step_num, step_func in steps_to_run:
        print(f"\n{CYAN}{'─' * 70}{RESET}")
        success = step_func()
        results[step_num] = success
        
        if not success and PIPELINE_STEPS[step_num]['required']:
            print(f"{RED}❌ Étape {step_num} échouée (requise). Arrêt du pipeline.{RESET}")
            break
        elif not success:
            print(f"{YELLOW}⚠️  Étape {step_num} échouée (optionnelle). Continuation...{RESET}")
    
    # Résumé
    elapsed = time.time() - start_time
    print_header("RÉSUMÉ DU PIPELINE")
    
    success_count = sum(1 for success in results.values() if success)
    total_count = len(results)
    
    print(f"{CYAN}Résultats par étape :{RESET}\n")
    for step_num, success in results.items():
        status = f"{GREEN}✅ SUCCÈS{RESET}" if success else f"{RED}❌ ÉCHEC{RESET}"
        print(f"  Étape {step_num} - {PIPELINE_STEPS[step_num]['name']}: {status}")
    
    print(f"\n{CYAN}Statistiques :{RESET}")
    print(f"  • Étapes réussies : {success_count}/{total_count}")
    print(f"  • Temps total : {elapsed/60:.1f} minutes")
    print(f"  • Date : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    if success_count == total_count:
        print(f"{GREEN}{'=' * 70}")
        print(f"✅ SUCCÈS ! Pipeline complet exécuté avec succès")
        print(f"{'=' * 70}{RESET}\n")
        return True
    else:
        print(f"{YELLOW}{'=' * 70}")
        print(f"⚠️  Pipeline terminé avec {total_count - success_count} erreur(s)")
        print(f"{'=' * 70}{RESET}\n")
        return False


def interactive_mode():
    """Mode interactif avec menu"""
    while True:
        print_header("ADMINISTRATION PIPELINE CHU DWH")
        
        print(f"{CYAN}Choisissez une option :{RESET}\n")
        print(f"  {GREEN}0{RESET} - Full Build (toutes les étapes)")
        print()
        
        for step_num, step in PIPELINE_STEPS.items():
            required_tag = f"{RED}[REQUIS]{RESET}" if step['required'] else f"{YELLOW}[OPTIONNEL]{RESET}"
            print(f"  {GREEN}{step_num}{RESET} - {step['name']} {required_tag}")
            print(f"      {step['description']}")
            print(f"      Temps estimé : {step['estimated_time']}")
            print()
        
        print(f"  {RED}q{RESET} - Quitter")
        print()
        
        choice = input(f"{CYAN}Votre choix : {RESET}").strip()
        
        if choice.lower() == 'q':
            print(f"\n{YELLOW}👋 Au revoir !{RESET}\n")
            break
        
        if choice == '0':
            full_build()
            input(f"\n{CYAN}Appuyez sur Entrée pour continuer...{RESET}")
            continue
        
        try:
            step_num = int(choice)
            if step_num not in PIPELINE_STEPS:
                print(f"\n{RED}❌ Choix invalide. Choisissez entre 0 et {len(PIPELINE_STEPS)}.{RESET}\n")
                time.sleep(2)
                continue
            
            # Exécuter l'étape choisie
            step_functions = {
                1: step_1_load_data,
                2: step_2_dbt_run,
                3: step_3_push_dwh,
                4: step_4_build_datamart,
                5: step_5_run_tests
            }
            
            success = step_functions[step_num]()
            
            if success:
                print(f"\n{GREEN}✅ Étape {step_num} terminée avec succès !{RESET}")
            else:
                print(f"\n{RED}❌ Étape {step_num} a échoué.{RESET}")
            
            input(f"\n{CYAN}Appuyez sur Entrée pour continuer...{RESET}")
            
        except ValueError:
            print(f"\n{RED}❌ Choix invalide. Entrez un nombre ou 'q'.{RESET}\n")
            time.sleep(2)


def run_specific_steps(steps_list):
    """Exécuter des étapes spécifiques"""
    print_header(f"Exécution des étapes : {', '.join(map(str, steps_list))}")
    
    step_functions = {
        1: step_1_load_data,
        2: step_2_dbt_run,
        3: step_3_push_dwh,
        4: step_4_build_datamart,
        5: step_5_run_tests
    }
    
    results = {}
    
    for step_num in steps_list:
        if step_num not in PIPELINE_STEPS:
            print(f"{RED}❌ Étape {step_num} invalide. Ignorée.{RESET}\n")
            continue
        
        print(f"\n{CYAN}{'─' * 70}{RESET}")
        success = step_functions[step_num]()
        results[step_num] = success
    
    # Résumé
    print_header("RÉSUMÉ")
    
    for step_num, success in results.items():
        status = f"{GREEN}✅ SUCCÈS{RESET}" if success else f"{RED}❌ ÉCHEC{RESET}"
        print(f"  Étape {step_num} - {PIPELINE_STEPS[step_num]['name']}: {status}")
    
    print()
    return all(results.values())


def main():
    """Fonction principale"""
    parser = argparse.ArgumentParser(
        description="Script d'administration du pipeline CHU DWH",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemples d'utilisation:
  python admin_pipeline.py                    # Mode interactif
  python admin_pipeline.py --full             # Full build
  python admin_pipeline.py --step 1           # Étape 1 uniquement
  python admin_pipeline.py --step 1,2,3       # Étapes 1, 2 et 3
  python admin_pipeline.py --step 4           # Datamart uniquement
        """
    )
    
    parser.add_argument(
        '--full',
        action='store_true',
        help='Exécuter le full build (toutes les étapes)'
    )
    
    parser.add_argument(
        '--step',
        type=str,
        help='Étape(s) à exécuter (ex: 1 ou 1,2,3)'
    )
    
    args = parser.parse_args()
    
    # Vérifier qu'on est dans le bon répertoire
    if not PROJECT_ROOT.exists():
        print(f"{RED}❌ Erreur : Le projet CHU DWH n'a pas été trouvé.{RESET}")
        print(f"   Assurez-vous d'exécuter ce script depuis le répertoire du projet.")
        sys.exit(1)
    
    # Mode full build
    if args.full:
        success = full_build()
        sys.exit(0 if success else 1)
    
    # Mode étapes spécifiques
    elif args.step:
        try:
            steps = [int(s.strip()) for s in args.step.split(',')]
            success = run_specific_steps(steps)
            sys.exit(0 if success else 1)
        except ValueError:
            print(f"{RED}❌ Erreur : Format d'étapes invalide. Utilisez par exemple: --step 1,2,3{RESET}")
            sys.exit(1)
    
    # Mode interactif par défaut
    else:
        interactive_mode()
        sys.exit(0)


if __name__ == '__main__':
    main()

