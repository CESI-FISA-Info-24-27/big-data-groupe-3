<div align="center">

# 🚀 Commencez Ici !

### Guide de Démarrage - CHU Data Warehouse

**Nouveau sur le projet ?** Ce guide vous orientera.

---

</div>

## 🎯 Selon Votre Profil

### 👨‍💼 Chef de Projet / Product Owner

**Vous voulez** : Vue d'ensemble et métriques

**À lire** (20 min) :
1. ✅ [README.md](README.md) - Vue d'ensemble
2. ✅ [docs/DICTIONNAIRE_DONNEES_DWH.md](docs/DICTIONNAIRE_DONNEES_DWH.md) - Données disponibles

**À faire** :
```bash
# Démarrer et voir Airflow
docker-compose up -d
# Ouvrir: http://localhost:8080 (admin/admin)
```

---

### 👨‍💻 Développeur / Data Engineer

**Vous voulez** : Comprendre et modifier le code

**À lire** (2-3h) :
1. ✅ [README.md](README.md)
2. ✅ [docs/INDEX_TRANSFORMATIONS.md](docs/INDEX_TRANSFORMATIONS.md) ⭐ Point d'entrée
3. ✅ Tous les guides de transformation dans l'ordre :
   - [CHARGEMENT_SOURCES_TO_RAW.md](docs/CHARGEMENT_SOURCES_TO_RAW.md)
   - [TRANSFORMATIONS_RAW_TO_STAGING.md](docs/TRANSFORMATIONS_RAW_TO_STAGING.md)
   - [TRANSFORMATIONS_STAGING_TO_ODS.md](docs/TRANSFORMATIONS_STAGING_TO_ODS.md)
   - [TRANSFORMATIONS_ODS_TO_DWH.md](docs/TRANSFORMATIONS_ODS_TO_DWH.md)
   - [TRANSFORMATIONS_DWH_TO_DATAMART.md](docs/TRANSFORMATIONS_DWH_TO_DATAMART.md)

**À faire** :
```bash
# Tester localement
pip install -r requirements.txt
cd dbt && dbt deps && cd ..
python scripts/admin_pipeline.py --full
```

---

### 📊 Data Analyst / Analyste BI

**Vous voulez** : Requêter les données

**À lire** (1h) :
1. ✅ [docs/DICTIONNAIRE_DONNEES_DWH.md](docs/DICTIONNAIRE_DONNEES_DWH.md) ⭐ Tables et colonnes
2. ✅ [docs/TRANSFORMATIONS_DWH_TO_DATAMART.md](docs/TRANSFORMATIONS_DWH_TO_DATAMART.md) - Tables DATAMART

**À faire** :
```bash
# Se connecter à PostgreSQL
psql -h localhost -p 5433 -U admin -d healthcare_dwh

# Ou via Power BI
# Serveur: localhost:5433
# Base: healthcare_dwh
# Schéma: datamart
```

---

### 🔧 DevOps / Ops

**Vous voulez** : Déployer et monitorer

**À lire** (1h) :
1. ✅ [README.md](README.md)
2. ✅ [docs/GUIDE_AIRFLOW.md](docs/GUIDE_AIRFLOW.md) ⭐ Orchestration
3. ✅ [QUICK_START_AIRFLOW.md](QUICK_START_AIRFLOW.md) - Démarrage rapide

**À faire** :
```bash
# Déployer
docker-compose up -d

# Monitorer
docker-compose ps
docker-compose logs -f

# Airflow UI
http://localhost:8080
```

---

## 🎯 Par Objectif

### 🚀 Je veux juste démarrer rapidement

1. **Avec Docker** (recommandé) :
   ```bash
   docker-compose up -d
   # → http://localhost:8080
   ```

2. **Sans Docker** :
   ```bash
   pip install -r requirements.txt
   python scripts/admin_pipeline.py --full
   ```

**Temps** : 5 minutes de setup, 15 minutes d'exécution

---

### 📚 Je veux comprendre comment ça marche

**Parcours d'apprentissage** :

1. **Débutant** (2h)
   - Lire [INDEX_TRANSFORMATIONS.md](docs/INDEX_TRANSFORMATIONS.md)
   - Comprendre le workflow global
   - Exécuter le pipeline

2. **Intermédiaire** (1 jour)
   - Lire tous les guides de transformation
   - Comprendre chaque étape
   - Modifier un modèle STAGING

3. **Avancé** (3 jours)
   - Lire toute la documentation
   - Créer nouveau modèle ODS
   - Implémenter nouveau KPI DATAMART

---

### 🔧 Je veux modifier quelque chose

**Selon ce que vous voulez changer** :

| Modification | Fichier | Documentation |
|--------------|---------|---------------|
| Ajouter une source | `scripts/load_*.py` | CHARGEMENT_SOURCES_TO_RAW.md |
| Nettoyer données | `dbt/models/staging/` | TRANSFORMATIONS_RAW_TO_STAGING.md |
| Jointure métier | `dbt/models/ods/` | TRANSFORMATIONS_STAGING_TO_ODS.md |
| Dimension/Fait | `dbt/models/marts/dwh/` | TRANSFORMATIONS_ODS_TO_DWH.md |
| Agrégation BI | `scripts/build_datamart_via_postgres.py` | TRANSFORMATIONS_DWH_TO_DATAMART.md |
| Orchestration | `dags/chu_dwh_pipeline.py` | GUIDE_AIRFLOW.md |

---

### 📊 Je veux analyser les données

**Power BI** :
1. Se connecter à PostgreSQL
   - Serveur : `localhost:5433`
   - Base : `healthcare_dwh`
   - Schéma : `datamart`
   - User : `admin` / Pass : `admin`

2. Utiliser les tables optimisées :
   - `dm_consultations_agregees` (45M lignes)
   - `dm_hospitalisations_agregees` (6K lignes)
   - `dm_analyse_territoriale` (30K lignes)

**SQL Direct** :
```bash
psql -h localhost -p 5433 -U admin -d healthcare_dwh

# Exemples dans DICTIONNAIRE_DONNEES_DWH.md
```

---

## 📚 Documentation Disponible

### 🎓 Par Ordre de Lecture

1. **[README.md](README.md)** - Vue d'ensemble du projet
2. **[docs/INDEX_TRANSFORMATIONS.md](docs/INDEX_TRANSFORMATIONS.md)** ⭐ Point d'entrée transformations
3. **[docs/DICTIONNAIRE_DONNEES_DWH.md](docs/DICTIONNAIRE_DONNEES_DWH.md)** - Référence tables
4. **[docs/GUIDE_AIRFLOW.md](docs/GUIDE_AIRFLOW.md)** - Orchestration
5. Les 5 guides de transformation (selon besoin)

### 🗺️ Navigation

```
START_HERE.md (vous êtes ici)
    │
    ├─ README.md (vue d'ensemble)
    │
    └─ docs/
       ├─ INDEX_TRANSFORMATIONS.md (point d'entrée) ⭐
       │  ├─ CHARGEMENT_SOURCES_TO_RAW.md (étape 0)
       │  ├─ TRANSFORMATIONS_RAW_TO_STAGING.md (étape 1)
       │  ├─ TRANSFORMATIONS_STAGING_TO_ODS.md (étape 2)
       │  ├─ TRANSFORMATIONS_ODS_TO_DWH.md (étape 3)
       │  └─ TRANSFORMATIONS_DWH_TO_DATAMART.md (étape 4)
       │
       ├─ DICTIONNAIRE_DONNEES_DWH.md (référence) ⭐
       └─ GUIDE_AIRFLOW.md (orchestration) ⭐
```

---

## ⚡ Commandes Ultra-Rapides

### 🐳 Avec Docker

```bash
# Démarrer
docker-compose up -d

# Monitorer
docker-compose logs -f airflow-scheduler

# Arrêter
docker-compose down
```

**Airflow** : http://localhost:8080 (admin/admin)

### 💻 Sans Docker

```bash
# Full build
python scripts/admin_pipeline.py --full

# Mode interactif
python scripts/admin_pipeline.py
```

---

## ❓ Questions Fréquentes

<details>
<summary><strong>C'est quoi la différence entre les couches ?</strong></summary>

- **RAW** : Données brutes (0 transformation)
- **STAGING** : Nettoyage simple (TRIM, CAST)
- **ODS** : Intégration (jointures, règles métier)
- **DWH** : Modèle dimensionnel (star schema, sk_*)
- **DATAMART** : Agrégations pré-calculées (Power BI)

Voir [INDEX_TRANSFORMATIONS.md](docs/INDEX_TRANSFORMATIONS.md)

</details>

<details>
<summary><strong>Comment je lance le pipeline ?</strong></summary>

**Avec Docker** :
```bash
docker-compose up -d
# → Airflow à http://localhost:8080
# → Activer DAG et déclencher
```

**Sans Docker** :
```bash
python scripts/admin_pipeline.py --full
```

</details>

<details>
<summary><strong>Où sont les données finales ?</strong></summary>

PostgreSQL sur `localhost:5433` :
- **Schéma dwh** : Dimensions + Faits (27M lignes)
- **Schéma datamart** : Tables agrégées (45M lignes)

Se connecter :
```bash
psql -h localhost -p 5433 -U admin -d healthcare_dwh
```

</details>

<details>
<summary><strong>Comment je vois la structure des tables ?</strong></summary>

Lire **[DICTIONNAIRE_DONNEES_DWH.md](docs/DICTIONNAIRE_DONNEES_DWH.md)**

Contient :
- ✅ Toutes les colonnes
- ✅ Types de données
- ✅ Contraintes et index
- ✅ Exemples de requêtes

</details>

<details>
<summary><strong>Le pipeline est trop long, normal ?</strong></summary>

**Temps normal** : ~15 minutes

Si plus long :
- Vérifier ressources Docker (CPU/RAM)
- Vérifier espace disque disponible
- Voir logs : `docker-compose logs -f`

</details>

---

## 🎉 Prêt à Commencer !

### Checklist de Démarrage

- [ ] Docker Desktop installé
- [ ] `docker-compose up -d` exécuté
- [ ] Services démarrés (vérifier avec `docker-compose ps`)
- [ ] Airflow accessible (http://localhost:8080)
- [ ] DAG `chu_dwh_pipeline` activé
- [ ] Premier run lancé
- [ ] README.md lu
- [ ] INDEX_TRANSFORMATIONS.md consulté

### Prochaines Étapes

1. ✅ Attendre fin du pipeline (~15 min)
2. ✅ Vérifier dans PostgreSQL que les tables existent
3. ✅ Connecter Power BI au datamart
4. ✅ Créer vos premiers dashboards
5. ✅ Partager avec l'équipe !

---

<div align="center">

## 📚 Besoin d'Aide ?

| Besoin | Document |
|--------|----------|
| 🎯 Vue d'ensemble | [README.md](README.md) |
| 📖 Transformations | [docs/INDEX_TRANSFORMATIONS.md](docs/INDEX_TRANSFORMATIONS.md) |
| 📚 Tables DWH | [docs/DICTIONNAIRE_DONNEES_DWH.md](docs/DICTIONNAIRE_DONNEES_DWH.md) |
| 🔄 Airflow | [docs/GUIDE_AIRFLOW.md](docs/GUIDE_AIRFLOW.md) |
| ⚡ Démarrage rapide | [QUICK_START_AIRFLOW.md](QUICK_START_AIRFLOW.md) |

---

**Équipe Big Data Groupe 3 - CESI 2025**

Made with ❤️ for Healthcare Data Analytics

</div>

