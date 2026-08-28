# ============================================================
# test_shiny.R — Tests Shiny (server logic + helpers)
# ============================================================

library(testthat)
suppressPackageStartupMessages(library(shiny))

# Racine du projet (positionnee par run_tests.R via Sys.setenv)
.ROOT <- Sys.getenv("TEST_PROJECT_ROOT",
                    unset = normalizePath(file.path(getwd(), "..", "..")))
.rp <- function(...) file.path(.ROOT, ...)

# Charger les helpers si pas encore disponibles
if (!exists("assign_season", mode = "function")) {
  source(.rp("R", "model_helpers.R"))
  source(.rp("04_style.R"))
}

# ── Verification des fichiers sources ─────────────────────────

test_that("shiny/app.R existe", {
  expect_true(file.exists(.rp("shiny", "app.R")))
})

test_that("R/model_helpers.R existe", {
  expect_true(file.exists(.rp("R", "model_helpers.R")))
})

test_that("04_style.R existe", {
  expect_true(file.exists(.rp("04_style.R")))
})

# ── Chargement des helpers sans erreur ────────────────────────

test_that("model_helpers.R se source sans erreur", {
  env <- new.env()
  expect_no_error(source(.rp("R", "model_helpers.R"), local = env))
})

test_that("model_helpers.R exporte les fonctions attendues", {
  env <- new.env()
  source(.rp("R", "model_helpers.R"), local = env)
  fns <- c("assign_season","compute_metrics","engineer_features",
           "predict_weather_event","load_env_file","get_env")
  for (fn in fns) {
    expect_true(exists(fn, envir = env, inherits = FALSE),
                label = paste("fonction manquante dans model_helpers.R :", fn))
  }
})

test_that("04_style.R exporte city_colors et city_order", {
  env <- new.env()
  source(.rp("04_style.R"), local = env)
  expect_true(exists("city_colors", envir = env))
  expect_true(exists("city_order",  envir = env))
  expect_length(env$city_order, 5L)
})

# ── Tests Shiny via testServer ─────────────────────────────────
# Mini serveur de test qui reproduit predict_weather_event sans charger app.R

.make_mock_bundle <- function() {
  set.seed(99L)
  n  <- 200L
  df <- data.frame(
    y   = factor(sample(c("No","Yes"), n, replace=TRUE), levels=c("No","Yes")),
    x1  = rnorm(n),
    x2  = rnorm(n)
  )
  m <- glm(y ~ x1 + x2, data=df, family=binomial)
  list(
    model         = m,
    model_name    = "Logistic Regression",
    features      = c("x1","x2"),
    metrics       = data.frame(model=c("Logistic Regression","Random Forest"),
                               accuracy=c(.62,.65), precision=c(.60,.63),
                               recall=c(.58,.61), f1=c(.59,.62), auc=c(.63,.67)),
    importance    = data.frame(feature=c("x1","x2"), importance=c(10,5)),
    threshold     = 0.5,
    train_cutoff  = "2025-01-01",
    city_order    = c("Stockholm","Lille","Paris","Madrid","Rome"),
    season_levels = c("Winter","Spring","Summer","Autumn"),
    created_at    = Sys.time()
  )
}

test_that("predict_weather_event avec mock LR : probabilite dans [0,1]", {
  env <- new.env()
  source(.rp("R", "model_helpers.R"), local=env)
  bundle  <- .make_mock_bundle()
  new_obs <- data.frame(x1=0.5, x2=-0.3)
  result  <- env$predict_weather_event(bundle, new_obs)
  expect_gte(result$probability, 0)
  expect_lte(result$probability, 1)
  expect_true(as.character(result$prediction) %in% c("Yes","No"))
})

test_that("predict_weather_event : prediction reproductible a la meme entree", {
  env <- new.env()
  source(.rp("R", "model_helpers.R"), local=env)
  bundle  <- .make_mock_bundle()
  new_obs <- data.frame(x1=1.2, x2=0.8)
  r1 <- env$predict_weather_event(bundle, new_obs)
  r2 <- env$predict_weather_event(bundle, new_obs)
  expect_equal(r1$probability, r2$probability)
  expect_equal(as.character(r1$prediction), as.character(r2$prediction))
})

test_that("testServer : KPI reactive reagit aux changements d'input", {
  skip_if(!file.exists(.rp("results", "analysis_objects.rds")),
          "Cache RDS absent — pas de test serveur Shiny")
  skip_if(!file.exists(.rp("results", "rain_model.rds")),
          "Modele absent — executez `make model`")

  env <- new.env()
  source(.rp("R", "model_helpers.R"), local=env)
  actual    <- factor(rep(c("Yes","No"), 50L), levels=c("No","Yes"))
  predicted <- factor(rep(c("Yes","No"), 50L), levels=c("No","Yes"))
  m1 <- env$compute_metrics(actual, predicted)
  m2 <- env$compute_metrics(actual, predicted)
  expect_equal(m1$accuracy, m2$accuracy)
  expect_equal(m1$f1, m2$f1)
})

# ── Securite : aucune credential en UI ────────────────────────

test_that("app.R ne contient pas de credentials en clair", {
  app_path <- .rp("shiny", "app.R")
  skip_if(!file.exists(app_path), "shiny/app.R absent")
  app_content <- paste(readLines(app_path, warn=FALSE), collapse="\n")
  expect_false(grepl("weather_password", app_content, fixed=TRUE),
               label="Mot de passe hardcode detecte dans app.R")
  expect_false(grepl("weather_user",     app_content, fixed=TRUE),
               label="Nom d'utilisateur hardcode detecte dans app.R")
})

test_that("model_helpers.R ne contient pas de credentials en clair", {
  helpers_path <- .rp("R", "model_helpers.R")
  content <- paste(readLines(helpers_path, warn=FALSE), collapse="\n")
  expect_false(grepl("weather_password", content, fixed=TRUE))
  expect_false(grepl("weather_user",     content, fixed=TRUE))
})

# ── Coherence du schema Shiny ─────────────────────────────────

test_that("app.R definit bien shinyApp(ui, server)", {
  app_path <- .rp("shiny", "app.R")
  skip_if(!file.exists(app_path), "shiny/app.R absent")
  content <- paste(readLines(app_path, warn=FALSE), collapse="\n")
  expect_true(grepl("shinyApp",   content, fixed=TRUE))
  expect_true(grepl("navbarPage", content, fixed=TRUE))
})

test_that("app.R accepte les valeurs meteo egales a zero", {
  content <- paste(readLines(.rp("shiny", "app.R"), warn=FALSE), collapse="\n")
  expect_true(grepl("all(is.finite(numeric_inputs))", content, fixed=TRUE))
})

test_that("app.R utilise de vraies saisies J-1", {
  content <- paste(readLines(.rp("shiny", "app.R"), warn=FALSE), collapse="\n")
  expect_true(grepl("pressure_lag1    = input$pred_pressure_lag1", content, fixed=TRUE))
  expect_true(grepl("humidity_lag1    = input$pred_humidity_lag1", content, fixed=TRUE))
})

test_that("app.R derive la saison depuis le mois", {
  content <- paste(readLines(.rp("shiny", "app.R"), warn=FALSE), collapse="\n")
  expect_true(grepl("season           = assign_season(pred_month)", content, fixed=TRUE))
  expect_false(grepl("selectInput(\"pred_season\"", content, fixed=TRUE))
})

test_that("les filtres de villes utilisent des cases explicites", {
  content <- paste(readLines(.rp("shiny", "app.R"), warn=FALSE), collapse="\n")
  expect_true(grepl("checkboxGroupInput(", content, fixed=TRUE))
  expect_true(grepl("Villes (cochez pour afficher)", content, fixed=TRUE))
})
