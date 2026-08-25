# Analyse et prédiction météorologique avec R

Projet de groupe réalisé en **R** autour de l’analyse et de la prédiction météorologique à partir de données issues de l’API **Open-Meteo**.

## Contexte

Nous sommes une équipe Data chargée de développer un outil d’aide à l’analyse météorologique.

L’objectif est d’exploiter des données météo historiques afin de :

- comprendre les tendances météorologiques ;
- identifier des périodes ou conditions atypiques ;
- produire des indicateurs et visualisations ;
- construire un modèle prédictif ;
- restituer les résultats dans une application.

Le projet suit la chaîne suivante :

```text
Open-Meteo API
      ↓
R
      ↓
Préparation et nettoyage
      ↓
Base SQL
      ↓
Analyse & visualisation
      ↓
Machine Learning
      ↓
Application Shiny
```

---

# Équipe et répartition

| Membre | Responsabilité |
|---|---|
| Ikhlas LAGHMICH | API + collecte + préparation des données |
| Narcisse Cabrel TSAFACK FOUEGAP | Base SQL + qualité / structuration des données |
| Maria MENNI| Analyse exploratoire + visualisations |
| Gills Daryl KETCHA NZOUNDJI JIEPMOU | Machine Learning + Shiny / intégration finale |

---

# 1. Mission 1 : Acquisition et préparation des données

## Objectif

Récupérer les données météorologiques depuis l’API Open-Meteo, comprendre leur structure, contrôler leur qualité et produire un dataset propre utilisable par les autres membres.

## Villes étudiées

Cinq villes européennes ont été retenues :

- Lille
- Paris
- Madrid
- Rome
- Stockholm

Ce choix permet d’obtenir des conditions climatiques relativement différentes au sein de l’Europe.

## Période étudiée

Les données couvrent la période :

**01/01/2021 → 31/12/2025**

La fréquence utilisée est **horaire**.

## Source des données

Les données sont récupérées depuis l’API historique d’Open-Meteo.

Endpoint utilisé :

```text
https://archive-api.open-meteo.com/v1/archive
```

## Variables récupérées

Les variables météo collectées sont :

- `datetime`
- `temperature_2m`
- `relative_humidity_2m`
- `precipitation`
- `rain`
- `surface_pressure`
- `cloud_cover`
- `wind_speed_10m`
- `wind_direction_10m`
- `city`
- `latitude`
- `longitude`

## Script de collecte

Le script :

```text
R/01_api.R
```

permet de :

1. définir les cinq villes ;
2. définir la période étudiée ;
3. envoyer les requêtes à l’API Open-Meteo ;
4. récupérer les données au format JSON ;
5. transformer les réponses en data frames R ;
6. fusionner les données des cinq villes ;
7. sauvegarder le dataset brut.

## Résultat de la collecte

Le dataset brut contient :

```text
219 120 observations
12 variables
```

Soit :

```text
43 824 observations par ville
```

## Nettoyage et préparation

Le script :

```text
R/02_cleaning.R
```

permet de :

- convertir la date et l’heure au bon format ;
- contrôler les valeurs manquantes ;
- contrôler les doublons ;
- vérifier les types des colonnes ;
- vérifier la cohérence des valeurs ;
- créer des variables temporelles utiles ;
- créer un indicateur pluie / pas de pluie.

## Variables créées

Les variables suivantes ont été ajoutées :

- `date`
- `year`
- `month`
- `day`
- `hour`
- `season`
- `rain_flag`

La variable `rain_flag` vaut :

```text
0 = absence de pluie
1 = présence de pluie
```

## Résultat après préparation

Le dataset nettoyé contient :

```text
219 120 observations
19 variables
```

## Contrôles qualité réalisés

### Valeurs manquantes

```text
0 valeur manquante
```

### Doublons

```text
0 doublon
```

### Cohérence des valeurs

Les contrôles suivants ont été effectués :

- humidité comprise entre 0 et 100 % ;
- couverture nuageuse comprise entre 0 et 100 % ;
- direction du vent comprise entre 0 et 360° ;
- vitesse du vent non négative ;
- précipitations non négatives ;
- pluie non négative.

Aucune anomalie n’a été détectée sur ces contrôles.

## Quelques statistiques de contrôle

| Ville | Température min. | Température max. | Température moyenne |
|---|---:|---:|---:|
| Lille | -7.6 °C | 38.1 °C | 11.7 °C |
| Paris | -6.1 °C | 39.1 °C | 12.5 °C |
| Madrid | -11.1 °C | 41.5 °C | 15.9 °C |
| Rome | -2.2 °C | 40.1 °C | 17.0 °C |
| Stockholm | -18.2 °C | 32.3 °C | 7.64 °C |

## Répartition pluie / absence de pluie

Sur les observations horaires :

```text
Pas de pluie : 189 107
Pluie :         30 013
```

## Fichiers produits

```text
R/01_api.R
R/02_cleaning.R

data/raw/weather_raw.csv
data/processed/weather_clean.csv
data/processed/quality_report.csv
```

Le fichier principal transmis aux autres membres est :

```text
data/processed/weather_clean.csv
```

---

# 2. Mission 2 : Base de données SQL

## Objectif

Structurer et stocker les données nettoyées dans une base SQL afin de disposer d’une chaîne Data complète.

## Travail réalisé

- PostgreSQL 16 exécuté avec Docker Compose ;
- schéma SQL rejouable avec clés, contraintes et index ;
- normalisation des villes ;
- import bulk transactionnel et idempotent depuis R ;
- agrégation journalière calculée automatiquement en SQL ;
- contrôles qualité bloquants après chaque import.

## Structure de la base

Tables retenues :

```text
cities
weather_hourly
weather_daily
predictions
```

## Clés primaires et étrangères

- `cities.city_id` : clé primaire des villes ;
- `weather_hourly.weather_id` : clé primaire et unicité `(city_id, datetime)` ;
- `weather_daily.daily_id` : clé primaire et unicité `(city_id, date)` ;
- `predictions.prediction_id` : clé primaire ;
- les trois tables métier référencent `cities.city_id`.

Les coordonnées sont stockées une seule fois dans `cities`. Des contraintes `CHECK`
protègent notamment l'humidité, la couverture nuageuse, le vent, les
précipitations, le mois, l'heure, la saison et les indicateurs binaires.

## Schéma SQL

Le fichier `sql/schema.sql` est monté comme dossier d'initialisation Docker pour
un volume neuf. La commande `make db-schema` permet aussi de le réappliquer
explicitement sur un volume existant.

## Injection des données depuis R

`R/03_database.R` lit `data/processed/weather_clean.csv`, vérifie ses 19 colonnes,
alimente `cities`, puis copie les 219 120 mesures vers une table temporaire.
Un `INSERT ... ON CONFLICT DO UPDATE` charge ensuite `weather_hourly` en une seule
opération. L'ensemble est protégé par une transaction.

L'import est idempotent : relancer `make database` met à jour les couples
`(city_id, datetime)` existants sans créer de doublon. `weather_daily` est ensuite
recalculée depuis la table horaire. Son `rain_flag` vaut 1 si au moins une mesure
horaire du jour indique de la pluie. La table `predictions` reste intacte et vide
tant qu'aucun modèle ne l'alimente.

## Contrôles de cohérence après injection

Le script compare les nombres de villes et de mesures au CSV, vérifie les
doublons, les clés orphelines, les bornes métier, la cohérence des composantes de
date et le nombre attendu de couples ville/jour. Une anomalie provoque un code de
sortie non nul.

## Connexion et sécurité

Les identifiants ne sont jamais écrits dans le code. Ils viennent des variables
`POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST` et
`POSTGRES_PORT`. `.env` est ignoré par Git ; `.env.example` sert de modèle. Comme
R s'exécute sur l'hôte, `POSTGRES_HOST=localhost`.

## Fichiers associés

```text
R/03_database.R
sql/schema.sql
docker-compose.yml
.env.example
Makefile
```

## Installation et exécution

Prérequis : R 4.5, Docker avec le plugin Compose, GNU Make et les bibliothèques
système nécessaires aux paquets R. Sous Debian/Ubuntu, la compilation requiert
notamment `libcurl4-openssl-dev`, `libssl-dev`, `pkg-config` et `libpq-dev`.
Installez-les séparément avec le gestionnaire de paquets de votre système ; le
pipeline n'exécute volontairement aucune commande `sudo`.

Depuis la racine du dépôt :

```bash
cp .env.example .env
make install
make data
make db-up
make database
```

Pour rejouer toute la chaîne API → nettoyage → PostgreSQL :

```bash
make pipeline
```

Cette commande rappelle l'API. Si les CSV existent déjà et que vous souhaitez
seulement rejouer la partie SQL, utilisez `make database`.

## Commandes PostgreSQL utiles

```bash
make db-status
make db-schema
make db-down
make db-reset
```

`db-down` conserve le volume. `db-reset` est destructif : il supprime le volume
et toutes les données PostgreSQL ; il n'est jamais appelé par le pipeline.

Pour inspecter rapidement les tables :

```bash
docker compose exec postgres psql -U weather_user -d weather_db -c '\\dt'
docker compose exec postgres psql -U weather_user -d weather_db -c \
  'SELECT COUNT(*) FROM weather_hourly;'
```

## Dépannage minimal

- `RPostgres` ne compile pas : installer les en-têtes PostgreSQL (`libpq-dev`).
- PostgreSQL ne démarre pas : vérifier que le port défini dans `.env` est libre.
- Tables absentes : exécuter `make db-schema`.
- CSV absent : exécuter `make data`, ou `make clean` si le CSV brut existe déjà.

---

# 3. Mission 3 : Reporting et analyse météorologique

## Objectif

Produire des indicateurs et visualisations permettant de comprendre les tendances météorologiques.

## 3.1 Évolution des températures

> À compléter par le membre responsable de l’analyse.

Éléments prévus :

- évolution quotidienne ou mensuelle ;
- comparaison des villes ;
- facettes ;
- moyenne mobile ou moyenne mensuelle ;
- pics de chaleur ;
- périodes froides ;
- comparaison des saisons.

## 3.2 Pluie et précipitations

> À compléter.

Éléments prévus :

- nombre de jours de pluie ;
- précipitations moyennes ;
- précipitations maximales ;
- périodes les plus pluvieuses ;
- taux de jours pluvieux ;
- comparaison entre villes.

## 3.3 Humidité, vent et pression

> À compléter.

Éléments prévus :

- humidité vs pluie ;
- température vs humidité ;
- jours de vent fort ;
- pression vs précipitations ;
- matrice de corrélation ;
- interprétation des relations.

## Principaux résultats

> À compléter.

## Visualisations

> À compléter.

Les graphiques principaux seront enregistrés dans :

```text
figures/
```

## Fichier associé

```text
R/04_analysis.R
```

---

# 4. Mission 4 : Analyse prédictive

## Objectif

Construire au moins un modèle prédictif à partir des données historiques.

## Problème retenu

> À compléter par le membre responsable du Machine Learning.

### Option envisagée

Prédiction de la pluie :

```text
rain_flag = 0 / 1
```

ou prédiction de la température future.

## Variables utilisées

> À compléter.

## Préparation des données

> À compléter.

## Modèle(s) testé(s)

> À compléter.

Exemples possibles :

- régression logistique ;
- arbre de décision ;
- Random Forest ;
- régression linéaire.

## Métriques d’évaluation

> À compléter.

Classification :

- Accuracy
- Precision
- Recall
- F1-score
- Matrice de confusion

Régression :

- MAE
- RMSE
- R²

## Résultats

> À compléter.

## Limites du modèle

> À compléter.

## Fichier associé

```text
R/05_model.R
```

---

# 5. Mission 5 : Application Shiny

## Objectif

Restituer les analyses et prédictions dans une interface interactive.

## Fonctionnalités réalisées

> À compléter par le membre responsable de Shiny.

Fonctionnalités envisagées :

- sélection de la ville ;
- sélection de la période ;
- KPI météo ;
- graphiques interactifs ;
- comparaison des villes ;
- affichage des prédictions.

## Captures / démonstration

> À compléter.

## Lancement de l'application

> À compléter.

## Fichiers associés

```text
shiny/
app.R
```

---

# Structure générale du dépôt

```text
weather-analysis-r/
│
├── README.md
├── .gitignore
│
├── R/
│   ├── 01_api.R
│   ├── 02_cleaning.R
│   ├── 03_database.R
│   ├── 04_analysis.R
│   └── 05_model.R
│
├── data/
│   ├── raw/
│   └── processed/
│
├── sql/
│
├── figures/
│
├── models/
│
└── shiny/
```

