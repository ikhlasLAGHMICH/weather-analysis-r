.root <- "."
source("R/model_helpers.R")
source("04_style.R")

env_path <- file.path(.root, ".env")
load_env_file(env_path)
con <- DBI::dbConnect(
  RPostgres::Postgres(),
  dbname   = get_env("POSTGRES_DB"),
  host     = get_env("POSTGRES_HOST", "localhost"),
  port     = as.integer(get_env("POSTGRES_PORT", "5432")),
  user     = get_env("POSTGRES_USER"),
  password = get_env("POSTGRES_PASSWORD")
)
daily <- DBI::dbGetQuery(con, "
    SELECT d.date,
           c.name               AS city,
           d.temp_min,   d.temp_max,   d.temp_mean,
           d.humidity_mean,
           d.precipitation_total,
           d.rain_total,
           d.pressure_mean,
           d.cloud_cover_mean,
           d.wind_speed_mean,  d.wind_speed_max,
           d.rain_flag
    FROM weather_daily d
    INNER JOIN cities c ON d.city_id = c.city_id
    ORDER BY c.name, d.date
  ")

  monthly <- DBI::dbGetQuery(con, "
    SELECT c.name AS city,
           EXTRACT(YEAR  FROM h.datetime)::int AS year,
           EXTRACT(MONTH FROM h.datetime)::int AS month,
           AVG(h.temperature_2m) AS temperature_mean,
           SUM(h.precipitation)  AS precipitation_total
    FROM weather_hourly h
    INNER JOIN cities c ON h.city_id = c.city_id
    GROUP BY 1, 2, 3
    ORDER BY 1, 2, 3
  ")
  daily$date    <- as.Date(daily$date)
  monthly$date  <- as.Date(paste(monthly$year, monthly$month, "01", sep = "-"))
  APP_DATA <- list(mode="db", daily=daily, monthly=monthly)

  library(dplyr)
  selected_cities <- c("Stockholm", "Lille", "Paris", "Madrid", "Rome")
  selected_dates <- as.Date(c("2022-01-06", "2025-12-17"))

  res <- APP_DATA$monthly |>
        dplyr::filter(city %in% !!selected_cities, date >= !!selected_dates[1], date <= !!selected_dates[2])
  
  print(min(res$date))
  print(max(res$date))
