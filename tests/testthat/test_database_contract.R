library(testthat)

.ROOT <- Sys.getenv(
  "TEST_PROJECT_ROOT",
  unset = normalizePath(file.path(getwd(), "..", ".."))
)
.rp <- function(...) file.path(.ROOT, ...)

test_that("l'import SQL est transactionnel", {
  content <- paste(readLines(.rp("R", "03_database.R"), warn = FALSE), collapse = "\n")
  expect_true(grepl("DBI::dbBegin(con)", content, fixed = TRUE))
  expect_true(grepl("DBI::dbCommit(con)", content, fixed = TRUE))
  expect_true(grepl("DBI::dbRollback(con)", content, fixed = TRUE))
})

test_that("PostgreSQL n'utilise pas le mode trust", {
  content <- paste(readLines(.rp("docker-compose.yml"), warn = FALSE), collapse = "\n")
  expect_false(grepl("POSTGRES_HOST_AUTH_METHOD=trust", content, fixed = TRUE))
})

test_that("les connexions principales ont un timeout", {
  database <- paste(readLines(.rp("R", "03_database.R"), warn = FALSE), collapse = "\n")
  model <- paste(readLines(.rp("R", "05_model.R"), warn = FALSE), collapse = "\n")
  app <- paste(readLines(.rp("shiny", "app.R"), warn = FALSE), collapse = "\n")
  expect_true(grepl("connect_timeout = 5L", database, fixed = TRUE))
  expect_true(grepl("connect_timeout = 5L", model, fixed = TRUE))
  expect_true(grepl("connect_timeout = 5L", app, fixed = TRUE))
})
