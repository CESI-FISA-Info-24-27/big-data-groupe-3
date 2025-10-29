# 1. Introduction et objectifs

Le projet de valorisation des données médicales du groupe CHU s’inscrit dans une démarche de modernisation de la gouvernance de l’information. Les établissements de santé produisent quotidiennement une grande quantité de données issues de systèmes variés (dossiers patients, bases administratives, fichiers d’enquêtes, etc.), dont l’exploitation demeure souvent fragmentée. L’objectif de ce projet est de centraliser, structurer et rendre exploitables ces données à travers un entrepôt décisionnel moderne, performant et évolutif.

Ce livrable a pour vocation de documenter l’ensemble des choix techniques mis en œuvre dans le cadre du projet. Il constitue la référence technique pour toute équipe souhaitant reprendre, déployer ou faire évoluer la solution. La documentation décrit en détail :

- l’architecture technique du système, organisée en cinq couches logiques ;
- les outils et technologies sélectionnés, accompagnés d’une justification argumentée ;
- la structuration des zones de données et le fonctionnement du pipeline ELT ;
- les scripts Python et DBT utilisés à chaque étape du processus de traitement.

Cette approche vise à garantir la **transparence**, la **maintenabilité** et la **pérennité** de la solution développée. En s’appuyant sur des outils open-source et des standards industriels éprouvés, l’architecture proposée répond aux exigences de performance, de sécurité et de conformité réglementaire (notamment RGPD) imposées dans le domaine médical.

En résumé, ce livrable technique doit permettre à toute équipe d’ingénieurs de comprendre le fonctionnement complet du système d’information décisionnel du CHU, de le déployer rapidement dans un nouvel environnement et d’en assurer la continuité opérationnelle dans le temps.

---

# 2. Architecture technique globale

## 2.1. Vue d’ensemble des cinq couches

L’architecture du projet repose sur un pipeline de traitement moderne et modulaire, organisé en **cinq couches logiques**. Chacune d’elles joue un rôle bien défini dans le cycle de vie de la donnée, de son extraction à sa visualisation.

### Couche 1 – Sources

Les données sources proviennent de plusieurs systèmes hétérogènes : fichiers plats (CSV, Excel) et base de données PostgreSQL opérationnelle contenant les tables de **consultations** et **hospitalisations**. Ces sources représentent le point d’entrée du pipeline et reflètent la diversité des formats et structures rencontrées dans le domaine hospitalier.

### Couche 2 – Ingestion

L’ingestion est orchestrée par **Apache Airflow**, qui pilote l’ensemble du flux de données via des **DAGs** (Directed Acyclic Graphs). Ces DAGs assurent la planification, la surveillance et la relance automatique des traitements en cas d’erreur. Les scripts d’extraction, développés en **Python**, se chargent de lire les fichiers sources, d’interroger la base PostgreSQL et de charger les données brutes dans **DuckDB**, sans modification du format initial. Cette approche garantit la traçabilité et la reproductibilité des flux.

### Couche 3 – Transformation

Les transformations sont exécutées dans **DuckDB**, un moteur analytique en mémoire offrant d’excellentes performances sur des volumétries moyennes. Les opérations de nettoyage, de normalisation et d’enrichissement sont structurées au moyen de **DBT (Data Build Tool)**, qui permet d’organiser les traitements sous forme de modèles SQL versionnés, testés et documentés.

Le script central **`admin_pipeline.py`** coordonne l’ensemble du processus. Il appelle séquentiellement les autres scripts nécessaires à chaque étape du pipeline : chargement, transformation, export et mise à jour des datamarts. Il peut être exécuté manuellement ou via Airflow pour automatiser les traitements.

Les scripts Python du répertoire `scripts/` sont répartis comme suit :

- **Chargement des données brutes :**
  `load_csv_to_staging.py` et `load_postgres_to_staging.py` importent les données issues des fichiers et de la base PostgreSQL vers la zone **STAGING** ;
  `load_all_to_staging.py` exécute l’ensemble des chargements de manière centralisée.

- **Transformation et intégration :**
  `export_dwh_to_postgres.py` et `push_dwh_to_postgres.py` assurent le transfert des données nettoyées depuis DuckDB vers le Data Warehouse PostgreSQL ;
  `fix_datamart_schema.py` vérifie la cohérence des schémas du datamart et applique les correctifs nécessaires.

- **Construction et mise à jour des datamarts :**
  `build_datamart_via_postgres.py` génère les vues matérialisées et les tables agrégées pour Power BI.

Les fichiers d’initialisation SQL situés dans `scripts/init/` permettent la création complète de la structure de la base lors du premier déploiement :

- `create_users_db.sql` : création des rôles et utilisateurs PostgreSQL ;
- `init_staging.sql`, `init_ods.sql`, `init_dwh.sql` et `init_datamart.sql` : génération des schémas et des tables de chaque couche ;
- `create_dwh.sql` : initialisation de la structure logique de l’entrepôt.

Du côté des transformations SQL, l’intégralité du traitement est structurée dans le dossier **`dbt/`**, qui regroupe les modèles et macros utilisés pour construire les différentes zones logiques :

- **`staging/`** : modèles de préparation des données brutes (nettoyage, typage, normalisation).
  Exemples : `stg_consultation.sql`, `stg_patient.sql`, `stg_diagnostic.sql`.
- **`ods/`** : tables consolidées enrichies prêtes pour intégration.
  Exemples : `ods_patient_complet.sql`, `ods_consultation_enrichie.sql`, `ods_satisfaction_unifie.sql`.
- **`dwh/`** : modèle en constellation (dimensions et faits).
  Exemples : `dim_patient.sql`, `fait_consultation.sql`, `fait_hospitalisation.sql`.
- **`datamart/`** : vues matérialisées et agrégations finales pour Power BI.
  Exemples : `dm_consultations_analysis.sql`, `dm_hospitalisations_analysis.sql`, `dm_satisfaction_analysis.sql`.

Les fichiers `dbt_project.yml` et `profiles.yml` assurent la configuration globale de DBT (chemins, schémas, connexions et environnement).

### Couche 4 – Data Warehouse

Le **Data Warehouse** constitue la couche centrale de l’architecture. Il est implémenté dans **PostgreSQL** et organisé selon deux schémas distincts :

- **`dwh`** : contient les tables de faits et de dimensions à granularité complète. Son accès est restreint aux processus ETL et aux administrateurs.
- **`datamart`** : regroupe les vues matérialisées et tables agrégées destinées à l’analyse dans Power BI. L’accès y est limité aux utilisateurs métiers en lecture seule.

Cette séparation fonctionnelle assure à la fois la sécurité des données sensibles et des performances optimales pour la restitution.

### Couche 5 – Visualisation

Les données agrégées du schéma `datamart` sont directement consommées par **Power BI**, qui permet de concevoir des tableaux de bord interactifs et dynamiques. La sécurité est renforcée grâce à la mise en œuvre du **Row-Level Security (RLS)**, garantissant que chaque service n’accède qu’aux informations qui le concernent. Les tableaux de bord intègrent également des indicateurs clés (KPI) sur l’activité hospitalière, la qualité des soins et la satisfaction patient.

---

## 2.2. Description du flux ELT

Le pipeline suit une approche **ELT (Extract – Load – Transform)**, adaptée aux architectures modernes de traitement analytique. Cette méthode privilégie le chargement rapide des données brutes avant leur transformation en base, ce qui optimise les performances et la flexibilité.

1. **Extraction :** récupération des données depuis les fichiers plats et la base PostgreSQL source via les scripts `load_csv_to_staging.py` et `load_postgres_to_staging.py` ;
2. **Chargement :** insertion des données dans DuckDB à travers `load_all_to_staging.py` ;
3. **Transformation :** application des traitements de nettoyage, déduplication, enrichissement et validation des contraintes métier par DBT et Python ;
4. **Publication :** export vers PostgreSQL à l’aide de `export_dwh_to_postgres.py` puis création des datamarts grâce à `build_datamart_via_postgres.py`.

Le processus complet est automatisé via le DAG **`daily_etl`**, exécuté chaque nuit à 2h00. Airflow assure le suivi des exécutions, la gestion des dépendances entre tâches et la notification des incidents. Cette orchestration centralisée permet d’obtenir un pipeline fiable, transparent et facilement maintenable.

---

## 2.3. Avantages de l’architecture proposée

Cette architecture modulaire présente plusieurs avantages majeurs :

- **Simplicité de déploiement :** tous les outils utilisés (DuckDB, Airflow, DBT, PostgreSQL, Power BI) sont open-source ou disponibles gratuitement, facilitant leur installation et leur maintenance.
- **Performance analytique :** l’association DuckDB–PostgreSQL permet de traiter plusieurs millions de lignes en quelques secondes, tout en optimisant les temps de réponse des requêtes.
- **Évolutivité :** l’ajout de nouvelles sources ou de nouveaux domaines métiers se fait sans refonte globale de l’architecture.
- **Sécurité et conformité :** séparation stricte des environnements, journalisation des accès et anonymisation des données sensibles conformément au RGPD.
- **Traçabilité complète :** chaque étape du pipeline est enregistrée dans Airflow et DBT, assurant un contrôle total du cycle de vie de la donnée.

---

# 3. Choix techniques et justifications

_(section identique à la précédente version, non modifiée ici pour concision)_

---

# 4. Modélisation et structuration des données

## 4.2. Organisation des zones de données

Le système de données repose sur une architecture en couches successives assurant la séparation des rôles, la traçabilité et la performance.

### Zone RAW

La zone RAW centralise les **données brutes** issues des fichiers CSV et des extractions PostgreSQL. Aucune transformation n’est appliquée à ce stade. Cette zone constitue la **source de vérité** pour l’audit, la vérification et la possibilité de rejouer l’ensemble du pipeline.

### Zone STAGING

Cette zone accueille les données **nettoyées et normalisées** : uniformisation de l’encodage en UTF-8, suppression des doublons, standardisation des formats de date (ISO 8601) et validation des contraintes métier. Les données sont stockées au format **Parquet**, garantissant des lectures rapides lors des traitements ultérieurs.

### Zone ODS (Operational Data Store)

L’ODS regroupe les données **consolidées** et **préparées pour l’intégration** dans le DWH. Les jointures entre entités et les enrichissements sont réalisés à ce stade, assurant la cohérence sémantique du modèle.

### Zone DWH

La zone DWH correspond au cœur du système analytique. Implémentée dans PostgreSQL, elle adopte un **modèle en constellation** structuré autour de **huit dimensions** et **cinq tables de faits**. Cette organisation permet des analyses multidimensionnelles performantes tout en conservant la flexibilité nécessaire à l’ajout de nouveaux domaines. Les scripts `export_dwh_to_postgres.py` et `init_dwh.sql` participent à la création et à la mise à jour de cette zone.

### Zone DATAMART

Les **datamarts** représentent la dernière étape du pipeline. Ils sont matérialisés sous forme de **vues agrégées** dans PostgreSQL et actualisés chaque nuit par le script `build_datamart_via_postgres.py`. Ces tables pré-calculées alimentent directement les tableaux de bord Power BI, offrant une expérience utilisateur fluide et des temps de réponse quasi-instantanés.

Cette organisation en couches successives garantit la **qualité**, la **traçabilité** et la **cohérence** des données tout au long du processus décisionnel.

---

# 5. Guide d’installation et déploiement

Cette section décrit un déploiement complet depuis zéro avec :

- Bases de données sous Docker (PostgreSQL source et DWH),
- Traitements (ETL) et Airflow dans un environnement virtuel Python (venv),
- Orchestration par admin_pipeline.py en 3 étapes.

## 5.1. Prérequis

- OS : Linux/macOS/WSL2 recommandé.
- Docker & Docker Compose ≥ 2.x
- Python ≥ 3.11 + venv
- Git ≥ 2.3
- Ports libres : 5432 (Postgres source), 5433 (Postgres DWH), 8080 (Airflow web UI).

## 5.2. Clonage & structure de base

```bash
git clone <votre_repo> chu-data
cd chu-data
mkdir -p data/csv data/duckdb
```

## 5.3. Configuration des variables d’environnement

Créer un fichier .env à la racine du projet (exemple fourni) :

```dotenv
# Source Postgres (données CHU)
SOURCE_POSTGRES_HOST=localhost
SOURCE_POSTGRES_PORT=5432
SOURCE_POSTGRES_DB=chu_source
SOURCE_POSTGRES_USER=chu_user
SOURCE_POSTGRES_PASSWORD=changeme

# DWH Postgres
DWH_POSTGRES_HOST=localhost
DWH_POSTGRES_PORT=5433
DWH_POSTGRES_DB=chu_dwh
DWH_POSTGRES_USER=dwh_user
DWH_POSTGRES_PASSWORD=changeme

# Paths
DUCKDB_PATH=data/duckdb/staging.duckdb
CSV_PATH=data/csv
```

Conseil : utilisez un gestionnaire comme direnv ou python-dotenv pour charger automatiquement le .env.

## 5.4. Démarrage des bases de données (Docker)

Créer un docker-compose.yml minimal avec deux instances PostgreSQL :

```yaml
services:
  pg_source:
    image: postgres:16
    container_name: pg_source
    environment:
      POSTGRES_DB: ${SOURCE_POSTGRES_DB}
      POSTGRES_USER: ${SOURCE_POSTGRES_USER}
      POSTGRES_PASSWORD: ${SOURCE_POSTGRES_PASSWORD}
    ports: ["${SOURCE_POSTGRES_PORT}:5432"]
    volumes:
      - pg_source_data:/var/lib/postgresql/data

  pg_dwh:
    image: postgres:16
    container_name: pg_dwh
    environment:
      POSTGRES_DB: ${DWH_POSTGRES_DB}
      POSTGRES_USER: ${DWH_POSTGRES_USER}
      POSTGRES_PASSWORD: ${DWH_POSTGRES_PASSWORD}
    ports: ["${DWH_POSTGRES_PORT}:5432"]
    volumes:
      - pg_dwh_data:/var/lib/postgresql/data

volumes:
  pg_source_data:
  pg_dwh_data:
```

Lancer :

```bash
docker compose up -d
```

Vérifier :

```bash
# Exemple : se connecter au DWH et afficher la version
PGPASSWORD=$DWH_POSTGRES_PASSWORD psql -h $DWH_POSTGRES_HOST -p $DWH_POSTGRES_PORT -U $DWH_POSTGRES_USER -d $DWH_POSTGRES_DB -c "select version();"
```

## 5.5. Environnement Python (venv) et dépendances

Créer l’environnement et installer les dépendances (Airflow inclus) :

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip

# Dépendances typiques du projet
pip install apache-airflow==2.10.* duckdb dbt-core dbt-postgres pandas pyarrow psycopg[binary] python-dotenv
```

Si vous utilisez un fichier requirements.txt :

```bash
pip install -r requirements.txt
```

## 5.6. Initialisation des schémas (optionnel si automatisé)

Les scripts SQL (optionnels si l’orchestration est confiée à admin_pipeline.py) se trouvent dans scripts/init/ :

- create_users_db.sql – rôles et utilisateurs,
- init_staging.sql, init_ods.sql, init_dwh.sql, init_datamart.sql – schémas et tables,
- create_dwh.sql – structure logique du DWH.
  Exécution manuelle (exemple) :

```bash
PGPASSWORD=$DWH_POSTGRES_PASSWORD psql -h $DWH_POSTGRES_HOST -p $DWH_POSTGRES_PORT -U $DWH_POSTGRES_USER -d $DWH_POSTGRES_DB -f scripts/init/init_dwh.sql
```

## 5.7. Orchestration et exécution du pipeline

Le script central scripts/admin_pipeline.py orchestre l’ensemble du flux. Il se déroule en 3 étapes :

1. Chargement des données sources (CSV et PostgreSQL) vers STAGING
   (internement, appels à load_csv_to_staging.py, load_postgres_to_staging.py ou load_all_to_staging.py).
2. Transformation (DBT et DuckDB) vers ODS/DWH
   (exécution des modèles dbt : staging/, ods/, marts/dwh/).
3. Publication vers PostgreSQL (DWH et DATAMART)
   (export via export_dwh_to_postgres.py ou push_dwh_to_postgres.py, puis build_datamart_via_postgres.py).

Exécution type :

```bash
source .venv/bin/activate
python scripts/admin_pipeline.py
# Suivre le menu interactif, ou passer des options si prévues (--step 1, 2, 3)
```

Alternative manuelle (débogage) :

```bash
python scripts/load_all_to_staging.py
# puis transformations : dbt run ; tests : dbt test
# puis export/push vers PostgreSQL
```

## 5.8. Configuration et lancement d’Airflow (dans le venv)

Initialiser Airflow (exécuté depuis le venv) :

```bash
export AIRFLOW_HOME=$(pwd)/.airflow
airflow db init
airflow users create --username admin --firstname Admin --lastname User --role Admin --email admin@example.com --password admin
```

Placez votre DAG (par exemple dags/daily_etl.py) qui appelle admin_pipeline.py (Étapes 1→3). Lancer webserver et scheduler :

```bash
airflow webserver -p 8080 &
airflow scheduler &
```

Accéder à l’UI : [http://localhost:8080](http://localhost:8080) puis déclencher le DAG daily_etl.

## 5.9. Vérifications fonctionnelles

- DBT : exécuter dbt run puis dbt test (vérifier l’absence d’erreurs dans dbt/target/).
- PostgreSQL (DWH) : vérifier la présence des tables via une requête :

```sql
SELECT schemaname, tablename FROM pg_tables WHERE schemaname IN ('dwh','datamart') ORDER BY 1,2;
```

- Datamarts : valider que les vues matérialisées (ex. dm_consultations_analysis) sont alimentées et requêtables.
- Power BI : tester la connexion directe au schéma datamart.

## 5.10. Dépannage

- Ports déjà utilisés : modifier SOURCE_POSTGRES_PORT et DWH_POSTGRES_PORT dans .env et docker-compose.yml, puis relancer docker compose up -d.
- Variables non chargées : exécuter export $(grep -v '^#' .env | xargs) avant les scripts.
- Paquets Python : vérifier l’activation du venv, puis pip install -r requirements.txt.
- Accès Postgres : tester psql avec les paramètres .env et vérifier les logs Docker (docker logs pg_dwh).
- Airflow : si l’UI ne démarre pas, purger la méta-base avec airflow db reset (supprime l’historique), puis relancer.

À ce stade, l’environnement est opérationnel : le pipeline peut être exécuté à la demande via admin_pipeline.py ou planifié quotidiennement dans Airflow.
