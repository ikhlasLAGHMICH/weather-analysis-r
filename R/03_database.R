#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
})

csv_path <- "data/processed/weather_clean.csv"
required_columns <- c(
  "datetime", "temperature_2m", "relative_humidity_2m", "precipitation",
  "rain", "surface_pressure", "cloud_cover", "wind_speed_10m",
  "wind_direction_10m", "city", "latitude", "longitude", "date", "year",
  "month", "day", "hour", "season", "rain_flag"
)

get_env <- function(name, default = NULL) {
  value <- Sys.getenv(name, unset = "")
  if (!nzchar(value)) value <- default
  if (is.null(value) || !nzchar(value)) {
    stop("Variable d'environnement manquante : ", name, call. = FALSE)
  }
  value
}

# Docker Compose lit .env automatiquement, contrairement à Rscript.
# Les variables déjà exportées gardent la priorité sur le fichier local.
if (file.exists(".env")) {
  env_lines <- trimws(readLines(".env", warn = FALSE))
  env_lines <- env_lines[nzchar(env_lines) & !startsWith(env_lines, "#")]
  for (line in env_lines) {
    separator <- regexpr("=", line, fixed = TRUE)
    if (separator > 1) {
      key <- trimws(substr(line, 1, separator - 1))
      value <- trimws(substr(line, separator + 1, nchar(line)))
      value <- sub("^(['\"])(.*)\\1$", "\\2", value)
      if (!nzchar(Sys.getenv(key, unset = ""))) do.call(Sys.setenv, setNames(list(value), key))
    }
  }
}

if (!file.exists(csv_path)) {
  stop("Fichier introuvable : ", csv_path, ". Exécutez d'abord `make data`.", call. = FALSE)
}

config <- list(
  dbname = get_env("POSTGRES_DB"),
  user = get_env("POSTGRES_USER"),
  password = get_env("POSTGRES_PASSWORD"),
  host = get_env("POSTGRES_HOST", "localhost"),
  port = as.integer(get_env("POSTGRES_PORT", "5432"))
)

message("Lecture de ", csv_path, "...")
weather <- read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE)
missing_columns <- setdiff(required_columns, names(weather))
if (length(missing_columns) > 0) {
  stop("Colonnes obligatoires absentes : ", paste(missing_columns, collapse = ", "), call. = FALSE)
}

weather <- weather[required_columns]
midnight <- nchar(weather$datetime) == 10
weather$datetime[midnight] <- paste(weather$datetime[midnight], "00:00:00")
weather$datetime <- as.POSIXct(weather$datetime, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
weather$date <- as.Date(weather$date)
if (anyNA(weather)) stop("Le CSV contient des valeurs manquantes.", call. = FALSE)
if (anyDuplicated(weather[c("city", "datetime")])) {
  stop("Le CSV contient des doublons sur (city, datetime).", call. = FALSE)
}

city_source <- unique(weather[c("city", "latitude", "longitude")])
if (anyDuplicated(city_source$city)) {
  stop("Une ville possède plusieurs couples latitude/longitude dans le CSV.", call. = FALSE)
}

con <- dbConnect(
  RPostgres::Postgres(), dbname = config$dbname, host = config$host,
  port = config$port, user = config$user, password = config$password
)
on.exit(if (dbIsValid(con)) dbDisconnect(con), add = TRUE)

required_tables <- c("cities", "weather_hourly", "weather_daily", "predictions")
missing_tables <- setdiff(required_tables, dbListTables(con))
if (length(missing_tables) > 0) {
  stop("Tables absentes : ", paste(missing_tables, collapse = ", "),
       ". Exécutez `make db-schema`.", call. = FALSE)
}

message("Import transactionnel vers PostgreSQL...")
invisible(dbWithTransaction(con, {
  for (i in seq_len(nrow(city_source))) {
    dbExecute(con, paste(
      "INSERT INTO cities (name, latitude, longitude) VALUES ($1, $2, $3)",
      "ON CONFLICT (name) DO UPDATE SET latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude"
    ), params = unname(as.list(city_source[i, ])))
  }

  city_map <- dbGetQuery(con, "SELECT city_id, name FROM cities")
  weather$city_id <- city_map$city_id[match(weather$city, city_map$name)]
  if (anyNA(weather$city_id)) stop("Correspondance city_id incomplète.", call. = FALSE)

  hourly <- weather[c(
    "city_id", "datetime", "temperature_2m", "relative_humidity_2m",
    "precipitation", "rain", "surface_pressure", "cloud_cover",
    "wind_speed_10m", "wind_direction_10m", "year", "month", "day",
    "hour", "season", "rain_flag"
  )]

  dbWriteTable(con, "weather_hourly_staging", hourly,
               temporary = TRUE, overwrite = TRUE, row.names = FALSE)

  dbExecute(con, paste(
    "INSERT INTO weather_hourly (city_id, datetime, temperature_2m, relative_humidity_2m,",
    " precipitation, rain, surface_pressure, cloud_cover, wind_speed_10m, wind_direction_10m,",
    " year, month, day, hour, season, rain_flag)",
    "SELECT city_id, datetime, temperature_2m, relative_humidity_2m, precipitation, rain,",
    " surface_pressure, cloud_cover, wind_speed_10m, wind_direction_10m, year, month, day,",
    " hour, season, rain_flag FROM weather_hourly_staging",
    "ON CONFLICT (city_id, datetime) DO UPDATE SET",
    " temperature_2m = EXCLUDED.temperature_2m, relative_humidity_2m = EXCLUDED.relative_humidity_2m,",
    " precipitation = EXCLUDED.precipitation, rain = EXCLUDED.rain,",
    " surface_pressure = EXCLUDED.surface_pressure, cloud_cover = EXCLUDED.cloud_cover,",
    " wind_speed_10m = EXCLUDED.wind_speed_10m, wind_direction_10m = EXCLUDED.wind_direction_10m,",
    " year = EXCLUDED.year, month = EXCLUDED.month, day = EXCLUDED.day, hour = EXCLUDED.hour,",
    " season = EXCLUDED.season, rain_flag = EXCLUDED.rain_flag"
  ))

  # rain_flag journalier vaut 1 dès qu'au moins une heure du jour est pluvieuse.
  dbExecute(con, "DELETE FROM weather_daily")
  dbExecute(con, paste(
    "INSERT INTO weather_daily (city_id, date, temp_min, temp_max, temp_mean, humidity_mean,",
    " precipitation_total, rain_total, pressure_mean, cloud_cover_mean, wind_speed_mean,",
    " wind_speed_max, rain_flag)",
    "SELECT city_id, datetime::date, MIN(temperature_2m), MAX(temperature_2m), AVG(temperature_2m),",
    " AVG(relative_humidity_2m), SUM(precipitation), SUM(rain), AVG(surface_pressure),",
    " AVG(cloud_cover), AVG(wind_speed_10m), MAX(wind_speed_10m), MAX(rain_flag)",
    "FROM weather_hourly GROUP BY city_id, datetime::date"
  ))
}))

scalar <- function(sql) dbGetQuery(con, sql)[[1]][1]
checks <- c(
  cities = scalar("SELECT COUNT(*) FROM cities"),
  weather_hourly = scalar("SELECT COUNT(*) FROM weather_hourly"),
  weather_daily = scalar("SELECT COUNT(*) FROM weather_daily"),
  hourly_duplicates = scalar(paste(
    "SELECT COUNT(*) FROM (SELECT city_id, datetime FROM weather_hourly",
    "GROUP BY city_id, datetime HAVING COUNT(*) > 1) d"
  )),
  orphan_city_ids = scalar(paste(
    "SELECT COUNT(*) FROM weather_hourly h LEFT JOIN cities c USING (city_id)",
    "WHERE c.city_id IS NULL"
  )),
  invalid_humidity = scalar("SELECT COUNT(*) FROM weather_hourly WHERE relative_humidity_2m NOT BETWEEN 0 AND 100"),
  invalid_cloud_cover = scalar("SELECT COUNT(*) FROM weather_hourly WHERE cloud_cover NOT BETWEEN 0 AND 100"),
  invalid_values = scalar(paste(
    "SELECT COUNT(*) FROM weather_hourly WHERE wind_direction_10m NOT BETWEEN 0 AND 360",
    "OR wind_speed_10m < 0 OR precipitation < 0 OR rain < 0 OR rain_flag NOT IN (0,1)",
    "OR month NOT BETWEEN 1 AND 12 OR hour NOT BETWEEN 0 AND 23"
  )),
  inconsistent_dates = scalar(paste(
    "SELECT COUNT(*) FROM weather_hourly WHERE year <> EXTRACT(YEAR FROM datetime)",
    "OR month <> EXTRACT(MONTH FROM datetime) OR day <> EXTRACT(DAY FROM datetime)",
    "OR hour <> EXTRACT(HOUR FROM datetime)"
  )),
  expected_daily = scalar("SELECT COUNT(*) FROM (SELECT DISTINCT city_id, datetime::date FROM weather_hourly) d"),
  predictions = scalar("SELECT COUNT(*) FROM predictions")
)

expected <- c(cities = nrow(city_source), weather_hourly = nrow(weather))
ok <- checks["cities"] == expected["cities"] &&
  checks["weather_hourly"] == expected["weather_hourly"] &&
  checks["weather_daily"] == checks["expected_daily"] &&
  all(checks[c("hourly_duplicates", "orphan_city_ids", "invalid_humidity",
               "invalid_cloud_cover", "invalid_values", "inconsistent_dates")] == 0)

cat("\n========================================\n")
cat("IMPORT POSTGRESQL TERMINÉ\n")
cat("========================================\n")
cat(sprintf("Cities              : %s (attendu : %s)\n", checks["cities"], expected["cities"]))
cat(sprintf("Weather hourly       : %s (attendu : %s)\n", checks["weather_hourly"], expected["weather_hourly"]))
cat(sprintf("Weather daily        : %s (attendu : %s)\n", checks["weather_daily"], checks["expected_daily"]))
cat(sprintf("Hourly duplicates    : %s\n", checks["hourly_duplicates"]))
cat(sprintf("Invalid humidity     : %s\n", checks["invalid_humidity"]))
cat(sprintf("Invalid cloud cover  : %s\n", checks["invalid_cloud_cover"]))
cat(sprintf("Other invalid values : %s\n", checks["invalid_values"]))
cat(sprintf("Inconsistent dates   : %s\n", checks["inconsistent_dates"]))
cat(sprintf("Orphan city IDs      : %s\n", checks["orphan_city_ids"]))
cat(sprintf("Predictions          : %s (non modifiées)\n", checks["predictions"]))
cat(sprintf("Status               : %s\n", if (ok) "OK" else "ÉCHEC"))
cat("========================================\n")

if (!ok) stop("Les contrôles de cohérence PostgreSQL ont échoué.", call. = FALSE)
