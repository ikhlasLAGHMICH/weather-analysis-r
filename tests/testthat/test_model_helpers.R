# ============================================================
# test_model_helpers.R — Tests unitaires des fonctions pures
# ============================================================
# run_tests.R garantit setwd(<racine>) avant d'appeler test_dir().
# On peut donc sourcer avec des chemins relatifs a la racine.
# ============================================================

library(testthat)
suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
})

# Source depuis la racine (definie par setup.R via TEST_PROJECT_ROOT)
.ROOT <- Sys.getenv("TEST_PROJECT_ROOT", unset = normalizePath(file.path(getwd(), "../..")))
if (!exists("assign_season")) {
  source(file.path(.ROOT, "R", "model_helpers.R"))
  source(file.path(.ROOT, "04_style.R"))
}

# ── create_multi_targets ──────────────────────────────────────

test_that("create_multi_targets ajoute bien toutes les cibles attendues", {
  daily <- data.frame(
    precipitation_total = c(0, 2, 25, 0),
    wind_speed_max      = c(10, 20, 70, 5),
    temp_max            = c(10, 2, 25, 35),
    temp_min            = c(5, -2, 15, 20),
    humidity_mean       = c(50, 60, 80, 95),
    wind_speed_mean     = c(5, 10, 30, 2)
  )
  res <- create_multi_targets(daily)
  expect_true("rain_flag" %in% names(res))
  expect_true("heavy_rain_flag" %in% names(res))
  expect_true("storm_flag" %in% names(res))
  expect_true("snow_flag" %in% names(res))
  expect_true("frost_flag" %in% names(res))
  expect_true("heatwave_flag" %in% names(res))
  expect_true("fog_flag" %in% names(res))
  expect_true("drought_risk_flag" %in% names(res))
  
  expect_equal(res$heatwave_flag, c(0, 0, 0, 1))
})

# ── assign_season ─────────────────────────────────────────────

test_that("assign_season : Hiver en decembre, janvier, fevrier", {
  expect_equal(assign_season(12L), "Winter")
  expect_equal(assign_season(1L),  "Winter")
  expect_equal(assign_season(2L),  "Winter")
})

test_that("assign_season : Printemps en mars, avril, mai", {
  expect_equal(assign_season(3L), "Spring")
  expect_equal(assign_season(4L), "Spring")
  expect_equal(assign_season(5L), "Spring")
})

test_that("assign_season : Ete en juin, juillet, aout", {
  expect_equal(assign_season(6L), "Summer")
  expect_equal(assign_season(7L), "Summer")
  expect_equal(assign_season(8L), "Summer")
})

test_that("assign_season : Automne en septembre, octobre, novembre", {
  expect_equal(assign_season(9L),  "Autumn")
  expect_equal(assign_season(10L), "Autumn")
  expect_equal(assign_season(11L), "Autumn")
})

test_that("assign_season : tous les mois couverts", {
  seasons <- assign_season(1:12)
  expect_true(all(seasons %in% c("Winter", "Spring", "Summer", "Autumn")))
  expect_equal(length(seasons), 12L)
})

test_that("assign_season : vectoriel avec mois melanges", {
  res <- assign_season(c(1L, 4L, 7L, 10L))
  expect_equal(res, c("Winter", "Spring", "Summer", "Autumn"))
})

# ── compute_metrics ───────────────────────────────────────────

test_that("compute_metrics : structure de retour correcte", {
  actual    <- factor(c("Yes","No","Yes","No"), levels=c("No","Yes"))
  predicted <- factor(c("Yes","No","No","No"), levels=c("No","Yes"))
  m <- compute_metrics(actual, predicted, model_name="TestModel")

  expect_type(m, "list")
  expect_named(m,
    c("model_name","accuracy","precision","recall","f1","auc","confusion_matrix"),
    ignore.order = FALSE
  )
  expect_equal(m$model_name, "TestModel")
})

test_that("compute_metrics : accuracy correcte (cas simple)", {
  # 3 bonnes predictions sur 4
  actual    <- factor(c("Yes","No","Yes","No"), levels=c("No","Yes"))
  predicted <- factor(c("Yes","No","No","No"), levels=c("No","Yes"))
  # TP=1 TN=2 FP=0 FN=1 → accuracy=3/4=0.75
  m <- compute_metrics(actual, predicted)
  expect_equal(m$accuracy, 0.75)
})

test_that("compute_metrics : precision et recall corrects", {
  # TP=2 TN=2 FP=1 FN=1
  actual    <- factor(c("Yes","Yes","No","No","Yes","No"), levels=c("No","Yes"))
  predicted <- factor(c("Yes","No","Yes","No","Yes","No"), levels=c("No","Yes"))
  m <- compute_metrics(actual, predicted)
  # precision = 2/(2+1) = 0.6667
  # recall    = 2/(2+1) = 0.6667
  expect_equal(m$precision, round(2/3, 4))
  expect_equal(m$recall,    round(2/3, 4))
})

test_that("compute_metrics : F1 = 1 pour prediction parfaite", {
  actual    <- factor(c("Yes","Yes","No","No"), levels=c("No","Yes"))
  predicted <- factor(c("Yes","Yes","No","No"), levels=c("No","Yes"))
  m <- compute_metrics(actual, predicted)
  expect_equal(m$accuracy,  1)
  expect_equal(m$precision, 1)
  expect_equal(m$recall,    1)
  expect_equal(m$f1,        1)
})

test_that("compute_metrics : valeurs dans [0, 1]", {
  set.seed(1L)
  n     <- 100L
  actual    <- factor(sample(c("No","Yes"), n, replace=TRUE), levels=c("No","Yes"))
  predicted <- factor(sample(c("No","Yes"), n, replace=TRUE), levels=c("No","Yes"))
  m <- compute_metrics(actual, predicted)
  expect_gte(m$accuracy, 0); expect_lte(m$accuracy, 1)
  if (!is.na(m$precision)) { expect_gte(m$precision, 0); expect_lte(m$precision, 1) }
  if (!is.na(m$recall))    { expect_gte(m$recall,    0); expect_lte(m$recall,    1) }
  if (!is.na(m$f1))        { expect_gte(m$f1,        0); expect_lte(m$f1,        1) }
})

test_that("compute_metrics : erreur si actual n'est pas factor", {
  actual    <- c("Yes","No","Yes")         # character, pas factor
  predicted <- factor(c("Yes","No","Yes"), levels=c("No","Yes"))
  expect_error(compute_metrics(actual, predicted))
})

test_that("compute_metrics : erreur si levels incorrects", {
  actual    <- factor(c("1","0","1"), levels=c("0","1"))  # levels != c("No","Yes")
  predicted <- factor(c("1","0","0"), levels=c("0","1"))
  expect_error(compute_metrics(actual, predicted))
})

test_that("compute_metrics : AUC NA si predicted_prob absent", {
  actual    <- factor(c("Yes","No","Yes","No"), levels=c("No","Yes"))
  predicted <- factor(c("Yes","No","No","No"), levels=c("No","Yes"))
  m <- compute_metrics(actual, predicted, predicted_prob=NULL)
  expect_true(is.na(m$auc))
})

test_that("optimize_f1_threshold : retourne un seuil valide", {
  actual <- factor(c("No", "No", "Yes", "Yes"), levels=c("No", "Yes"))
  probabilities <- c(0.1, 0.4, 0.45, 0.9)
  threshold <- optimize_f1_threshold(actual, probabilities)
  expect_gte(threshold, 0)
  expect_lte(threshold, 1)
})

test_that("optimize_f1_threshold : fallback pour une seule classe", {
  actual <- factor(rep("No", 4), levels=c("No", "Yes"))
  expect_equal(optimize_f1_threshold(actual, c(0.1, 0.2, 0.3, 0.4)), 0.5)
})

# ── engineer_features ─────────────────────────────────────────

.make_synthetic_daily <- function(n = 20L, city = "Paris") {
  set.seed(42L)
  data.frame(
    date                = seq(as.Date("2021-01-01"), by="day", length.out=n),
    city                = city,
    temp_min            = runif(n, -5, 10),
    temp_max            = runif(n, 10, 25),
    temp_mean           = runif(n,  5, 18),
    humidity_mean       = runif(n, 40, 95),
    precipitation_total = runif(n,  0, 15),
    rain_total          = runif(n,  0,  8),
    pressure_mean       = runif(n, 995, 1025),
    cloud_cover_mean    = runif(n,  0, 100),
    wind_speed_mean     = runif(n,  0, 30),
    wind_speed_max      = runif(n,  5, 60),
    rain_flag           = sample(0:1, n, replace=TRUE),
    stringsAsFactors    = FALSE
  )
}

test_that("engineer_features : colonnes attendues presentes", {
  d <- .make_synthetic_daily()
  co <- c("Stockholm","Lille","Paris","Madrid","Rome")
  result <- engineer_features(d, flag_col = "rain_flag", city_order = co)

  expected_cols <- c("flag_lag1", "precip_lag1", "pressure_lag1",
                     "humidity_lag1", "target", "season", "month")
  for (col in expected_cols) {
    expect_true(col %in% names(result), label = paste("colonne manquante :", col))
  }
})

test_that("engineer_features : target est factor No/Yes", {
  d <- .make_synthetic_daily()
  co <- c("Stockholm","Lille","Paris","Madrid","Rome")
  result <- engineer_features(d, flag_col = "rain_flag", city_order = co)
  expect_s3_class(result$target, "factor")
  expect_equal(levels(result$target), c("No", "Yes"))
})

test_that("engineer_features : moins de lignes que l'entree (lag+lead suppression)", {
  n  <- 20L
  d  <- .make_synthetic_daily(n)
  co <- c("Stockholm","Lille","Paris","Madrid","Rome")
  result <- engineer_features(d, flag_col = "rain_flag", city_order = co)
  # Premier et dernier jour enleves par NA lag/lead → n - 2 au maximum
  expect_lt(nrow(result), n)
})

test_that("engineer_features : erreur si colonnes obligatoires manquantes", {
  d  <- .make_synthetic_daily()
  d  <- d[, !names(d) %in% "rain_flag"]   # on retire rain_flag
  co <- c("Stockholm","Lille","Paris","Madrid","Rome")
  expect_error(engineer_features(d, flag_col = "rain_flag", city_order = co))
})

test_that("engineer_features : city est factor avec les bons niveaux", {
  d  <- .make_synthetic_daily()
  co <- c("Stockholm","Lille","Paris","Madrid","Rome")
  result <- engineer_features(d, flag_col = "rain_flag", city_order = co)
  expect_s3_class(result$city, "factor")
  expect_true(all(levels(result$city) == co))
})

# ── load_env_file ─────────────────────────────────────────────

test_that("load_env_file : retourne NULL si fichier absent", {
  result <- load_env_file("fichier_inexistant_xyz.env")
  expect_null(result)
})

test_that("load_env_file : charge les variables correctement", {
  tmp <- tempfile(fileext = ".env")
  writeLines(c("TEST_VAR_ML=hello_test_42", "# un commentaire", ""), tmp)
  on.exit({ Sys.unsetenv("TEST_VAR_ML"); file.remove(tmp) })

  # S'assurer que la variable n'est pas deja definie
  Sys.unsetenv("TEST_VAR_ML")
  load_env_file(tmp)
  expect_equal(Sys.getenv("TEST_VAR_ML"), "hello_test_42")
})

test_that("load_env_file : ne remplace pas une variable deja definie", {
  tmp <- tempfile(fileext = ".env")
  writeLines("TEST_EXISTING_VAR=new_value", tmp)
  on.exit({ Sys.unsetenv("TEST_EXISTING_VAR"); file.remove(tmp) })

  Sys.setenv(TEST_EXISTING_VAR = "original_value")
  load_env_file(tmp)
  expect_equal(Sys.getenv("TEST_EXISTING_VAR"), "original_value")
})

# ── get_env ───────────────────────────────────────────────────

test_that("get_env : retourne la valeur si la variable existe", {
  Sys.setenv(TEST_GET_ENV_VAR = "test_value_123")
  on.exit(Sys.unsetenv("TEST_GET_ENV_VAR"))
  expect_equal(get_env("TEST_GET_ENV_VAR"), "test_value_123")
})

test_that("get_env : utilise le default si variable absente", {
  Sys.unsetenv("TEST_ABSENT_VAR_9999")
  expect_equal(get_env("TEST_ABSENT_VAR_9999", default = "fallback"), "fallback")
})

test_that("get_env : stop si variable absente et pas de default", {
  Sys.unsetenv("TEST_REQUIRED_VAR_9999")
  expect_error(get_env("TEST_REQUIRED_VAR_9999"), regexp = "manquante")
})
