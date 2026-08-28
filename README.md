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

L'objectif de cette partie est d'explorer les données météorologiques stockées dans PostgreSQL afin d'identifier les principales tendances climatiques, de comparer les cinq villes et d'étudier les relations entre les variables météorologiques.

Le script utilisé est :

```text
R/04_analysis.R
```

Les résultats sont enregistrés dans les dossiers :

```text
figures/
results/
```
## Données analysées

L'analyse porte sur les données horaires de **Lille, Paris, Madrid, Rome et Stockholm**, sur la période **2021–2025**.

Les principales variables étudiées sont :

- température ;
- précipitations ;
- humidité relative ;
- pression atmosphérique ;
- nébulosité ;
- vitesse du vent.

## 3.1 Évolution des températures

Plusieurs analyses permettent de comparer les températures entre les villes.

### Température moyenne par ville

| Ville | Température moyenne |
|---|---:|
| Stockholm | 7,6 °C |
| Lille | 11,7 °C |
| Paris | 12,5 °C |
| Madrid | 15,9 °C |
| Rome | 17,0 °C |

Les températures extrêmes observées montrent également des différences importantes entre les villes. Stockholm présente le minimum le plus bas (**-18,2 °C**) et Madrid le maximum le plus élevé (**41,5 °C**).

### Évolution mensuelle

L'évolution mensuelle montre une forte saisonnalité pour les cinq villes : les températures augmentent au printemps, atteignent leurs niveaux les plus élevés en été puis diminuent à l'automne et en hiver. Stockholm présente le profil le plus froid, tandis que Madrid et Rome présentent les températures les plus élevées.

### Comparaison saisonnière

Les moyennes saisonnières confirment ces différences climatiques. En été, Madrid atteint environ **26,6 °C** et Rome **26,4 °C**, contre environ **17,3 °C** pour Stockholm.

En hiver, Stockholm présente une moyenne d'environ **-1 °C**, alors que Rome atteint environ **9,1 °C**.

### Nombre de jours de pluie

| Ville | Jours de pluie | Taux |
|---|---:|---:|
| Stockholm | 905 | 49,6 % |
| Lille | 1070 | 61,1 % |
| Paris | 1027 | 58,6 % |
| Madrid | 656 | 35,9 % |
| Rome | 825 | 45,2 % |

Lille et Paris présentent donc la fréquence de jours pluvieux la plus élevée, tandis que Madrid présente le taux le plus faible.

### Précipitations mensuelles

L'évolution mensuelle des précipitations met en évidence une forte variabilité d'un mois à l'autre. Les cumuls présentent des pics importants selon les années et les villes, ce qui permet d'identifier les périodes les plus pluvieuses et de comparer les profils des cinq villes.

## 3.3 Humidité et vent

### Humidité relative moyenne

| Ville | Humidité moyenne |
|---|---:|
| Stockholm | 78,9 % |
| Lille | 78,3 % |
| Paris | 76,3 % |
| Madrid | 59,1 % |
| Rome | 71,8 % |

Stockholm, Lille et Paris présentent les niveaux d'humidité moyens les plus élevés, tandis que Madrid est nettement moins humide.

### Vitesse du vent

| Ville | Moyenne | Maximum |
|---|---:|---:|
| Stockholm | 12,0 km/h | 42,0 km/h |
| Lille | 14,1 km/h | 69,9 km/h |
| Paris | 12,0 km/h | 52,4 km/h |
| Madrid | 10,1 km/h | 48,2 km/h |
| Rome | 9,0 km/h | 42,4 km/h |

Lille présente la vitesse moyenne la plus élevée ainsi que le maximum de vent le plus important.

## 3.4 Relations entre les variables météorologiques

### Température et humidité

Les nuages de points montrent une relation négative entre la température et l'humidité dans les cinq villes : lorsque la température augmente, l'humidité relative tend globalement à diminuer.

### Matrice de corrélation

| Relation | Corrélation |
|---|---:|
| Température – Humidité relative | -0,64 |
| Humidité relative – Pression | 0,31 |
| Humidité relative – Nébulosité | 0,29 |
| Nébulosité – Précipitations | 0,17 |
| Humidité relative – Précipitations | 0,13 |
| Température – Précipitations | ≈ 0 |
| Pression – Précipitations | -0,03 |
| Température – Vitesse du vent | -0,04 |

La relation la plus marquée est celle entre **température et humidité relative (-0,64)**. À l'inverse, la corrélation entre température et précipitations est quasiment nulle dans cet ensemble de données.

## 3.5 Visualisations produites

Le script `R/04_analysis.R` génère neuf visualisations principales :

1. température moyenne par ville ;
2. évolution mensuelle de la température ;
3. température moyenne par saison ;
4. nombre de jours de pluie par ville ;
5. évolution mensuelle des précipitations ;
6. humidité relative moyenne par ville ;
7. vitesse du vent par ville ;
8. relation entre température et humidité ;
9. matrice de corrélation des variables météorologiques.

Les graphiques sont sauvegardés dans :

```text
figures/
```

Les tableaux de résultats sont sauvegardés dans :

```text
results/
```

## Fichiers associés

```text
R/04_analysis.R

figures/
├── 01_temperature_mean_city.png
├── 02_temperature_monthly.png
├── 03_temperature_season.png
├── 04_rainy_days.png
├── 05_precipitation_monthly.png
├── 06_humidity_city.png
├── 07_wind_city.png
├── 08_temperature_humidity.png
└── 09_correlation.png

results/
├── 01_temperature_city.csv
├── 02_temperature_monthly.csv
├── 03_temperature_season.csv
├── 04_rainy_days.csv
├── 05_precipitation_monthly.csv
├── 06_humidity_city.csv
├── 07_wind_city.csv
├── 09_correlation_matrix.csv
└── 09_correlation_long.csv
```

---

# 4. Mission 4 : Analyse prédictive

## Objectif

Construire des modèles prédictifs robustes pour anticiper diverses conditions météorologiques à partir des données historiques.

## Problème retenu

Prédiction de **8 événements météorologiques** distincts (Pluie, Pluie forte, Orage / Tempête, Neige, Gel, Canicule, Brouillard, Risque de sécheresse) à horizon J+1. Le pipeline est conçu pour être extensible et s'entraîner sur de nouvelles cibles facilement.

## Variables utilisées

- Variables météorologiques de base (Température min/max/moyenne, Humidité, Pression, Vitesse du vent).
- Variables temporelles (Mois, Saison).
- Variables de décalage temporel (Lags) : Conditions de la veille (Précipitations J-1, Pression J-1, Humidité J-1, Événement survenu à J-1).

## Préparation des données

- Suppression des lignes rendues incomplètes par la création des décalages J-1/J+1.
- Encodage des variables catégorielles (Saison, Ville).
- Création automatique des cibles binaires (1/0) selon des seuils documentés.
- Fractionnement temporel strict : entraînement 2021-2023, validation et choix du seuil en 2024, évaluation finale en 2025.

## Modèles testés

Pour chaque intempérie, nous entraînons et mettons en compétition deux modèles :
- **Régression Logistique** (rapide, interprétable)
- **Random Forest** (plus complexe, capture les interactions non linéaires via `ranger`)

Le pipeline sélectionne automatiquement le meilleur modèle sur le jeu de validation,
optimise son seuil de décision selon le F1-score, puis publie les métriques finales
sur 2025. Le jeu de test n'est donc pas utilisé pour choisir le gagnant.

## Métriques d’évaluation

Classification :
- Accuracy
- Precision
- Recall
- F1-score
- AUC-ROC

## Résultats

Les modèles sont sauvegardés individuellement au format `.rds` dans le dossier `results/`. Une approche de **Lazy Loading** a été mise en place pour ne charger en mémoire que le modèle nécessaire lors de l'inférence. Les métriques globales sont consolidées dans un rapport CSV.

## Limites du modèle

- La prédiction se limite à un horizon temporel de 24h (J+1).
- Les événements rares souffrent d'un fort déséquilibre de classe ; leurs scores
  d'accuracy doivent être interprétés avec la précision, le recall, le F1 et l'AUC.
- Brouillard et risque de sécheresse sont des extensions conservées sous forme de
  proxys définis par des seuils, et non des observations officielles d'événements.

## Fichier associé

```text
R/05_model.R
R/model_helpers.R
```

---

# 5. Mission 5 : Application Shiny

## Objectif

Restituer les analyses et prédictions dans une interface interactive et robuste.

## Fonctionnalités réalisées

L'application Shiny propose une interface "Dark Mode" professionnelle avec :
- **Dashboard interactif** : Suivi des KPIs (Température, Jours de pluie, Précipitations).
- **Visualisations avancées (Plotly)** : Évolution temporelle, comparaisons inter-villes, matrice de corrélation, diagrammes d'importance des variables.
- **Filtres réactifs** : Filtrage croisé par Villes et par Dates sur l'ensemble des graphiques.
- **Module de Prédiction ML** : Interface dynamique permettant de simuler les conditions du jour J pour prédire le risque d'intempérie à J+1 (Lazy loading autonome des modèles).
- **Résilience (Fallback Cache)** : Mécanisme de tolérance aux pannes basculant automatiquement sur un cache local (`.rds`) si la base PostgreSQL est inaccessible.
- graphiques interactifs ;
- comparaison des villes ;
- affichage des prédictions.

## Captures / démonstration

> À compléter.

## Lancement de l'application

Depuis la racine du projet :

```bash
make install
make shiny
```

L'application tente PostgreSQL pendant au maximum quelques secondes, puis bascule
sur le cache local si la base est indisponible. En mode cache, seuls les objets
pré-calculés disponibles peuvent être filtrés avec la même granularité que la base.

## Fichiers associés

```text
shiny/app.R
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

