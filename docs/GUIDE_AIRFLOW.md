# 🔄 Guide Apache Airflow - CHU DWH

## 📋 Vue d'Ensemble

Apache Airflow orchestre automatiquement le pipeline complet CHU Data Warehouse.

**Avantages** :
- ✅ **Automatisation complète** : Exécution quotidienne sans intervention
- ✅ **Monitoring visuel** : Interface web pour suivre les exécutions
- ✅ **Gestion des erreurs** : Retry automatique, alertes
- ✅ **Historique** : Logs de toutes les exécutions
- ✅ **Planification** : Schedule flexible (quotidien, hebdo, etc.)

---

## 🚀 Démarrage Rapide

### 1️⃣ Lancer Airflow

```bash
# Démarrer tous les services (PostgreSQL + Airflow)
docker-compose up -d

# Vérifier que tout est démarré
docker-compose ps

# Attendu :
# chu-dwh                 ... Up (healthy)
# chu-airflow-db          ... Up (healthy)
# chu-airflow-webserver   ... Up (healthy)
# chu-airflow-scheduler   ... Up (healthy)
```

### 2️⃣ Accéder à l'Interface Web

**URL** : http://localhost:8080

**Credentials** :
- 👤 Username : `admin`
- 🔒 Password : `admin`

### 3️⃣ Activer et Lancer le DAG

1. Dans l'interface, trouver le DAG `chu_dwh_pipeline`
2. Cliquer sur le toggle (OFF → ON) pour l'activer
3. Cliquer sur ▶️ "Trigger DAG" pour lancer manuellement
4. Observer l'exécution en temps réel

---

## 📊 Interface Airflow

### Vue Principale (DAGs)

```
┌─────────────────────────────────────────────────────────────┐
│  Apache Airflow                                    admin ▼  │
├─────────────────────────────────────────────────────────────┤
│  DAGs  │  Jobs  │  Admin  │                                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  🔍 Search DAGs...                                          │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ chu_dwh_pipeline                         ⚪ → 🟢  │    │
│  │ Pipeline complet CHU Data Warehouse                │    │
│  │                                                     │    │
│  │ Schedule: 0 2 * * * (Daily at 2am)                │    │
│  │ Last Run: 2025-10-21 02:00 - ✅ Success          │    │
│  │ Duration: 14m 32s                                  │    │
│  │                                                     │    │
│  │ [▶️ Trigger] [📊 Graph] [📅 Calendar] [📝 Code]   │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Vue Graph (Workflow)

```
┌─────────────────────────────────────────────────────────────┐
│  chu_dwh_pipeline - Graph View                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│       🟢 chargement_donnees                                 │
│       ├─ 🟢 load_csv                                        │
│       └─ 🟢 load_postgres                                   │
│              │                                               │
│              ↓                                               │
│       🟢 transformations_dbt                                │
│       ├─ 🟢 dbt_deps                                        │
│       ├─ 🟢 dbt_staging                                     │
│       ├─ 🟢 dbt_ods                                         │
│       └─ 🟢 dbt_dwh                                         │
│              │                                               │
│              ↓                                               │
│       🟢 push_dwh_to_postgres                               │
│              │                                               │
│              ↓                                               │
│       🟢 build_datamart_postgres                            │
│              │                                               │
│              ↓                                               │
│       🟢 validation                                         │
│       ├─ 🟢 dbt_test                                        │
│       └─ 🟢 test_postgres_extension                         │
│              │                                               │
│              ↓                                               │
│       🟢 notify_success                                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘

Légende:
🟢 Success   🟡 Running   🔴 Failed   ⚪ Not Run
```

---

## 📋 DAG Configuration

### Définition du DAG

```python
dag = DAG(
    'chu_dwh_pipeline',
    schedule_interval='0 2 * * *',  # Tous les jours à 2h du matin
    start_date=datetime(2025, 10, 21),
    catchup=False,                   # Ne pas rattraper exécutions passées
    max_active_runs=1,               # Une seule exécution à la fois
    tags=['chu', 'dwh', 'etl', 'healthcare'],
)
```

### Schedule (Cron)

| Expression | Signification |
|------------|---------------|
| `0 2 * * *` | Tous les jours à 2h du matin (par défaut) |
| `0 */6 * * *` | Toutes les 6 heures |
| `0 0 * * 0` | Tous les dimanches à minuit |
| `0 1 1 * *` | Le 1er de chaque mois à 1h |
| `None` | Déclenchement manuel uniquement |

**Modifier le schedule** : Éditer `dags/chu_dwh_pipeline.py` ligne 61

---

## 🔄 Tâches du Pipeline

### 1️⃣ Chargement Données (Groupe de Tâches)

**Tâches** :
- `load_csv` : Charger fichiers CSV dans DuckDB RAW
- `load_postgres` : Charger tables PostgreSQL dans DuckDB RAW

**Exécution** : Parallèle (les 2 tâches en même temps)

**Durée** : ~3 minutes

**Logs** :
```bash
docker-compose logs airflow-scheduler | grep load_csv
```

### 2️⃣ Transformations dbt (Groupe de Tâches)

**Tâches** :
- `dbt_deps` : Installer packages dbt
- `dbt_staging` : Nettoyage (16 modèles)
- `dbt_ods` : Intégration (9 modèles)
- `dbt_dwh` : Modélisation (13 modèles)

**Exécution** : Séquentielle (ordre des dépendances)

**Durée** : ~1 minute

### 3️⃣ Export DWH

**Tâche** : `push_dwh_to_postgres`

**Action** : Pousser le DWH de DuckDB vers PostgreSQL

**Durée** : ~3 minutes

### 4️⃣ Création Datamart

**Tâche** : `build_datamart_postgres`

**Action** : Créer datamart directement dans PostgreSQL (optimisé)

**Durée** : ~8 minutes

### 5️⃣ Validation (Groupe de Tâches)

**Tâches** :
- `dbt_test` : Tests de qualité dbt
- `test_postgres_extension` : Tests extension Postgres

**Exécution** : Parallèle

**Durée** : ~1 minute

### 6️⃣ Notifications

**Tâches** :
- `notify_success` : Si tout réussit
- `notify_failure` : Si une tâche échoue

---

## 🎛️ Utilisation de l'Interface

### Déclencher Manuellement

1. Aller sur http://localhost:8080
2. Cliquer sur le DAG `chu_dwh_pipeline`
3. Cliquer sur ▶️ "Trigger DAG" en haut à droite
4. Confirmer
5. Observer l'exécution en temps réel

### Voir les Logs d'une Tâche

1. Cliquer sur le DAG
2. Cliquer sur une tâche (carré coloré)
3. Cliquer sur "Log" dans le menu contextuel
4. Les logs s'affichent en temps réel

### Relancer une Tâche Échouée

1. Cliquer sur la tâche en échec (🔴)
2. Cliquer sur "Clear"
3. Confirmer
4. La tâche et ses descendants se relancent

### Voir l'Historique

1. Aller dans l'onglet "Browse" → "DAG Runs"
2. Voir toutes les exécutions passées
3. Cliquer sur une exécution pour voir les détails

---

## 🔧 Configuration Avancée

### Variables d'Environnement

Modifier dans `docker-compose.yml` :

```yaml
environment:
  # PostgreSQL DWH
  DWH_POSTGRES_HOST: postgres-dwh
  DWH_POSTGRES_PORT: 5432
  DWH_POSTGRES_DB: healthcare_dwh
  DWH_POSTGRES_USER: admin
  DWH_POSTGRES_PASSWORD: admin  # ⚠️ Changer en production
  
  # PostgreSQL Source (optionnel)
  SOURCE_POSTGRES_HOST: ${SOURCE_POSTGRES_HOST:-localhost}
  SOURCE_POSTGRES_PORT: ${SOURCE_POSTGRES_PORT:-5432}
  SOURCE_POSTGRES_DB: ${SOURCE_POSTGRES_DB:-chu_operationnel}
```

### Modifier le Schedule

Éditer `dags/chu_dwh_pipeline.py` :

```python
dag = DAG(
    'chu_dwh_pipeline',
    schedule_interval='0 2 * * *',  # ← Modifier ici
    ...
)
```

**Exemples** :
- `'0 2 * * *'` : Tous les jours à 2h
- `'0 */6 * * *'` : Toutes les 6 heures
- `'0 0 * * 0'` : Tous les dimanches à minuit
- `None` : Déclenchement manuel uniquement

### Ajouter des Alertes Email

```python
default_args = {
    'owner': 'chu-dwh',
    'email': ['admin@chu.fr'],           # ← Ajouter email
    'email_on_failure': True,            # ← Activer
    'email_on_retry': True,
    ...
}
```

**Configuration SMTP** (dans `docker-compose.yml`) :
```yaml
environment:
  AIRFLOW__SMTP__SMTP_HOST: smtp.gmail.com
  AIRFLOW__SMTP__SMTP_PORT: 587
  AIRFLOW__SMTP__SMTP_USER: votre.email@gmail.com
  AIRFLOW__SMTP__SMTP_PASSWORD: votre_mot_de_passe
  AIRFLOW__SMTP__SMTP_MAIL_FROM: airflow@chu-dwh.local
```

---

## 📊 Monitoring

### Métriques Airflow

**Dashboard** : http://localhost:8080/home

Métriques disponibles :
- ✅ **DAG Success Rate** : Taux de réussite
- ⏱️ **Duration** : Temps d'exécution moyen
- 📅 **Last Run** : Dernière exécution
- 🔢 **Task Count** : Nombre de tâches

### Logs Docker

```bash
# Logs Airflow Scheduler
docker-compose logs -f airflow-scheduler

# Logs Airflow Webserver
docker-compose logs -f airflow-webserver

# Logs PostgreSQL DWH
docker-compose logs -f postgres-dwh

# Tous les logs
docker-compose logs -f
```

### Ressources Système

```bash
# Voir l'utilisation CPU/RAM
docker stats

# Espace disque
docker system df
```

---

## 🐛 Dépannage

### ❌ Airflow ne démarre pas

```bash
# Vérifier les logs
docker-compose logs airflow-init

# Recréer complètement
docker-compose down -v
docker-compose up -d
```

### ❌ DAG n'apparaît pas

```bash
# Vérifier le fichier DAG
docker-compose exec airflow-scheduler ls -la /opt/airflow/dags/

# Vérifier les erreurs Python
docker-compose exec airflow-scheduler airflow dags list-import-errors

# Relancer le scheduler
docker-compose restart airflow-scheduler
```

### ❌ Tâche échoue

1. **Voir les logs** dans l'interface Airflow
2. **Identifier l'erreur** (connexion, données, code)
3. **Corriger** le problème
4. **Relancer** avec "Clear" dans l'interface

**Erreurs fréquentes** :

| Erreur | Cause | Solution |
|--------|-------|----------|
| `Connection refused` | PostgreSQL DWH pas démarré | `docker-compose up -d postgres-dwh` |
| `File not found` | Volume Docker mal monté | Vérifier `docker-compose.yml` volumes |
| `Permission denied` | Problème UID/GID | Définir `AIRFLOW_UID` dans `.env` |
| `ModuleNotFoundError` | Package Python manquant | Ajouter dans `_PIP_ADDITIONAL_REQUIREMENTS` |

### ❌ Performance lente

```bash
# Augmenter les ressources Docker
# Docker Desktop → Settings → Resources
# - CPUs: 4+
# - Memory: 8 GB+
# - Swap: 2 GB+

# Vérifier l'utilisation
docker stats
```

---

## 📅 Planification

### Exemples de Schedule

```python
# Quotidien
schedule_interval='0 2 * * *'        # Tous les jours à 2h
schedule_interval='@daily'           # Équivalent

# Hebdomadaire
schedule_interval='0 2 * * 0'        # Tous les dimanches à 2h
schedule_interval='@weekly'          # Équivalent

# Mensuel
schedule_interval='0 2 1 * *'        # Le 1er de chaque mois à 2h
schedule_interval='@monthly'         # Équivalent

# Personnalisé
schedule_interval='0 */4 * * *'      # Toutes les 4 heures
schedule_interval='0 8,20 * * *'     # À 8h et 20h
schedule_interval='0 2 * * 1-5'      # Du lundi au vendredi à 2h
```

### Déclencher Manuellement

```bash
# Via CLI dans le container
docker-compose exec airflow-scheduler \
  airflow dags trigger chu_dwh_pipeline

# Via API (si activée)
curl -X POST \
  http://localhost:8080/api/v1/dags/chu_dwh_pipeline/dagRuns \
  -H "Content-Type: application/json" \
  -u "admin:admin"
```

---

## 🔔 Alertes et Notifications

### Configuration Email

```python
# Dans dags/chu_dwh_pipeline.py
default_args = {
    'email': ['admin@chu.fr', 'ops@chu.fr'],
    'email_on_failure': True,
    'email_on_retry': True,
    'email_on_success': False,  # Optionnel
}
```

### Notifications Slack (Optionnel)

```python
from airflow.providers.slack.operators.slack_webhook import SlackWebhookOperator

notify_slack = SlackWebhookOperator(
    task_id='notify_slack',
    slack_webhook_conn_id='slack_webhook',
    message='✅ Pipeline CHU DWH terminé avec succès !',
    channel='#data-alerts',
)
```

---

## 📈 Optimisations

### Parallélisation

**Actuel** : Les tâches `load_csv` et `load_postgres` s'exécutent en parallèle

**Augmenter** :
```python
# Dans docker-compose.yml
AIRFLOW__CORE__PARALLELISM: 32            # Max tâches parallèles
AIRFLOW__CORE__DAG_CONCURRENCY: 16        # Max par DAG
AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG: 1 # Exécutions simultanées
```

### Pools (Limiter Ressources)

```bash
# Créer un pool dans Airflow UI
# Admin → Pools → + Add Pool

# Name: postgres_pool
# Slots: 2  (max 2 tâches PostgreSQL simultanées)

# Utiliser dans le DAG
push_dwh = BashOperator(
    task_id='push_dwh',
    pool='postgres_pool',
    ...
)
```

---

## 🔍 Monitoring Avancé

### Métriques Custom

```python
from airflow.metrics import statsd

# Dans une tâche Python
def mon_traitement(**context):
    statsd.incr('chu_dwh.rows_processed', value=1000000)
    statsd.timing('chu_dwh.duration', duration_ms)
```

### Logs Structurés

```python
import logging
logger = logging.getLogger(__name__)

def ma_tache(**context):
    logger.info("Début du traitement")
    logger.info(f"Lignes traitées: {row_count}")
    logger.warning("Attention: table vide")
    logger.error("Erreur de connexion")
```

---

## 📚 Commandes Utiles

### Gestion des Services

```bash
# ▶️ Démarrer
docker-compose up -d

# 📊 Statut
docker-compose ps

# 🔄 Redémarrer un service
docker-compose restart airflow-scheduler

# 📝 Logs
docker-compose logs -f airflow-scheduler

# ⏹️ Arrêter
docker-compose stop

# 🗑️ Supprimer (conserve volumes)
docker-compose down

# 💣 Supprimer tout (⚠️ perte de données)
docker-compose down -v
```

### Airflow CLI

```bash
# Liste des DAGs
docker-compose exec airflow-scheduler airflow dags list

# Détails d'un DAG
docker-compose exec airflow-scheduler \
  airflow dags show chu_dwh_pipeline

# Tester un DAG (dry-run)
docker-compose exec airflow-scheduler \
  airflow dags test chu_dwh_pipeline 2025-10-21

# Lister les exécutions
docker-compose exec airflow-scheduler \
  airflow dags list-runs -d chu_dwh_pipeline

# Créer un utilisateur
docker-compose exec airflow-webserver \
  airflow users create \
    --username john \
    --password secret \
    --firstname John \
    --lastname Doe \
    --role Admin \
    --email john@chu.fr
```

---

## 🎯 Bonnes Pratiques

### ✅ À Faire

- ✅ **Activer DAG** uniquement quand prêt
- ✅ **Tester localement** avant de déployer
- ✅ **Vérifier les logs** après chaque exécution
- ✅ **Documenter** les changements dans le DAG
- ✅ **Utiliser des pools** pour limiter ressources
- ✅ **Monitorer** les durées d'exécution
- ✅ **Configurer alertes** pour échecs

### ❌ À Éviter

- ❌ **Plusieurs DAG actifs** en même temps (risque de conflits)
- ❌ **Modifier un DAG** pendant son exécution
- ❌ **Catchup=True** (peut lancer des centaines d'exécutions)
- ❌ **Pas de retry** sur tâches critiques
- ❌ **Timeout trop court** (pipeline peut durer 15+ min)

---

## 🔐 Sécurité

### Credentials

**⚠️ IMPORTANT** : Les credentials par défaut sont à usage de développement uniquement !

**En production** :
```bash
# Générer des mots de passe forts
openssl rand -base64 32

# Utiliser des secrets Docker
# Ou variables d'environnement sécurisées
```

### Accès PostgreSQL

**Depuis l'extérieur** :
```bash
psql -h localhost -p 5433 -U admin -d healthcare_dwh
# Password: admin
```

**Depuis un container** :
```bash
docker-compose exec postgres-dwh psql -U admin -d healthcare_dwh
```

---

## 📊 Cas d'Usage

### Rafraîchissement Quotidien

**Automatique** : Airflow exécute tous les jours à 2h

**Manuel** :
```bash
# Via interface Airflow
# Trigger DAG → chu_dwh_pipeline

# Via CLI
docker-compose exec airflow-scheduler \
  airflow dags trigger chu_dwh_pipeline
```

### Rafraîchissement Partiel

Si seul le datamart doit être recréé :

**Option 1** : Modifier le DAG temporairement
```python
# Commenter les tâches non nécessaires
# chargement >> transformations >> push_dwh >> build_datamart
```

**Option 2** : Exécuter hors Airflow
```bash
python scripts/build_datamart_via_postgres.py
```

### Backfill (Rattrapage)

```bash
# Relancer pour une période passée
docker-compose exec airflow-scheduler \
  airflow dags backfill \
    -s 2025-10-01 \
    -e 2025-10-10 \
    chu_dwh_pipeline
```

---

## 📚 Ressources

### Documentation Officielle

- [Apache Airflow](https://airflow.apache.org/docs/)
- [DuckDB](https://duckdb.org/docs/)
- [dbt](https://docs.getdbt.com/)
- [PostgreSQL](https://www.postgresql.org/docs/)

### Documentation Projet

- 📘 [Index des Transformations](docs/INDEX_TRANSFORMATIONS.md)
- 📕 [Dictionnaire de Données](docs/DICTIONNAIRE_DONNEES_DWH.md)
- 📗 [Guide dbt](dbt/README.md)

### Communauté

- [Airflow Slack](https://apache-airflow.slack.com/)
- [dbt Community](https://www.getdbt.com/community/)
- [DuckDB Discord](https://discord.duckdb.org/)

---

## 🎓 FAQ

<details>
<summary><strong>Comment changer le mot de passe admin Airflow ?</strong></summary>

```bash
# Modifier dans docker-compose.yml
environment:
  _AIRFLOW_WWW_USER_PASSWORD: nouveau_mot_de_passe

# Recréer
docker-compose down
docker-compose up -d airflow-init
docker-compose up -d
```

</details>

<details>
<summary><strong>Comment désactiver un DAG temporairement ?</strong></summary>

1. Dans l'interface Airflow
2. Cliquer sur le toggle du DAG (🟢 → ⚪)
3. Le DAG ne s'exécutera plus automatiquement

</details>

<details>
<summary><strong>Comment voir les tâches en échec ?</strong></summary>

1. Aller dans "Browse" → "Task Instances"
2. Filtrer par "State: Failed"
3. Voir les détails et logs de chaque tâche

</details>

<details>
<summary><strong>Peut-on exécuter le pipeline sans Airflow ?</strong></summary>

Oui ! Utiliser le script d'administration :

```bash
python scripts/admin_pipeline.py --full
```

</details>

<details>
<summary><strong>Comment sauvegarder les données PostgreSQL ?</strong></summary>

```bash
# Backup
docker-compose exec postgres-dwh \
  pg_dump -U admin healthcare_dwh > backup.sql

# Restore
docker-compose exec -T postgres-dwh \
  psql -U admin healthcare_dwh < backup.sql
```

</details>

---

<div align="center">

## ✨ Prêt pour Production

**Version** : 3.0  
**Dernière mise à jour** : 2025-10-21

🚀 **Pipeline Optimisé** • 📚 **Documentation Complète** • 🤖 **Orchestration Automatisée**

[⬆️ Retour en haut](#-chu-data-warehouse)

---

Made with ❤️ by Équipe Big Data Groupe 3 - CESI 2025

</div>

