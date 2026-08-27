# ============================================================
# run_tests.R — Runner des tests automatises
# Usage : Rscript tests/run_tests.R
#         (depuis la racine du projet)
# ============================================================

# 1. Detecter la racine du projet
.root <- tryCatch({
  args <- commandArgs(trailingOnly = FALSE)
  farg <- grep("--file=", args, value = TRUE)
  if (length(farg) > 0) {
    script_dir <- normalizePath(dirname(sub("--file=", "", farg[1])))
    if (basename(script_dir) == "tests") dirname(script_dir) else script_dir
  } else {
    getwd()
  }
}, error = function(e) getwd())

setwd(.root)

# 2. Exposer la racine via variable d'environnement
# (visible dans chaque fichier test_*.R via Sys.getenv)
Sys.setenv(TEST_PROJECT_ROOT = .root)
cat(sprintf("[run_tests] Racine : %s\n", .root))

# 3. Packages
suppressPackageStartupMessages({
  library(testthat)
  library(dplyr)
  library(lubridate)
})

cat("=============================================\n")
cat("TESTS AUTOMATISES - Gills (ML + Shiny)\n")
cat("=============================================\n\n")

# 4. Lancer les tests sans charger les helpers via testthat
#    (chaque test_*.R se charge lui-meme)
results <- test_dir(
  path             = file.path(.root, "tests", "testthat"),
  reporter         = "summary",
  load_helpers     = FALSE,   # evite l'env verrouille de testthat
  stop_on_failure  = FALSE,
  stop_on_warning  = FALSE
)

df       <- as.data.frame(results)
n_tests  <- sum(df$nb)
n_failed <- sum(df$failed)
n_errors <- sum(df$error)
n_passed <- n_tests - n_failed - n_errors
n_skip   <- sum(df$skipped)

cat("\n=============================================\n")
cat(sprintf("Total    : %d tests\n",     n_tests))
cat(sprintf("Passes   : %d\n",           n_passed))
cat(sprintf("Echecs   : %d\n",           n_failed))
cat(sprintf("Erreurs  : %d\n",           n_errors))
cat(sprintf("Ignores  : %d (skip_if)\n", n_skip))
cat("---------------------------------------------\n")
if (n_failed == 0 && n_errors == 0) {
  cat("RESULTAT : TOUS LES TESTS PASSENT\n")
} else {
  cat("RESULTAT : DES TESTS ECHOUENT\n")
}
cat("=============================================\n")

if (n_failed > 0 || n_errors > 0) quit(status = 1L)
