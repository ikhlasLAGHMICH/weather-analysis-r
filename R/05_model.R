# ============================================================
# 05_model.R — Analyse predictive : Multi-Intemperies
# Gills — feature/gills-ml-shiny
# ============================================================
# Pipeline :
#   1. Connexion PostgreSQL (weather_daily)
#   2. Generation des 8 cibles via create_multi_targets()
#   3. Boucle sur les 8 intemperies (WEATHER_EVENTS)
#      a. Feature engineering (lags, cibles J+1)
#      b. Split temporel train (2021-2024) / test (2025)
#      c. Regression Logistique & Random Forest
#      d. Evaluation (F1, AUC, etc.)
#      e. Selection du meilleur modele, compression et sauvegarde (.rds)
#      f. Persistance des predictions test dans PostgreSQL
#   4. Export d'un CSV consolide de toutes les metriques
# ============================================================

suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
  library(dplyr)
  library(lubridate)
  library(ranger)
  library(pROC)
})

# ============================================================
# 0. HELPERS ET STYLE
# ============================================================

source("04_style.R")
source("R/model_helpers.R")

dir.create("results", recursive = TRUE, showWarnings = FALSE)
dir.create("figures", recursive = TRUE, showWarnings = FALSE)

# ============================================================
# 1. CHARGEMENT DE L'ENVIRONNEMENT ET CONNEXION POSTGRESQL
# ============================================================

load_env_file(".env")

config <- list(
  dbname   = get_env("POSTGRES_DB"),
  user     = get_env("POSTGRES_USER"),
  password = get_env("POSTGRES_PASSWORD"),
  host     = get_env("POSTGRES_HOST", "localhost"),
  port     = as.integer(get_env("POSTGRES_PORT", "5432"))
)

message("Connexion a PostgreSQL...")
con <- DBI::dbConnect(
  RPostgres::Postgres(),
  dbname   = config$dbname,
  host     = config$host,
  port     = config$port,
  user     = config$user,
  password = config$password
)

if (!DBI::dbIsValid(con)) stop("Connexion PostgreSQL invalide.", call. = FALSE)
message("Connexion OK.")

# ============================================================
# 2. CHARGEMENT DE weather_daily ET MULTI-TARGETS
# ============================================================

sql_daily <- "
  SELECT
    d.date,
    c.name               AS city,
    d.temp_min,
    d.temp_max,
    d.temp_mean,
    d.humidity_mean,
    d.precipitation_total,
    d.rain_total,
    d.pressure_mean,
    d.cloud_cover_mean,
    d.wind_speed_mean,
    d.wind_speed_max,
    d.rain_flag
  FROM weather_daily d
  INNER JOIN cities c ON d.city_id = c.city_id
  ORDER BY c.name, d.date
"

message("Lecture de weather_daily depuis PostgreSQL...")
daily_raw <- DBI::dbGetQuery(con, sql_daily)
message(sprintf("Lignes chargees : %d", nrow(daily_raw)))
if (nrow(daily_raw) == 0) stop("weather_daily est vide.", call. = FALSE)

# Generation des 8 flags cibles pour toutes les intemperies
daily_raw <- create_multi_targets(daily_raw)

# Mapping ville/id pour les predictions
city_map <- DBI::dbGetQuery(con, "SELECT city_id, name FROM cities")
DBI::dbDisconnect(con)
rm(con)

# ============================================================
# 3. BOUCLE D'ENTRAINEMENT SUR LES 8 CIBLES
# ============================================================

SEASON_LEVELS <- c("Winter", "Spring", "Summer", "Autumn")
TRAIN_CUTOFF  <- as.Date("2025-01-01")

FEATURES <- c(
  "temp_min", "temp_max", "temp_mean",
  "humidity_mean", "pressure_mean",
  "wind_speed_mean", "wind_speed_max",
  "cloud_cover_mean",
  "month", "season", "city",
  "flag_lag1", "precip_lag1",
  "pressure_lag1", "humidity_lag1"
)
formula_ml <- as.formula(paste("target ~", paste(FEATURES, collapse = " + ")))

all_metrics <- list()

message("\n========================================")
message("DEBUT DE L'ENTRAINEMENT MULTI-INTEMPERIES")
message("========================================")

for (event_key in names(WEATHER_EVENTS)) {
  
  event_config <- WEATHER_EVENTS[[event_key]]
  flag_col     <- event_config$col
  
  cat(sprintf("\n>>> Entrainement pour la cible : %s (%s) <<<\n", event_key, event_config$label))
  
  # a. Feature engineering dedie a cette cible
  model_data <- engineer_features(
    daily         = daily_raw,
    flag_col      = flag_col,
    city_order    = city_order,
    season_levels = SEASON_LEVELS
  )
  
  # b. Split temporel
  train <- model_data |> filter(date < TRAIN_CUTOFF)
  test  <- model_data |> filter(date >= TRAIN_CUTOFF)
  
  if (nrow(train) == 0 || nrow(test) == 0) {
    warning("Train ou test vide pour ", event_key, " — Skip.")
    next
  }
  
  n_pos_train <- sum(train$target == "Yes")
  if (n_pos_train == 0) {
    warning("Aucun cas positif dans le train pour ", event_key, " — Skip.")
    next
  }
  
  # c. Regression Logistique
  # cat("  - LR...")
  lr_model <- glm(formula_ml, data = train, family = binomial)
  lr_prob  <- predict(lr_model, newdata = test, type = "response")
  lr_class <- factor(ifelse(lr_prob >= 0.5, "Yes", "No"), levels = c("No", "Yes"))
  metrics_lr <- compute_metrics(test$target, lr_class, lr_prob, "Logistic Regression")
  
  # d. Random Forest
  # cat("  - RF...")
  set.seed(42L)
  rf_model <- ranger::ranger(
    formula     = formula_ml,
    data        = train,
    num.trees   = 500L,
    mtry        = max(1L, floor(sqrt(length(FEATURES)))),
    importance  = "impurity",
    probability = TRUE,
    num.threads = 1L,
    seed        = 42L
  )
  rf_prob  <- predict(rf_model, data = test)$predictions[, "Yes"]
  rf_class <- factor(ifelse(rf_prob >= 0.5, "Yes", "No"), levels = c("No", "Yes"))
  metrics_rf <- compute_metrics(test$target, rf_class, rf_prob, "Random Forest")
  
  # e. Comparaison et selection (critere F1)
  metrics_table <- data.frame(
    event     = event_key,
    model     = c("Logistic Regression", "Random Forest"),
    accuracy  = c(metrics_lr$accuracy,   metrics_rf$accuracy),
    precision = c(metrics_lr$precision,  metrics_rf$precision),
    recall    = c(metrics_lr$recall,     metrics_rf$recall),
    f1        = c(metrics_lr$f1,         metrics_rf$f1),
    auc       = c(metrics_lr$auc,        metrics_rf$auc),
    stringsAsFactors = FALSE
  )
  
  best_idx <- which.max(metrics_table$f1)
  if (length(best_idx) == 0) {
    best_idx <- which.max(metrics_table$auc)
  }
  if (length(best_idx) == 0) {
    best_idx <- 1L
  }

  best_name  <- metrics_table$model[best_idx]
  best_model <- if (best_idx == 1L) lr_model else rf_model
  best_prob  <- if (best_idx == 1L) lr_prob  else rf_prob
  best_class <- if (best_idx == 1L) lr_class else rf_class
  
  cat(sprintf("  Gagnant : %s (F1: %.4f, AUC: %.4f)\n", 
              best_name, metrics_table$f1[best_idx], metrics_table$auc[best_idx]))
  
  all_metrics[[event_key]] <- metrics_table
  
  # Importance (si RF gagnant, sinon on exporte quand meme l'importance du RF)
  importance_df <- data.frame(
    feature    = names(rf_model$variable.importance),
    importance = rf_model$variable.importance,
    stringsAsFactors = FALSE
  ) |> arrange(desc(importance))
  
  # ============================================================
  # Optimisation Memoire du modele GLM (purger les gros objets)
  # ============================================================
  if (inherits(best_model, "glm")) {
    best_model$data <- NULL
    best_model$y <- NULL
    best_model$linear.predictors <- NULL
    best_model$weights <- NULL
    best_model$fitted.values <- NULL
    best_model$model <- NULL
    best_model$prior.weights <- NULL
    best_model$residuals <- NULL
    best_model$effects <- NULL
    best_model$qr$qr <- NULL
  }
  
  # f. Sauvegarde du bundle .rds
  bundle <- list(
    event_key     = event_key,
    event_label   = event_config$label,
    model         = best_model,
    model_name    = best_name,
    features      = FEATURES,
    metrics       = metrics_table[best_idx, ],
    importance    = importance_df,
    threshold     = 0.5,
    train_cutoff  = as.character(TRAIN_CUTOFF),
    city_order    = city_order,
    season_levels = SEASON_LEVELS,
    created_at    = Sys.time()
  )
  
  rds_path <- file.path("results", paste0(event_key, "_model.rds"))
  saveRDS(bundle, rds_path, compress = TRUE)
  
  # g. Persistance des predictions (UPSERT)
  test_preds <- test |>
    select(date, city) |>
    mutate(
      prediction_datetime = as.POSIXct(date, tz = "UTC"),
      model_name          = best_name,
      target              = event_key,
      predicted_value     = as.numeric(best_class == "Yes"),
      probability         = round(best_prob, 6L)
    ) |>
    left_join(city_map, by = c("city" = "name")) |>
    select(city_id, prediction_datetime, model_name, target, predicted_value, probability) |>
    filter(!is.na(city_id))
  
  con2 <- DBI::dbConnect(
    RPostgres::Postgres(),
    dbname   = config$dbname,
    host     = config$host,
    port     = config$port,
    user     = config$user,
    password = config$password
  )
  
  DBI::dbWriteTable(con2, "predictions_staging", test_preds,
                    temporary = TRUE, overwrite = TRUE, row.names = FALSE)
  
  n_upserted <- DBI::dbExecute(con2, "
    INSERT INTO predictions
      (city_id, prediction_datetime, model_name, target, predicted_value, probability)
    SELECT city_id, prediction_datetime, model_name, target, predicted_value, probability
    FROM predictions_staging
    ON CONFLICT (city_id, prediction_datetime, model_name, target)
    DO UPDATE SET
      predicted_value = EXCLUDED.predicted_value,
      probability     = EXCLUDED.probability
  ")
  DBI::dbDisconnect(con2)
  cat(sprintf("  Predictions : %d lignes upsert\n", n_upserted))
}

# ============================================================
# 4. EXPORT DES METRIQUES CONSOLIDEES
# ============================================================

df_all_metrics <- bind_rows(all_metrics)
write.csv(df_all_metrics, "results/10_all_models_metrics.csv", row.names = FALSE)

message("\n========================================")
message("MODELE ML MULTI-INTEMPERIES TERMINE")
message("Tous les modeles (.rds compresses) et metriques exportes dans results/")
message("========================================")
