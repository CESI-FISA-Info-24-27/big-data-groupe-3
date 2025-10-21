# ⚡ Démarrage Rapide - Airflow

## 🎯 En 3 Minutes Chrono

### Étape 1 : Démarrer Docker (30 secondes)

```bash
docker-compose up -d
```

### Étape 2 : Accéder à Airflow (10 secondes)

```
URL: http://localhost:8080
User: admin
Password: admin
```

### Étape 3 : Lancer le Pipeline (1 clic)

1. Trouver le DAG `chu_dwh_pipeline`
2. Activer le toggle (OFF → ON)
3. Cliquer sur ▶️ "Trigger DAG"
4. ✅ C'est parti ! (~15 minutes)

---

## 📊 Services Disponibles

| Service | URL | Credentials |
|---------|-----|-------------|
| 🌐 **Airflow UI** | http://localhost:8080 | admin / admin |
| 🐘 **PostgreSQL DWH** | localhost:5433 | admin / admin |
| 🐘 **PostgreSQL Airflow** | localhost:5434 | airflow / airflow |

---

## 🔍 Vérifications

### ✅ Tout fonctionne ?

```bash
# Vérifier les services
docker-compose ps

# Attendu :
# ✅ chu-dwh                 Up (healthy)
# ✅ chu-airflow-db          Up (healthy)
# ✅ chu-airflow-webserver   Up (healthy)
# ✅ chu-airflow-scheduler   Up (healthy)
```

### 📝 Voir les Logs

```bash
# Logs Airflow Scheduler
docker-compose logs -f airflow-scheduler

# Logs PostgreSQL DWH
docker-compose logs -f postgres-dwh

# Tous les logs
docker-compose logs -f
```

---

## 🎯 Dans Airflow

### Vue Graph du DAG

```
chargement_donnees (parallèle)
├─ load_csv
└─ load_postgres
        │
        ↓
transformations_dbt (séquentiel)
├─ dbt_deps
├─ dbt_staging
├─ dbt_ods
└─ dbt_dwh
        │
        ↓
push_dwh_to_postgres
        │
        ↓
build_datamart_postgres
        │
        ↓
validation (parallèle)
├─ dbt_test
└─ test_postgres_extension
        │
        ↓
Notifications
```

**Durée totale** : ~15 minutes

---

## 🛠️ Commandes Essentielles

```bash
# ▶️ Démarrer
docker-compose up -d

# 📊 Statut
docker-compose ps

# ⏹️ Arrêter
docker-compose down

# 🔄 Redémarrer
docker-compose restart

# 🗑️ Tout nettoyer (⚠️ perte données)
docker-compose down -v
```

---

## ❓ Problèmes ?

### Le DAG n'apparaît pas

```bash
# Attendre 30 secondes et rafraîchir la page
# Ou vérifier les erreurs
docker-compose logs airflow-scheduler | grep ERROR
```

### Une tâche échoue

1. Cliquer sur la tâche 🔴
2. Cliquer sur "Log"
3. Lire l'erreur
4. Corriger
5. "Clear" pour relancer

---

## 🎉 C'est Tout !

Votre pipeline s'exécute maintenant automatiquement tous les jours à 2h du matin.

**Prochaine étape** : Connecter Power BI à PostgreSQL (localhost:5433)

📚 **Documentation complète** : [docs/GUIDE_AIRFLOW.md](docs/GUIDE_AIRFLOW.md)

---

**Équipe Big Data Groupe 3 - CESI 2025**

