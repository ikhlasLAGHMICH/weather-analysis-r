# ============================================================
# model_helpers.R — Fonctions pures ML (testables independamment)
# Gills — feature/gills-ml-shiny
# ============================================================
# Ce fichier ne contient QUE des fonctions pures sans effets de bord.
# Il peut etre source() depuis 05_model.R, shiny/app.R et les tests.
# ============================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
})

# ============================================================
# 1. GESTION ENVIRONNEMENT
# ============================================================

#' Charge un fichier .env dans les variables d'environnement du process.
#' Les credentials ne sont jamais retournes ni loggues.
#' @param path Chemin vers le fichier .env
#' @return invisible(NULL)
load_env_file <- function(path = ".env") {
  if (!file.exists(path)) return(invisible(NULL))
  env_lines <- trimws(readLines(path, warn = FALSE))
  env_lines <- env_lines[nzchar(env_lines) & !startsWith(env_lines, "#")]
  for (line in env_lines) {
    sep <- regexpr("=", line, fixed = TRUE)
    if (sep > 1) {
      key   <- trimws(substr(line, 1, sep - 1))
      value <- trimws(substr(line, sep + 1, nchar(line)))
      value <- sub("^(['\"])(.*)\\1$", "\\2", value)
      if (!nzchar(Sys.getenv(key, unset = ""))) {
        do.call(Sys.setenv, setNames(list(value), key))
      }
    }
  }
  invisible(NULL)
}

#' Lit une variable d'environnement avec valeur par defaut optionnelle.
#' @param name Nom de la variable
#' @param default Valeur par defaut (NULL = obligatoire)
#' @return La valeur de la variable
get_env <- function(name, default = NULL) {
  value <- Sys.getenv(name, unset = "")
  if (!nzchar(value)) value <- default
  if (is.null(value) || !nzchar(value)) {
    stop("Variable d'environnement manquante : ", name, call. = FALSE)
  }
  value
}

# ============================================================
# 2. FEATURE ENGINEERING
# ============================================================

#' Convertit un numero de mois en saison.
#' @param month Vecteur entier de mois (1-12)
#' @return Vecteur character de saisons
assign_season <- function(month) {
  dplyr::case_when(
    month %in% c(12L, 1L, 2L) ~ "Winter",
    month %in% c(3L, 4L, 5L)  ~ "Spring",
    month %in% c(6L, 7L, 8L)  ~ "Summer",
    TRUE                       ~ "Autumn"
  )
}

# ============================================================
# 3. CIBLES METEO MULTIPLES (GENERATION DES FLAGS)
# ============================================================

#' Definition des 8 evenements meteo a predire.
#' Chaque entree contient :
#'   $label      : nom affiche en UI
#'   $icon       : emoji pour l'interface Shiny
#'   $col        : nom de la colonne flag dans le data.frame
#'   $create_fn  : function(daily_row) -> integer (0/1)
#'   $note       : note methodologique (proxy ou seuil officiel)
WEATHER_EVENTS <- list(

  rain = list(
    label     = "Pluie",
    icon      = "\U0001f327",
    col       = "rain_flag",
    note      = "precipitation_total > 1 mm (seuil OMM)",
    create_fn = function(d) as.integer(d$precipitation_total > 1)
  ),

  heavy_rain = list(
    label     = "Pluie forte",
    icon      = "\U0001f30a",
    col       = "heavy_rain_flag",
    note      = "precipitation_total > 20 mm (vigilance orange Meteo-France)",
    create_fn = function(d) as.integer(d$precipitation_total > 20)
  ),

  storm = list(
    label     = "Orage / Tempete",
    icon      = "\u26c8",
    col       = "storm_flag",
    note      = "wind_speed_max > 60 km/h (Beaufort 8 - tempete)",
    create_fn = function(d) as.integer(d$wind_speed_max > 60)
  ),

  snow = list(
    label     = "Neige",
    icon      = "\u2744",
    col       = "snow_flag",
    note      = "Proxy : temp_max < 3C ET precipitation_total > 0.5 mm",
    create_fn = function(d) {
      as.integer(d$temp_max < 3 & d$precipitation_total > 0.5)
    }
  ),

  frost = list(
    label     = "Gel",
    icon      = "\U0001f9ca",
    col       = "frost_flag",
    note      = "temp_min < 0C (gel au sol, seuil agronomique standard)",
    create_fn = function(d) as.integer(d$temp_min < 0)
  ),

  heatwave = list(
    label     = "Canicule",
    icon      = "\U0001f525",
    col       = "heatwave_flag",
    note      = "temp_max >= 33C (seuil vigilance Meteo-France canicule)",
    create_fn = function(d) as.integer(d$temp_max >= 33)
  ),

  fog = list(
    label     = "Brouillard",
    icon      = "\U0001f32b",
    col       = "fog_flag",
    note      = "Proxy : humidity_mean >= 90% ET wind_speed_mean < 5 km/h",
    create_fn = function(d) {
      as.integer(d$humidity_mean >= 90 & d$wind_speed_mean < 5)
    }
  ),

  drought_risk = list(
    label     = "Risque secheresse",
    icon      = "\U0001f4a7",
    col       = "drought_risk_flag",
    note      = "Proxy : temp_max > 28C ET precipitation_total < 1mm ET humidity_mean < 50%",
    create_fn = function(d) {
      as.integer(d$temp_max > 28 & d$precipitation_total < 1 & d$humidity_mean < 50)
    }
  )
)

#' Cree les colonnes de flags pour tous les evenements meteo definis.
#' @param daily data.frame avec les colonnes meteo de weather_daily
#' @return data.frame avec les colonnes *_flag ajoutees
create_multi_targets <- function(daily) {
  stopifnot(is.data.frame(daily))
  required <- c("precipitation_total", "wind_speed_max", "temp_max",
                 "temp_min", "humidity_mean", "wind_speed_mean")
  missing_cols <- setdiff(required, names(daily))
  if (length(missing_cols) > 0) {
    stop("Colonnes manquantes pour create_multi_targets : ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }
  for (event in WEATHER_EVENTS) {
    daily[[event$col]] <- event$create_fn(daily)
  }
  daily
}

# ============================================================
# 4. FEATURE ENGINEERING PAR CIBLE
# ============================================================

#' Applique le feature engineering pour une cible donnee.
#' Ajoute month, season, lags J-1, et la target lead(flag, 1).
#'
#' @param daily data.frame issu de weather_daily (deja enrichi par create_multi_targets)
#' @param flag_col character — nom de la colonne flag source (ex: "rain_flag")
#' @param city_order Vecteur des niveaux du facteur city
#' @param season_levels Vecteur des niveaux du facteur season
#' @return data.frame pret pour l'entrainement, avec colonne "target"
engineer_features <- function(
    daily,
    flag_col      = "rain_flag",
    city_order,
    season_levels = c("Winter", "Spring", "Summer", "Autumn")
) {
  required_base <- c("date", "city", "precipitation_total",
                     "pressure_mean", "humidity_mean", flag_col)
  stopifnot(
    is.data.frame(daily),
    all(required_base %in% names(daily))
  )

  daily <- daily |>
    dplyr::mutate(
      date   = as.Date(date),
      city   = factor(city, levels = city_order),
      month  = lubridate::month(date),
      season = assign_season(month),
      season = factor(season, levels = season_levels)
    )

  # Renommer le flag courant en "current_flag" pour les lags
  daily[["current_flag"]] <- daily[[flag_col]]

  daily <- daily |>
    dplyr::group_by(city) |>
    dplyr::arrange(date, .by_group = TRUE) |>
    dplyr::mutate(
      flag_lag1     = dplyr::lag(current_flag,       1L),
      precip_lag1   = dplyr::lag(precipitation_total, 1L),
      pressure_lag1 = dplyr::lag(pressure_mean,       1L),
      humidity_lag1 = dplyr::lag(humidity_mean,       1L),
      target        = dplyr::lead(current_flag,       1L)
    ) |>
    dplyr::ungroup()

  daily |>
    dplyr::filter(!is.na(target), !is.na(flag_lag1)) |>
    dplyr::mutate(
      target    = factor(target,    levels = c(0L, 1L), labels = c("No", "Yes")),
      flag_lag1 = as.integer(flag_lag1)
    )
}

# ============================================================
# 5. METRIQUES DE CLASSIFICATION
# ============================================================

#' Calcule les metriques de classification binaire.
#' @param actual   factor (levels = c("No","Yes")) — vraies etiquettes
#' @param predicted_class factor (levels = c("No","Yes")) — predictions
#' @param predicted_prob  numeric [0,1] — probabilites (optionnel, pour AUC)
#' @param model_name character — nom du modele pour le rapport
#' @return list avec accuracy, precision, recall, f1, auc, confusion_matrix
compute_metrics <- function(actual, predicted_class,
                             predicted_prob = NULL,
                             model_name = "Model") {
  stopifnot(
    is.factor(actual),
    is.factor(predicted_class),
    identical(levels(actual), c("No", "Yes")),
    length(actual) == length(predicted_class)
  )

  cm <- table(Predicted = predicted_class, Actual = actual)

  get_cell <- function(r, c) {
    if (r %in% rownames(cm) && c %in% colnames(cm)) as.integer(cm[r, c]) else 0L
  }

  tp <- get_cell("Yes", "Yes")
  tn <- get_cell("No",  "No")
  fp <- get_cell("Yes", "No")
  fn <- get_cell("No",  "Yes")
  n  <- tp + tn + fp + fn

  accuracy  <- (tp + tn) / n
  precision <- if ((tp + fp) > 0L) tp / (tp + fp) else NA_real_
  recall    <- if ((tp + fn) > 0L) tp / (tp + fn) else NA_real_
  f1 <- if (!is.na(precision) && !is.na(recall) && (precision + recall) > 0) {
    2 * precision * recall / (precision + recall)
  } else NA_real_

  auc_val <- NA_real_
  if (!is.null(predicted_prob) &&
      requireNamespace("pROC", quietly = TRUE) &&
      length(unique(actual)) == 2L) {
    roc_obj <- pROC::roc(actual, predicted_prob,
                         levels    = c("No", "Yes"),
                         direction = "<",
                         quiet     = TRUE)
    auc_val <- as.numeric(pROC::auc(roc_obj))
  }

  list(
    model_name       = model_name,
    accuracy         = round(accuracy,  4L),
    precision        = round(precision, 4L),
    recall           = round(recall,    4L),
    f1               = round(f1,        4L),
    auc              = round(auc_val,   4L),
    confusion_matrix = cm
  )
}

# ============================================================
# 6. INFERENCE — PREDICTION MULTI-INTEMPERIES
# ============================================================

#' Applique un modele sauvegarde sur de nouvelles donnees.
#' Fonctionne sans connexion DB — le bundle .rds est autosuffisant.
#'
#' @param model_bundle list issu de readRDS("results/<event>_model.rds")
#' @param new_data data.frame avec les features du jour J
#' @return list(probability = numeric, prediction = factor(No/Yes))
predict_weather_event <- function(model_bundle, new_data) {
  stopifnot(
    is.list(model_bundle),
    all(c("model", "model_name", "features", "threshold",
          "city_order", "season_levels") %in% names(model_bundle))
  )

  if ("city" %in% names(new_data)) {
    new_data$city <- factor(new_data$city, levels = model_bundle$city_order)
  }
  if ("season" %in% names(new_data)) {
    new_data$season <- factor(new_data$season, levels = model_bundle$season_levels)
  }

  model      <- model_bundle$model
  model_name <- model_bundle$model_name
  threshold  <- model_bundle$threshold

  prob <- if (grepl("Random Forest", model_name, fixed = TRUE)) {
    predict(model, data = new_data)$predictions[, "Yes"]
  } else {
    predict(model, newdata = new_data, type = "response")
  }

  pred_class <- factor(
    ifelse(prob >= threshold, "Yes", "No"),
    levels = c("No", "Yes")
  )

  list(probability = as.numeric(prob), prediction = pred_class)
}

# Alias retrocompatible (ancienne signature utilisee dans les tests)
predict_rain <- predict_weather_event

#' Charge tous les modeles disponibles dans results/.
#' @param results_dir Chemin vers le dossier results/
#' @return named list de bundles (noms = event keys)
load_all_models <- function(results_dir = "results") {
  bundles <- list()
  for (event_key in names(WEATHER_EVENTS)) {
    rds_path <- file.path(results_dir, paste0(event_key, "_model.rds"))
    if (file.exists(rds_path)) {
      bundles[[event_key]] <- readRDS(rds_path)
    }
  }
  bundles
}
