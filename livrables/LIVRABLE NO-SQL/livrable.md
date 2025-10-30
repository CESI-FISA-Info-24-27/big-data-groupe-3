# 1. Introduction et objectifs

Le secteur de la santé vit aujourd’hui une transformation numérique sans précédent. Chaque jour, les hôpitaux produisent des quantités considérables de données médicales et administratives : dossiers patients, résultats d’examens, suivis d’hospitalisation, enquêtes de satisfaction, statistiques internes… Ces informations représentent une véritable richesse, mais restent souvent dispersées dans différents systèmes, rendant leur exploitation difficile.

Face à ce constat, le groupe CHU a souhaité mettre en place un entrepôt de données moderne et évolutif capable de centraliser, structurer et valoriser ces informations. L’objectif est simple : offrir aux équipes médicales et aux responsables d’établissement une vision claire et fiable de leur activité pour appuyer la prise de décision et améliorer la qualité des soins.

Ce livrable détaille l’ensemble des choix techniques réalisés pour concevoir cette solution :

- une architecture en cinq couches logiques ;

- les technologies sélectionnées et leurs justifications ;

- la structure des différentes zones de données et le fonctionnement du pipeline ELT ;

- les scripts Python et DBT utilisés à chaque étape du traitement.

Plus qu’une simple documentation, ce livrable constitue un guide technique complet, destiné à toute équipe amenée à déployer, maintenir ou faire évoluer la solution. Il met l’accent sur la clarté, la reproductibilité et la pérennité du système.

En s’appuyant sur des outils open-source et des standards reconnus, cette architecture répond aux exigences du domaine médical : performance, sécurité, conformité réglementaire et respect du RGPD.

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

## 3.1. DuckDB

DuckDB a été retenu comme moteur analytique intermédiaire en raison de sa **légèreté**, de ses **performances élevées** et de son **intégration native** avec Python et les formats colonnes tels que Parquet. Il permet d’exécuter des requêtes SQL complexes directement sur des fichiers locaux sans nécessiter d’infrastructure serveur, ce qui réduit considérablement les coûts de maintenance.

## 3.2. DBT (Data Build Tool)

DBT structure les transformations en SQL de manière modulaire et versionnée. Il introduit une **logique de dépendance entre modèles**, une **documentation automatique** et des **tests de validation intégrés**. Cette approche garantit la qualité du code et la reproductibilité des transformations dans tous les environnements (développement, test, production).

## 3.3. Apache Airflow

Airflow constitue le cœur de l’orchestration. Il permet de planifier et de superviser les tâches, de gérer les dépendances et de relancer automatiquement les traitements en cas d’échec. Grâce à son interface web, les équipes peuvent suivre en temps réel l’état du pipeline et accéder aux logs d’exécution pour le diagnostic. L’approche “configuration as code” d’Airflow favorise le versionnement et la transparence.

## 3.4. PostgreSQL

PostgreSQL héberge le Data Warehouse et les datamarts. C’est un SGBD relationnel open-source reconnu pour sa robustesse et sa conformité ACID. Ses fonctionnalités avancées (partitionnement, indexation BRIN et B-tree, vues matérialisées) en font un choix idéal pour l’analytique décisionnelle. La gestion fine des privilèges et la journalisation des connexions renforcent la sécurité du système.

## 3.5. Parquet

Le format **Parquet** a été choisi pour le stockage intermédiaire des données en raison de ses excellentes performances d’accès et de compression. Son organisation en colonnes réduit significativement les temps de lecture et la taille des fichiers, tout en permettant la lecture sélective des colonnes pertinentes. Ce format s’intègre parfaitement dans les pipelines utilisant DuckDB et DBT.

## 3.6. Power BI

Power BI assure la visualisation et la restitution des données. Son intégration directe avec PostgreSQL permet d’exploiter les datamarts sans couches intermédiaires. Les vues matérialisées garantissent des **temps de réponse inférieurs à la seconde**, même sur des volumes importants. La mise en place du **Row-Level Security (RLS)** permet de restreindre dynamiquement les accès en fonction du profil utilisateur.

## 3.7. Comparatif avec la stack Big Data classique

Le cahier des charges initial proposait une architecture basée sur **Talend, Hadoop et Hive**. Après analyse, cette solution a été jugée surdimensionnée pour les besoins du CHU. Notre approche modernisée, fondée sur DuckDB, DBT et PostgreSQL, offre :

- une **réduction drastique de la complexité opérationnelle** ;
- des **performances équivalentes voire supérieures** sur les volumétries concernées ;
- une **installation simplifiée** sans infrastructure distribuée ;
- et un **coût d’exploitation nul**, grâce à l’utilisation exclusive d’outils open-source.

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

Cette section décrit la procédure pour **déployer le projet depuis zéro** en s’appuyant sur le `docker-compose.yml` fourni (PostgreSQL DWH + base Airflow + Airflow webserver/scheduler). Les **traitements ETL** (DuckDB + DBT + scripts Python) s’exécutent dans un **environnement virtuel Python (venv)** sur la machine hôte.

---

## 5.1. Prérequis

* **OS** : Linux / macOS / WSL2 recommandé
* **Docker & Docker Compose** ≥ 2.x
* **Python** ≥ 3.11 avec `venv`
* **Git** ≥ 2.3
* Ports libres : **5433** (PostgreSQL DWH), **5434** (PostgreSQL Airflow), **8080** (Airflow UI)

---

## 5.2. Clonage du dépôt & création des répertoires

```bash
# HTTPS (recommandé)
git clone https://github.com/CESI-FISA-Info-24-27/big-data-groupe-3.git
# ou en SSH
# git@github.com:24-27/big-data-groupe-3.git

cd big-data-groupe-3
# (optionnel) se placer sur la branche de travail
# git checkout labo

# Dossiers de données locaux
mkdir -p data/csv data/duckdb
```

Arborescence principale déjà fournie :

* `dags/` : DAGs Airflow pour l’orchestration
* `dbt/` : modèles et tests DBT (staging, ods, dwh, datamart)
* `scripts/` : scripts Python d’ingestion/transfert/administration
* `scripts/init/` : SQL d’initialisation des schémas (exécutés au démarrage du DWH)
* `docs/`, `livrables/` : documentation
* `docker-compose.yml` : stack Docker (PostgreSQL + Airflow)

---

## 5.3. Variables d’environnement

Créer un fichier **`.env`** à la racine :

```dotenv
# Source Postgres (optionnelle)
SOURCE_POSTGRES_HOST=localhost
SOURCE_POSTGRES_PORT=5432
SOURCE_POSTGRES_DB=chu_source
SOURCE_POSTGRES_USER=chu_user
SOURCE_POSTGRES_PASSWORD=changeme

# DWH Postgres (dans Docker)
DWH_POSTGRES_HOST=postgres-dwh
DWH_POSTGRES_PORT=5432
DWH_POSTGRES_DB=healthcare_dwh
DWH_POSTGRES_USER=admin
DWH_POSTGRES_PASSWORD=admin

# Chemins locaux
DUCKDB_PATH=data/duckdb/staging.duckdb
CSV_PATH=data/csv
```

---

## 5.4. Démarrage de l’infrastructure Docker

Le `docker-compose.yml` lance :

* **postgres-dwh** (PostgreSQL 15) exposé sur **localhost:5433**
* **postgres-airflow** (PostgreSQL 15) exposé sur **localhost:5434**
* **airflow-webserver** (port **8080**) et **airflow-scheduler**
* **airflow-init** (initialisation automatique)

```bash
docker compose up -d
```

Accès à l’UI Airflow : **[http://localhost:8080](http://localhost:8080)** (utilisateur : `admin`, mot de passe : `admin`).

Vérification du DWH :

```bash
PGPASSWORD=admin psql -h localhost -p 5433 -U admin -d healthcare_dwh -c "SELECT version();"
```

---

## 5.5. Environnement Python (ETL local)

Créer le venv et installer les dépendances ETL :

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip

# Dépendances principales (alignées avec les scripts fournis)
pip install duckdb dbt-core dbt-duckdb pandas pyarrow psycopg2-binary python-dotenv
```

> Si vous préférez, utilisez le fichier `requirements.txt` :
>
> ```bash
> pip install -r requirements.txt
> ```

---

## 5.6. Initialisation automatique des schémas DWH

Au premier démarrage, Docker charge les SQL de `scripts/init/` via le volume `./scripts/init:/docker-entrypoint-initdb.d` et crée :

* `create_users_db.sql` (rôles & utilisateurs),
* `init_staging.sql`, `init_ods.sql`, `init_dwh.sql`, `init_datamart.sql` (schémas & tables).

Relance manuelle possible :

```bash
docker exec -it chu-dwh \
  psql -U admin -d healthcare_dwh \
  -f /docker-entrypoint-initdb.d/init_dwh.sql
```

---

## 5.7. Lancer le pipeline avec `admin_pipeline.py`

`scripts/admin_pipeline.py` orchestre les **3 étapes cibles** (mode recommandé) :

1. **Chargement → STAGING (DuckDB)**
   Exécute `load_csv_to_staging.py` + `load_postgres_to_staging.py` (ou `load_all_to_staging.py`).
2. **Transformations → ODS & DWH (DuckDB via DBT)**
   Par défaut, la commande intégrée est `dbt run` **qui construit tous les modèles** (`staging/`, `ods/`, `dwh/` et `marts/datamart/`).
3. **Publication → PostgreSQL (DWH **+ datamarts**) **
   Exécute `push_dwh_to_postgres.py` (mode **batch** avec `COPY`) et pousse les tables `dwh.*` **et** les `dm_*` si elles existent dans DuckDB.

Exécution standard (interactive) :

```bash
source .venv/bin/activate
python scripts/admin_pipeline.py
```

Exécution automatique des étapes **1–3** :

```bash
python scripts/admin_pipeline.py --step 1,2,3
```

---

## 5.8. Orchestration planifiée avec Airflow (Docker)

Le DAG `dags/daily_etl.py` déclenche `admin_pipeline.py` à l’horaire défini.

```bash
docker compose start airflow-webserver airflow-scheduler  # si non démarrés
# Ouvrir l’UI : http://localhost:8080 (admin / admin) et activer le DAG `daily_etl`
```

---

## 5.9. Vérifications rapides

* **DBT**

  ```bash
  cd dbt && dbt run && dbt test
  ```
* **PostgreSQL – DWH**

  ```bash
  docker exec -it chu-dwh psql -U admin -d healthcare_dwh -c "\dt dwh.*"
  ```
* **Datamarts**

  * Si vous avez poussé les `dm_*` (mode étapes 1–3) : vérifiez `\dt datamart.*`.
  * Si vous avez choisi la variante « DM direct PostgreSQL » (étape 4) : exécutez ensuite `python scripts/fix_datamart_schema.py` puis vérifiez `\d+ datamart.dm_consultations_agregees`.
* **Power BI**

  * Source : PostgreSQL `localhost:5433`, schéma `datamart` (RLS prêt).

---

## 5.10. Dépannage

| Problème                                   | Cause probable                                    | Solution                                                                                                                                    |
| ------------------------------------------ | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Airflow ne démarre pas                     | Services déjà actifs / init incomplet             | `docker compose down -v && docker compose up -d` ; vérifier les logs `docker logs chu-airflow-webserver`                                    |
| Ports 5433/5434 occupés                    | Autre Postgres local en cours                     | Modifier les ports dans `docker-compose.yml` puis relancer                                                                                  |
| Erreur `psycopg2` manquant                 | Dépendances venv incomplètes                      | `pip install psycopg2-binary`                                                                                                               |
| Échec de connexion DWH                     | Conteneur `chu-dwh` non démarré                   | `docker start chu-dwh` puis retester la connexion `psql`                                                                                    |
| Échec `push_dwh_to_postgres.py` sur `dm_*` | Les modèles datamart DBT n’ont pas été construits | Soit exécuter `dbt run` (incluant `marts/datamart`), soit commenter les lignes `dm_*` dans `TABLES_ORDRE` et construire le DM via l’étape 4 |
| Schémas DM (types trop courts)             | Colonnes `sexe`, `tranche_age`, etc.              | `python scripts/fix_datamart_schema.py`                                                                                                     |
