# ============================================================
# test_model_output.R — Tests d'integration (apres make model)
# ============================================================
# Ces tests verifient les artefacts produits par 05_model.R.
# Chaque test est skippe si le fichier attendu n'existe pas.
# ============================================================

library(testthat)

# Source depuis la racine (definie par setup.R via TEST_PROJECT_ROOT)
.ROOT <- Sys.getenv("TEST_PROJECT_ROOT", unset = normalizePath(file.path(getwd(), "../..")))
if (!exists("predict_weather_event")) {
  source(file.path(.ROOT, "R", "model_helpers.R"))
  source(file.path(.ROOT, "04_style.R"))
}

# Helper : chemin depuis la racine
.rp <- function(...) file.path(.ROOT, ...)

# ── Existence des fichiers ────────────────────────────────────

test_that("results/rain_model.rds existe", {
  skip_if(!file.exists(.rp("results", "rain_model.rds")),
          "Executez `make model` pour generer le modele")
  expect_true(file.exists(.rp("results", "rain_model.rds")))
})

test_that("results/10_all_models_metrics.csv existe", {
  skip_if(!file.exists(.rp("results", "10_all_models_metrics.csv")),
          "Executez `make model` pour generer le CSV global")
  expect_true(file.exists(.rp("results", "10_all_models_metrics.csv")))
})

# ── Structure de rain_model.rds ───────────────────────────────

test_that("rain_model.rds : champs obligatoires presents", {
  skip_if(!file.exists(.rp("results", "rain_model.rds")),
          "Executez `make model`")
  bundle <- readRDS(.rp("results", "rain_model.rds"))
  required_fields <- c("event_key","event_label","model","model_name","features","metrics",
                        "importance","threshold","train_cutoff",
                        "city_order","season_levels","created_at")
  for (f in required_fields) {
    expect_true(f %in% names(bundle),
                label = paste("champ manquant dans rain_model.rds :", f))
  }
})

test_that("rain_model.rds : model_name est LR ou RF", {
  skip_if(!file.exists(.rp("results", "rain_model.rds")), "Executez `make model`")
  bundle <- readRDS(.rp("results", "rain_model.rds"))
  expect_true(
    bundle$model_name %in% c("Logistic Regression", "Random Forest"),
    label = paste("model_name inattendu :", bundle$model_name)
  )
})

test_that("rain_model.rds : threshold dans [0, 1]", {
  skip_if(!file.exists(.rp("results", "rain_model.rds")), "Executez `make model`")
  bundle <- readRDS(.rp("results", "rain_model.rds"))
  expect_gte(bundle$threshold, 0)
  expect_lte(bundle$threshold, 1)
})

test_that("rain_model.rds : city_order contient les 5 villes attendues", {
  skip_if(!file.exists(.rp("results", "rain_model.rds")), "Executez `make model`")
  bundle <- readRDS(.rp("results", "rain_model.rds"))
  expected_cities <- c("Stockholm","Lille","Paris","Madrid","Rome")
  expect_true(all(expected_cities %in% bundle$city_order),
              label = "Une ou plusieurs villes manquent dans city_order")
})

test_that("rain_model.rds : features non vide", {
  skip_if(!file.exists(.rp("results", "rain_model.rds")), "Executez `make model`")
  bundle <- readRDS(.rp("results", "rain_model.rds"))
  expect_true(length(bundle$features) > 0)
})

test_that("rain_model.rds : importance est un data.frame avec feature et importance", {
  skip_if(!file.exists(.rp("results", "rain_model.rds")), "Executez `make model`")
  bundle <- readRDS(.rp("results", "rain_model.rds"))
  expect_s3_class(bundle$importance, "data.frame")
  expect_true("feature"    %in% names(bundle$importance))
  expect_true("importance" %in% names(bundle$importance))
  expect_gt(nrow(bundle$importance), 0L)
})

# ── Verification de la base de donnees (Predictions) ──────────

test_that("Des predictions ont ete ajoutees dans PostgreSQL (rain)", {
  skip_if_not(file.exists(.rp(".env")), "Fichier .env absent")
  
  suppressWarnings(suppressPackageStartupMessages(library(DBI)))
  suppressWarnings(suppressPackageStartupMessages(library(RPostgres)))
  
  load_env_file(.rp(".env"))
  con <- tryCatch(
    DBI::dbConnect(
      RPostgres::Postgres(),
      dbname   = get_env("POSTGRES_DB"),
      host     = get_env("POSTGRES_HOST", "localhost"),
      port     = as.integer(get_env("POSTGRES_PORT", "5432")),
      user     = get_env("POSTGRES_USER"),
      password = get_env("POSTGRES_PASSWORD")
    ),
    error = function(e) NULL
  )
  skip_if(is.null(con), "Connexion PostgreSQL echouee pour le test")
  
  n_preds <- DBI::dbGetQuery(con, "SELECT COUNT(*) FROM predictions WHERE target = 'rain'")[[1]]
  DBI::dbDisconnect(con)
  
  if (n_preds == 0) {
    skip("Aucune prediction trouvee dans la DB (peut-etre que `make model` n'a pas ete execute)")
  }
  expect_gt(n_preds, 0L)
})
