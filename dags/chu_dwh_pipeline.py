"""
DAG Airflow pour orchestrer le pipeline CHU Data Warehouse

Architecture du Pipeline:
    1. Chargement données (CSV + PostgreSQL → DuckDB RAW)
    2. Transformations dbt (RAW → STAGING → ODS → DWH)
    3. Export DWH vers PostgreSQL
    4. Création Datamart dans PostgreSQL (optimisé)
    5. Tests de validation

Auteur: Équipe Big Data Groupe 3
Date: 2025-10-21
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from airflow.utils.task_group import TaskGroup
import os

# ============================================
# Configuration du DAG
# ============================================

default_args = {
    'owner': 'chu-dwh',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
    'execution_timeout': timedelta(hours=2),
}

# ============================================
# Définition du DAG
# ============================================

with DAG(
    'chu_dwh_pipeline',
    default_args=default_args,
    description='Pipeline complet CHU Data Warehouse',
    schedule_interval='0 2 * * *',  # Tous les jours à 2h du matin
    start_date=datetime(2025, 10, 21),
    catchup=False,
    tags=['chu', 'dwh', 'etl', 'healthcare'],
    max_active_runs=1,
) as dag:

    # ============================================
    # TASK GROUP 1: Chargement des Données
    # ============================================
    
    with TaskGroup('chargement_donnees', tooltip='Charger CSV et PostgreSQL vers DuckDB RAW') as chargement:
        
        load_csv = BashOperator(
            task_id='load_csv',
            bash_command='cd /opt/airflow && python scripts/load_csv_to_staging.py',
            doc_md="""
            ## Chargement CSV
            
            Charge tous les fichiers CSV dans DuckDB (schéma RAW):
            - Décès INSEE (~25M lignes)
            - Établissements FINESS (~416K lignes)
            - Hospitalisations (~2.5K lignes)
            - Satisfaction (31 fichiers)
            
            **Temps estimé**: 2-3 minutes
            """,
        )
        
        load_postgres = BashOperator(
            task_id='load_postgres',
            bash_command='cd /opt/airflow && python scripts/load_postgres_to_staging.py',
            doc_md="""
            ## Chargement PostgreSQL
            
            Charge toutes les tables PostgreSQL dans DuckDB (schéma RAW):
            - Patients (~100K lignes)
            - Professionnels (~1M lignes)
            - Consultations (~1M lignes)
            - Prescriptions (~2M lignes)
            - Autres tables métier
            
            **Temps estimé**: 1-2 minutes
            """,
        )
        
        # Les 2 chargements peuvent se faire en parallèle
        [load_csv, load_postgres]

    # ============================================
    # TASK 2: Transformations dbt
    # ============================================
    
    with TaskGroup('transformations_dbt', tooltip='Exécuter les transformations dbt') as transformations:
        
        dbt_deps = BashOperator(
            task_id='dbt_deps',
            bash_command='cd /opt/airflow/dbt && dbt deps',
            doc_md="""
            ## Installation packages dbt
            
            Installe les packages dbt nécessaires:
            - dbt_utils
            - dbt_date
            - dbt_expectations
            """,
        )
        
        dbt_staging = BashOperator(
            task_id='dbt_staging',
            bash_command='cd /opt/airflow/dbt && dbt run --select tag:staging',
            doc_md="""
            ## Transformation STAGING
            
            Nettoyage basique des données:
            - TRIM, UPPER, CAST
            - Parsing dates multi-format
            - Filtrage lignes invalides
            - Calculs simples (âge, durée)
            
            **Modèles**: 16  
            **Temps estimé**: 10-15 secondes
            """,
        )
        
        dbt_ods = BashOperator(
            task_id='dbt_ods',
            bash_command='cd /opt/airflow/dbt && dbt run --select tag:ods',
            doc_md="""
            ## Transformation ODS
            
            Intégration et enrichissement:
            - Jointures entre tables
            - Règles métier
            - Agrégations
            - Classifications métier
            
            **Modèles**: 9  
            **Temps estimé**: 15-20 secondes
            """,
        )
        
        dbt_dwh = BashOperator(
            task_id='dbt_dwh',
            bash_command='cd /opt/airflow/dbt && dbt run --select marts.dwh',
            doc_md="""
            ## Transformation DWH
            
            Création du modèle dimensionnel:
            - 8 Dimensions avec clés substituts (sk_*)
            - 5 Faits avec métriques
            - SCD Type 2 (dim_professionnel)
            - Anonymisation RGPD (SHA-256)
            
            **Modèles**: 13 (8 dims + 5 faits)  
            **Temps estimé**: 20-30 secondes
            """,
        )
        
        # Ordre des transformations dbt
        dbt_deps >> dbt_staging >> dbt_ods >> dbt_dwh

    # ============================================
    # TASK 3: Export DWH vers PostgreSQL
    # ============================================
    
    push_dwh = BashOperator(
        task_id='push_dwh_to_postgres',
        bash_command='cd /opt/airflow && python scripts/push_dwh_to_postgres.py',
        doc_md="""
        ## Push DWH vers PostgreSQL
        
        Exporte le DWH de DuckDB vers PostgreSQL:
        - 8 dimensions (ordre: pas de FK entre elles)
        - 5 faits (ordre: avec FK vers dimensions)
        - Utilise COPY pour performance
        
        **Volume**: ~27M lignes  
        **Temps estimé**: 2-3 minutes
        """,
    )

    # ============================================
    # TASK 4: Création Datamart (Optimisé)
    # ============================================
    
    build_datamart = BashOperator(
        task_id='build_datamart_postgres',
        bash_command='cd /opt/airflow && python scripts/build_datamart_via_postgres.py',
        doc_md="""
        ## Création Datamart (Optimisé)
        
        Crée le datamart directement dans PostgreSQL via extension DuckDB:
        - dm_consultations_agregees (~45M lignes agrégées)
        - dm_hospitalisations_agregees (~6K lignes)
        - dm_analyse_territoriale (~30K lignes)
        
        **Méthode**: DuckDB extension postgres (pas de transfert de données)  
        **Temps estimé**: 6-8 minutes  
        **Gain**: 70% plus rapide que l'ancienne méthode
        """,
    )

    # ============================================
    # TASK GROUP 5: Tests de Validation
    # ============================================
    
    with TaskGroup('validation', tooltip='Tests de validation') as validation:
        
        dbt_test = BashOperator(
            task_id='dbt_test',
            bash_command='cd /opt/airflow/dbt && dbt test',
            doc_md="""
            ## Tests dbt
            
            Exécute tous les tests de qualité:
            - Unicité des business keys
            - Non-nullité des FK
            - Relations référentielles
            - Tests personnalisés
            
            **Temps estimé**: 30-60 secondes
            """,
        )
        
        test_postgres_extension = BashOperator(
            task_id='test_postgres_extension',
            bash_command='cd /opt/airflow && python scripts/test_datamart_postgres_extension.py',
            trigger_rule='all_done',  # Exécuter même si dbt_test échoue
            doc_md="""
            ## Test Extension Postgres
            
            Valide que l'extension DuckDB Postgres fonctionne:
            - Connexion PostgreSQL
            - Lecture/Écriture
            - Requêtes complexes
            
            **Temps estimé**: 10 secondes
            """,
        )
        
        [dbt_test, test_postgres_extension]

    # ============================================
    # TASK 6: Notification (Success)
    # ============================================
    
    def notify_success(**context):
        """Notification de succès du pipeline"""
        execution_date = context['execution_date']
        print("=" * 70)
        print("✅ PIPELINE CHU DWH TERMINÉ AVEC SUCCÈS")
        print("=" * 70)
        print(f"Date d'exécution: {execution_date}")
        print(f"Durée: {context['ti'].duration} secondes")
        print()
        print("Résultats:")
        print("  ✅ Données chargées dans RAW")
        print("  ✅ Transformations dbt complétées")
        print("  ✅ DWH poussé vers PostgreSQL")
        print("  ✅ Datamart créé dans PostgreSQL")
        print("  ✅ Tests de validation passés")
        print()
        print("Prochaine exécution: Demain à 2h du matin")
        print("=" * 70)
    
    success_notification = PythonOperator(
        task_id='notify_success',
        python_callable=notify_success,
        trigger_rule='all_success',
    )

    # ============================================
    # TASK 7: Notification (Failure)
    # ============================================
    
    def notify_failure(**context):
        """Notification d'échec du pipeline"""
        execution_date = context['execution_date']
        task_instance = context['task_instance']
        print("=" * 70)
        print("❌ PIPELINE CHU DWH ÉCHOUÉ")
        print("=" * 70)
        print(f"Date d'exécution: {execution_date}")
        print(f"Tâche échouée: {task_instance.task_id}")
        print()
        print("Actions recommandées:")
        print("  1. Vérifier les logs Airflow")
        print("  2. Vérifier que PostgreSQL DWH est démarré")
        print("  3. Vérifier les données sources")
        print("  4. Relancer manuellement si nécessaire")
        print("=" * 70)
    
    failure_notification = PythonOperator(
        task_id='notify_failure',
        python_callable=notify_failure,
        trigger_rule='one_failed',
    )

    # ============================================
    # Définition du Workflow (Ordre des Tâches)
    # ============================================
    
    # Pipeline linéaire avec validation finale
    chargement >> transformations >> push_dwh >> build_datamart >> validation
    
    # Notifications
    validation >> [success_notification, failure_notification]


# ============================================
# Documentation du DAG
# ============================================

dag.doc_md = """
# Pipeline CHU Data Warehouse

## 📊 Vue d'Ensemble

Ce DAG orchestre le pipeline complet du Data Warehouse CHU:

1. **Chargement** (parallèle): CSV + PostgreSQL → DuckDB RAW
2. **Transformations dbt**: STAGING → ODS → DWH
3. **Export**: DWH → PostgreSQL
4. **Datamart**: Agrégations optimisées dans PostgreSQL
5. **Validation**: Tests dbt + extension Postgres

## ⏱️ Planification

- **Schedule**: Quotidien à 2h du matin
- **Durée estimée**: ~15 minutes
- **Timeout**: 2 heures max

## 📈 Volumétrie

- **Sources**: ~30M lignes
- **DWH**: ~27M lignes (8 dims + 5 faits)
- **Datamart**: ~45M lignes agrégées

## 🔗 Dépendances

- PostgreSQL DWH (port 5433)
- PostgreSQL Source (optionnel si CSV uniquement)
- DuckDB (fichier local)
- dbt packages installés

## 📚 Documentation

Voir `docs/INDEX_TRANSFORMATIONS.md` pour la documentation complète.
"""

