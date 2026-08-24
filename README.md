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

> À compléter par le membre responsable de la Mission 2.

## Structure de la base

> À compléter.

Tables envisagées :

```text
cities
weather_hourly
weather_daily
predictions
```

## Clés primaires et étrangères

> À compléter.

## Schéma SQL

> À compléter.

## Injection des données depuis R

> À compléter.

## Contrôles de cohérence après injection

> À compléter.

## Connexion et sécurité

> À compléter.

## Fichiers associés

```text
R/03_database.R
sql/
```

> À compléter avec les fichiers réellement utilisés.

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

