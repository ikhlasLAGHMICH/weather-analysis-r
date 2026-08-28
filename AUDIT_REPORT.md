# Rapport d'audit du projet `weather-analysis-r`

**Date de l'audit :** 28 août 2026  
**Périmètre :** architecture, acquisition et nettoyage des données, PostgreSQL, analyse exploratoire, machine learning, application Shiny, tests et maintenabilité.

> **Mise à jour corrective :** les anomalies relevant des membres 2 et 4 ont été
> traitées après cet audit : transaction SQL et timeout, authentification PostgreSQL,
> séparation temporelle ML, optimisation du seuil, saisies J-1, validation Shiny,
> cohérence mois/saison et filtres temporels du cache. Les constats ci-dessous
> décrivent l'état observé avant ces corrections et restent conservés pour la traçabilité.

## 1. Synthèse générale

Le projet propose une chaîne Data complète :

```text
Open-Meteo → préparation R → PostgreSQL → analyses → modèles ML → application Shiny
```

L'ensemble est ambitieux et bien structuré pour un projet académique. La séparation des responsabilités, la présence d'un `Makefile`, l'utilisation de `renv`, le schéma PostgreSQL, les artefacts d'analyse et le dashboard Shiny constituent une base sérieuse.

### Appréciation globale

**Évaluation indicative : 7/10.**

Le projet est convaincant pour une démonstration ou une soutenance, mais plusieurs écarts entre la documentation et l'implémentation, ainsi que quelques défauts fonctionnels dans Shiny et dans l'évaluation ML, doivent être corrigés avant de considérer la chaîne comme robuste.

### Points forts principaux

- pipeline couvrant l'ensemble du cycle de vie des données ;
- scripts R organisés par étape métier ;
- base PostgreSQL normalisée avec contraintes et index ;
- import idempotent avec `ON CONFLICT` ;
- séparation temporelle entre entraînement et test ;
- comparaison régression logistique / Random Forest ;
- application Shiny riche et cohérente visuellement ;
- fallback vers un cache local lorsque PostgreSQL est indisponible ;
- présence de tests unitaires et d'artefacts reproductibles ;
- documentation détaillée dans le README.

### Risques prioritaires

1. l'import PostgreSQL est annoncé comme transactionnel, mais aucune transaction explicite n'est utilisée ;
2. certaines valeurs numériques égales à zéro bloquent silencieusement la prédiction Shiny ;
3. l'interface renseigne incorrectement les variables météo de J-1 ;
4. plusieurs modèles d'événements rares présentent une accuracy élevée tout en ne détectant aucun cas positif ;
5. le jeu de test 2025 sert à la fois à choisir le meilleur modèle et à publier sa performance ;
6. le fallback Shiny sur cache n'applique pas toujours les filtres de dates ;
7. la suite de tests d'intégration peut rester bloquée sur la connexion PostgreSQL.

## 2. Architecture et organisation

### Constat

La progression suivante est facile à comprendre :

- `R/01_api.R` : collecte Open-Meteo ;
- `R/02_cleaning.R` : nettoyage et enrichissement ;
- `R/03_database.R` : import PostgreSQL ;
- `R/04_analysis.R` : analyses et visualisations ;
- `R/05_model.R` : entraînement des modèles ;
- `R/model_helpers.R` : fonctions partagées ;
- `shiny/app.R` : restitution interactive.

Le `Makefile` rend les étapes principales accessibles avec des commandes simples. Le verrouillage des dépendances avec `renv.lock` améliore également la reproductibilité.

### Points à améliorer

- Plusieurs scripts de récupération ou de correction à la racine donnent une impression de chantier temporaire. Les scripts encore utiles devraient être documentés et déplacés dans `tools/`; les autres devraient être retirés.
- Les chemins relatifs supposent généralement une exécution depuis la racine. Une détection commune de la racine du projet rendrait tous les scripts plus robustes.
- Les fonctions de lecture du fichier `.env` sont dupliquées dans plusieurs fichiers. Elles devraient être centralisées.
- Une intégration continue devrait valider automatiquement la syntaxe, les tests unitaires et, séparément, les tests PostgreSQL.

## 3. Acquisition des données

### Points positifs

- source et endpoint clairement identifiés ;
- liste explicite des villes et variables ;
- format tabulaire homogène après récupération ;
- création automatique du dossier de sortie.

### Risques

- Les requêtes ne définissent pas explicitement de stratégie de retry ou de timeout.
- La structure de la réponse API est supposée valide avant d'accéder à `data$hourly`.
- Il n'existe pas de contrôle explicite du statut, des unités ou de la longueur identique des séries retournées.
- `timezone = "auto"` renvoie des heures locales, ensuite interprétées comme UTC dans la chaîne SQL. Cela peut introduire des décalages et des ambiguïtés aux changements d'heure.
- La période est codée en dur, ce qui limite la réutilisation du pipeline.

### Recommandations

- utiliser explicitement UTC lors de la collecte, ou conserver le fuseau de chaque ville ;
- ajouter timeout, retry et messages d'erreur contextualisés ;
- vérifier les métadonnées et longueurs des colonnes de la réponse ;
- rendre les dates et villes configurables ;
- conserver un journal minimal de collecte : date, ville, statut et nombre de lignes.

## 4. Nettoyage et qualité des données

### Points positifs

- création de variables temporelles utiles ;
- suppression des doublons ;
- création de `rain_flag` ;
- calcul d'un rapport descriptif par ville ;
- contrôle des principales bornes métier.

### Problème principal

Les contrôles qualité sont calculés et affichés, mais ils ne sont pas bloquants. Par exemple, compter les humidités hors de `[0, 100]` ne provoque pas l'échec du pipeline.

Le pipeline peut donc produire `weather_clean.csv` même lorsqu'une anomalie métier est présente.

### Recommandations

- transformer les contrôles critiques en assertions avec `stop()` ;
- vérifier les colonnes attendues avant tout traitement ;
- valider explicitement la conversion des dates et les valeurs manquantes introduites par celle-ci ;
- contrôler l'unicité sur la clé métier `(city, datetime)`, et pas seulement les lignes entièrement identiques ;
- produire un rapport qualité comportant une colonne `status` et les nombres d'anomalies ;
- n'écrire le fichier nettoyé qu'après validation complète.

## 5. PostgreSQL

### Points positifs

- schéma séparé et rejouable ;
- normalisation des villes ;
- contraintes métier au niveau SQL ;
- clés étrangères et index ;
- import bulk via une table temporaire ;
- UPSERT idempotent des observations horaires ;
- reconstruction de l'agrégat journalier ;
- contrôles de cohérence après import.

### Anomalie critique : transaction absente

Le README indique que l'import est protégé par une transaction. Pourtant, `R/03_database.R` n'appelle pas explicitement :

```r
DBI::dbBegin(con)
DBI::dbCommit(con)
DBI::dbRollback(con)
```

Le script supprime ensuite toutes les lignes de `weather_daily` avant de reconstruire cette table. Si une erreur survient entre ces opérations, la base peut rester dans un état incomplet.

### Autres améliorations

- garantir la déconnexion avec `on.exit(DBI::dbDisconnect(con), add = TRUE)` ;
- englober l'import et la reconstruction journalière dans une transaction unique ;
- déclencher un rollback automatique en cas d'erreur ;
- éviter de supprimer toutes les agrégations si seules quelques données ont changé, si le volume augmente ;
- documenter clairement que les identifiants de `.env.example` sont destinés uniquement au développement local.

## 6. Analyse exploratoire et visualisations

### Points positifs

- analyses diversifiées et cohérentes avec les objectifs ;
- sorties CSV et PNG faciles à réutiliser ;
- style graphique centralisé ;
- fonctions d'agrégation tolérantes aux valeurs manquantes ;
- cache RDS utile à Shiny.

### Points à améliorer

- Le nombre exact de `219120` lignes est codé en dur. Une validation fondée sur la période, les villes et la fréquence serait plus robuste.
- Le script dépend obligatoirement de PostgreSQL alors que certaines analyses pourraient utiliser le CSV nettoyé en fallback.
- Certaines conclusions gagneraient à inclure des intervalles, distributions ou tests statistiques au lieu de seules moyennes.
- Les unités et définitions devraient être vérifiées systématiquement entre Open-Meteo, PostgreSQL, les figures et Shiny.

## 7. Machine learning

### Méthode actuelle

Pour chaque événement, le projet :

1. construit une cible binaire à partir de règles métier ;
2. crée des variables courantes et retardées ;
3. prédit l'événement à J+1 ;
4. entraîne une régression logistique et une Random Forest ;
5. évalue sur 2025 ;
6. sélectionne le modèle ayant le meilleur F1 ;
7. sauvegarde le modèle et les prédictions.

### Résultats observés

Les modèles les plus convaincants sont approximativement :

| Événement | Meilleur F1 observé | Appréciation |
|---|---:|---|
| Canicule | 0,83 | Bon résultat sur les données étudiées |
| Risque de sécheresse | 0,81 | Bon résultat sur la cible proxy |
| Gel | 0,76 | Résultat encourageant |
| Pluie | 0,46 | Modeste, mais exploitable avec prudence |
| Neige | 0,17 | Faible détection des cas positifs |
| Brouillard | 0,06 | Modèle peu exploitable au seuil actuel |
| Fortes pluies | indéfini | Aucun cas positif prédit |
| Tempête | indéfini | Évaluation non informative |

### Problèmes méthodologiques

#### Sélection sur le jeu de test

L'année 2025 sert à comparer les deux algorithmes et à annoncer la performance du gagnant. Elle n'est donc plus un test entièrement indépendant.

Une séparation plus rigoureuse serait :

```text
2021–2023 : entraînement
2024      : validation, modèle et seuil
2025      : évaluation finale
```

#### Classes rares

Pour les tempêtes, fortes pluies et brouillard, l'accuracy est trompeuse. Un modèle qui prédit toujours « non » peut obtenir une accuracy proche de 100 % tout en étant inutile.

#### Seuil fixe

Toutes les prédictions utilisent un seuil de `0.5`. Ce seuil n'est pas nécessairement adapté aux événements rares.

#### Nature des cibles

Plusieurs événements sont des proxys construits avec des seuils, et non des observations officielles. Ils doivent être présentés comme des indicateurs heuristiques.

### Recommandations ML

- réserver 2025 à l'évaluation finale ;
- utiliser une validation temporelle glissante ;
- optimiser le seuil sur le jeu de validation ;
- ajouter PR-AUC, balanced accuracy et taux de positifs ;
- envisager pondération des classes ou rééchantillonnage uniquement sur le train ;
- publier les matrices de confusion ;
- empêcher la promotion d'un modèle dont le recall positif est nul ou indéfini ;
- calibrer les probabilités si elles sont affichées directement aux utilisateurs ;
- documenter explicitement les règles définissant chaque cible.

## 8. Audit spécifique de l'application Shiny

### Points positifs

- navigation simple et logique ;
- thème graphique cohérent ;
- graphiques interactifs avec Plotly ;
- filtres par ville et période ;
- chargement différé des modèles RDS ;
- prédiction disponible même sans connexion SQL ;
- message indiquant le mode cache ou l'absence de données ;
- séparation claire entre saisie, résultat, métriques et importance.

### 8.1 Valeurs égales à zéro bloquées

Dans le bloc de prédiction, plusieurs valeurs numériques sont passées directement à `req()`. Shiny considère `0` comme une valeur fausse.

Des valeurs pourtant valides peuvent donc empêcher silencieusement la prédiction :

- température de `0 °C` ;
- vent de `0 km/h` ;
- humidité de `0 %` ;
- précipitations J-1 de `0 mm`.

Il faut tester explicitement `!is.null(value)` et `is.finite(value)`.

### 8.2 Variables J-1 incorrectes

Le modèle attend notamment `pressure_lag1` et `humidity_lag1`. L'application leur affecte cependant les valeurs de pression et d'humidité du jour courant :

```r
pressure_lag1 = input$pred_pressure
humidity_lag1 = input$pred_humidity
```

Cette différence entre entraînement et inférence peut dégrader ou fausser la prédiction.

Deux solutions sont possibles :

- ajouter de vrais champs « pression J-1 » et « humidité J-1 » ;
- réentraîner les modèles sans ces variables si elles ne peuvent pas être fournies.

### 8.3 Incohérence mois/saison

Le mois et la saison sont sélectionnés indépendamment. L'utilisateur peut donc envoyer une combinaison impossible, comme juillet et hiver.

La saison devrait être calculée automatiquement depuis le mois avec `assign_season()`.

### 8.4 Filtres incomplets en mode cache

Avec PostgreSQL, les filtres de dates sont appliqués aux données quotidiennes et mensuelles. Avec le cache, plusieurs sorties filtrent uniquement les villes.

La période affichée dans le sélecteur peut alors changer sans modifier le graphique, ce qui donne une information trompeuse.

Les objets temporels du cache doivent être filtrés par date. Pour les agrégats calculés sur toute la période, il faut soit stocker des données suffisamment détaillées, soit désactiver le filtre en expliquant pourquoi.

### 8.5 Démarrage et timeout PostgreSQL

La connexion PostgreSQL est tentée immédiatement au chargement global de `app.R`. Un test de chargement limité à 30 secondes n'a pas terminé dans le délai disponible.

Le fallback vers le cache doit être précédé d'un timeout court et maîtrisé. Une indisponibilité SQL ne devrait pas retarder fortement l'affichage initial.

### 8.6 Présentation des résultats ML

Des formulations comme « TEMPÊTE PROBABLE » donnent une impression de certitude excessive, notamment lorsque le modèle associé a un recall nul ou indéfini.

Préférer :

- « risque estimé » ;
- un niveau de confiance explicite ;
- un avertissement pour les modèles peu fiables ;
- un format lisible pour les métriques indisponibles ;
- une mention indiquant que les événements sont souvent des proxys définis par des seuils.

### 8.7 Validation des saisies

L'interface autorise des combinaisons physiquement incohérentes, par exemple une température minimale supérieure à la température maximale.

Il faut ajouter des validations :

- `temp_min <= temp_mean <= temp_max` ;
- valeurs finies et dans les plages prévues ;
- saison dérivée du mois ;
- modèle et variables requis disponibles ;
- message d'erreur visible avec `validate(need(...))`.

### Verdict Shiny

L'application est convaincante visuellement et adaptée à une démonstration contrôlée. Elle n'est toutefois pas encore suffisamment robuste pour des saisies libres ou un déploiement public.

Les corrections prioritaires côté Shiny sont :

1. accepter correctement les valeurs égales à zéro ;
2. corriger les variables J-1 ;
3. dériver automatiquement la saison ;
4. appliquer réellement les dates en mode cache ;
5. ajouter un timeout de connexion SQL ;
6. contextualiser la fiabilité des prédictions.

## 9. Tests et vérifications

### Vérifications effectuées pendant l'audit

- inventaire des fichiers du projet ;
- lecture des scripts principaux, du schéma SQL, du `Makefile` et des tests ;
- contrôle de la syntaxe des fichiers R : les fichiers examinés sont syntaxiquement valides ;
- lecture des métriques exportées ;
- tentative de lancement de la suite de tests ;
- tentative de chargement de l'application Shiny.

### Résultat de la suite actuelle

La suite complète a été lancée, mais elle est restée sans sortie jusqu'à interruption. Le test d'intégration PostgreSQL tente une connexion sans timeout suffisamment court, ce qui peut bloquer l'ensemble lorsque la base n'est pas disponible.

### Limites des tests Shiny

Le fichier nommé `test_shiny.R` vérifie surtout :

- la présence des fichiers ;
- le chargement des helpers ;
- l'absence de quelques identifiants écrits en clair ;
- la présence textuelle de `shinyApp` et `navbarPage`.

Le test présenté comme un test serveur n'appelle pas réellement `shiny::testServer()` et ne teste pas la logique réactive de l'application.

### Recommandations de test

- séparer `unit`, `integration` et `shiny` ;
- ne pas faire dépendre les tests unitaires de PostgreSQL ;
- ajouter des timeouts courts aux tests de connexion ;
- utiliser une base PostgreSQL éphémère en CI ;
- tester les valeurs égales à zéro ;
- tester les filtres ville/date dans les deux modes ;
- tester la cohérence des données envoyées au modèle ;
- tester les erreurs de saisie ;
- tester le fallback DB → cache ;
- ajouter un vrai `testServer()` sur les principales réactions.

## 10. Sécurité et exploitation

### Points positifs

- les identifiants sont chargés depuis l'environnement ;
- `.env` est exclu par `.gitignore` ;
- aucun mot de passe de production évident n'est intégré à l'application ;
- les requêtes d'import paramétrées limitent les risques d'injection.

### Recommandations

- ne jamais réutiliser le mot de passe d'exemple hors développement ;
- valider toutes les variables d'environnement au démarrage ;
- limiter les droits du compte PostgreSQL utilisé par Shiny à la lecture si l'application ne doit pas écrire ;
- ajouter des limites de taille et des timeouts ;
- ne pas afficher les messages d'erreur SQL détaillés aux utilisateurs ;
- prévoir des logs structurés sans informations sensibles.

## 11. Plan d'action priorisé

### Priorité P0 — corrections critiques

| Action | Bénéfice attendu |
|---|---|
| Encadrer l'import SQL avec transaction, commit et rollback | Évite une base partiellement mise à jour |
| Corriger `req()` pour accepter les zéros dans Shiny | Supprime un blocage fonctionnel silencieux |
| Corriger les variables `pressure_lag1` et `humidity_lag1` | Aligne l'inférence sur l'entraînement |
| Ajouter un timeout aux connexions PostgreSQL | Évite les démarrages et tests bloqués |

### Priorité P1 — fiabilité scientifique et fonctionnelle

| Action | Bénéfice attendu |
|---|---|
| Introduire train/validation/test temporels | Rend les métriques finales plus crédibles |
| Optimiser les seuils pour les classes rares | Améliore recall et F1 |
| Bloquer le pipeline en cas d'anomalie qualité | Empêche la propagation de données invalides |
| Dériver la saison depuis le mois | Évite les observations incohérentes |
| Appliquer les dates en mode cache | Garantit la cohérence des graphiques |
| Ajouter les validations physiques des températures | Évite les saisies impossibles |

### Priorité P2 — industrialisation

| Action | Bénéfice attendu |
|---|---|
| Ajouter une CI | Détecte automatiquement les régressions |
| Séparer tests unitaires et intégration | Rend les tests rapides et fiables |
| Centraliser configuration et lecture `.env` | Réduit la duplication |
| Nettoyer ou ranger les scripts temporaires | Améliore la lisibilité du dépôt |
| Ajouter logs et documentation de déploiement | Facilite l'exploitation |

## 12. Conclusion

`weather-analysis-r` est un projet complet, lisible et pertinent pour démontrer des compétences en R, SQL, visualisation, machine learning et Shiny. Sa force principale est de proposer une chaîne cohérente de bout en bout plutôt qu'une juxtaposition de scripts isolés.

Les faiblesses relevées sont corrigeables sans refonte générale. Les travaux les plus urgents concernent la transaction SQL, la cohérence des entrées Shiny et la méthodologie d'évaluation des événements rares.

Après correction des éléments P0 et P1, le projet gagnera nettement en robustesse technique, en crédibilité scientifique et en qualité de démonstration.
