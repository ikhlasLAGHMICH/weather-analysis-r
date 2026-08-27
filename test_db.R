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

DBI::dbGetQuery(con, "
    SELECT c.name AS city,
           EXTRACT(YEAR  FROM h.datetime)::int AS year,
           EXTRACT(MONTH FROM h.datetime)::int AS month,
           AVG(h.temperature_2m) AS temperature_mean,
           SUM(h.precipitation)  AS precipitation_total
    FROM weather_hourly h
    INNER JOIN cities c ON h.city_id = c.city_id
    GROUP BY 1, 2, 3
    ORDER BY 1, 2, 3
    LIMIT 5
")
