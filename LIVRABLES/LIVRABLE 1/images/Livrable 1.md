# Livrable 1 – Référentiel de données
**Projet : Cloud Healthcare Unit (CHU)**

---

## Introduction
Le secteur de la santé connaît aujourd'hui une profonde mutation numérique, portée par l'explosion du volume et de la diversité des données médicales générées quotidiennement. Ces données, issues notamment des systèmes de gestion hospitaliers, des plateformes FTP ou encore des bases administratives, représentent une source d'informations stratégiques encore largement sous-exploitée. 

Dans ce contexte, la capacité à collecter, intégrer, consolider et analyser ces données de manière fiable et sécurisée est devenue un levier majeur d'amélioration de la qualité des soins et de la performance organisationnelle.

Le groupe CHU (Cloud Healthcare Unit) souhaite ainsi amorcer une transformation digitale en mettant en place son propre entrepôt de données. 

L'objectif est de disposer d'une solution décisionnelle robuste et évolutive, capable d'agréger des sources hétérogènes pour permettre aux praticiens et aux responsables d'établissement d'accéder à des analyses fiables et exploitables. Ces analyses portent notamment sur le suivi des consultations, des hospitalisations, des diagnostics, des taux de satisfaction et des statistiques de mortalité au niveau national.

Le livrable 1 s'inscrit dans la première phase du projet. Il consiste à définir le référentiel de données qui servira de fondation à l'entrepôt décisionnel. 

Cette étape comprend :
- la modélisation conceptuelle adaptée aux besoins d'analyse,
- la justification des choix technologiques,
- la description de l'architecture cible,
- la définition des dimensions et faits décisionnels,
- la gestion des contextes techniques.

Une planification structurée sur quatre semaines accompagne ce livrable afin d'assurer une exécution coordonnée et progressive du projet.

---

## 1. Planification du projet – Diagramme de Gantt
Afin de structurer efficacement l'avancement du projet Cloud Healthcare Unit, une planification détaillée a été élaborée à l'aide d'un diagramme de Gantt sur quatre semaines. 
Elle permet de visualiser l'enchaînement logique des tâches, de clarifier les dépendances et d'assurer une répartition équilibrée du travail.

### Principaux livrables
**Livrable 1 – Référentiel de données**

Analyse des besoins, étude des sources, modélisation conceptuelle, conception du schéma décisionnel, mise en place des premiers flux ETL et validation.

**Livrable 2 – Modèle physique et optimisation**

Création des tables physiques, chargement et validation des données, tests de performance et optimisations (partitionnement, indexation, bucketing).

**Livrable 3 – Présentation et storytelling**

Restitution et valorisation des données : définition des indicateurs clés, création du tableau de bord, interprétation des résultats et préparation de la soutenance.
La planification suit une logique séquentielle tout en intégrant certaines tâches parallélisables (par exemple, étude des sources et modélisation). Des marges sont prévues pour absorber les ajustements nécessaires lors des validations et optimisations.

![Diagramme de Gantt](../../GANTT/BIG_DATA_GANTT.png)

---

## 2. Stack technologique et architecture cible
La stack initialement préconisée (Talend, Hadoop, Hive, Spark) correspond à une approche Big Data classique, mais elle présente plusieurs limites dans le contexte du projet :
- Complexité d'intégration et de déploiement, peu adaptée à un environnement pédagogique.
- Manque de souplesse pour des volumes structurés et semi-structurés de taille moyenne.
- Courbe d'apprentissage élevée pour des besoins couverts plus simplement par des outils modernes.
- Manque d'agilité pour mettre en place rapidement une architecture analytique modulaire.

### Stack adoptée
Nous avons opté pour une stack moderne et légère, structurée en cinq couches :

**Source de données**
Fichiers CSV/Excel, base PostgreSQL, fichiers plats FTP (satisfaction et décès).

**Ingestion**
Orchestration par Apache Airflow ; extraction en Python ; chargement dans DuckDB.

**Transformation**
Transformations avec DBT dans DuckDB, génération de fichiers Parquet, export vers PostgreSQL.

**Data Warehouse**
Modèle en constellation dans PostgreSQL avec dimensions partagées et datamarts.

**Visualisation**
Power BI pour la restitution, avec Row-Level Security (RLS) par service.

### Justification
Cette architecture est :
- simple et rapide à mettre en œuvre (outils légers et open source),
- performante pour des volumes moyens grâce à DuckDB et PostgreSQL,
- modulaire et évolutive, chaque couche étant indépendante,
- alignée avec les pratiques modernes (ELT, orchestration as code, transformations SQL déclaratives),
- adaptée au contexte du CHU et aux contraintes pédagogiques.

![Schéma Stack](<stack/Stack Technique.png>)

---

## 3. Modélisation conceptuelle des données (MCD)
*Section à compléter avec le diagramme et la description du modèle en étoile / constellation.*

![Etoile consultation](<etoiles/Etoile consultation.png>) 

![Etoile décès](<etoiles/Etoile deces.png>) 

![Etoile hospitalisation](<etoiles/Etoile hospitalisation.png>) 

![Etoile qualité soins](<etoiles/Etoile qualite soins.png>) 

![Etoile satisfaction](<etoiles/Etoiles satisfaction.png>)

![MLD constellation](mld/MLD.png)

---

## 4. Pré-requis : Dimensions et Faits
La modélisation repose sur une architecture ELT structurée en plusieurs zones au sein du datalake DuckDB, puis dans PostgreSQL :
```
/duckdb
  /raw          → ingestion brute (CSV, PostgreSQL, FTP)
  /staging      → nettoyage et normalisation
  /ods          → jointures et constitution des dimensions et faits
  /dwh          → données prêtes à l'export
/Postgres
  /datawarehouse → tables décisionnelles
  /datamart      → vues agrégées pour la BI
```

### Dimensions principales
**Patient**
Sélection de champs pertinents, création d'une clé substitut sk_patient.
Alimentation mensuelle.

**Professionnel**
Jointure avec établissements, clé sk_professionnel.
Alimentation mensuelle.

**Diagnostic**
Fusion de plusieurs sources, standardisation, clé sk_diagnostic.
Alimentation mensuelle.

**Localisation**
Normalisation géographique, création de sk_localisation.
Alimentation ponctuelle.

**Temps**
Génération interne, dérivation d'attributs temporels, sk_temps.
Alimentation ponctuelle.

**Autres dimensions**
Établissements, spécialités, mutuelles.

### Tables de faits
- **Consultation** : nombre, durée, répartition temporelle.
- **Hospitalisation** : volumes, durées, diagnostics.
- **Décès** : volumes, âge, localisation.
- **Satisfaction** : scores globaux et par service.
- **Qualité des soins** : ratios et évolution.

### Méthodologie de chargement
1. Ingestion brute dans /raw orchestrée par Airflow.
2. Nettoyage dans /staging via Python.
3. Constitution dans /ods avec DuckDB et DBT.
4. Export vers PostgreSQL dans /dwh.
5. Création de datamarts pour Power BI.

---

## 5. Utilisation des contextes
La gestion des contextes et paramètres est assurée par Airflow et DBT, remplaçant les contextes Talend/Cloudera par une approche plus souple et maintenable.

**Airflow** : les connexions (PostgreSQL, FTP, chemins du datalake) sont stockées sous forme de variables sécurisées et utilisées dynamiquement dans les DAG.

**DBT** : le fichier profiles.yml définit les environnements (DuckDB, PostgreSQL) et permet de basculer entre dev/test/prod sans modifier le code.

**Workflows** : les variables sont utilisées dans les tâches pour paramétrer chemins, périodes de chargement et environnements.
Cette méthode assure une séparation claire entre configuration et logique, une meilleure traçabilité et une maintenance facilitée, tout en répondant pleinement aux exigences liées à l'utilisation de contextes.

---

## Conclusion
Ce livrable établit les bases techniques et organisationnelles nécessaires à la construction d'un système décisionnel moderne pour le groupe CHU. L'approche retenue repose sur une stack légère et performante, une modélisation adaptée aux besoins métiers, une orchestration automatisée et une restitution sécurisée et interactive. Elle remplace avantageusement une stack Big Data classique par une architecture plus agile, tout en respectant les objectifs pédagogiques et analytiques du projet.
