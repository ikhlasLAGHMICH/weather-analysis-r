# ============================================================
# Partie 03 : Analyse exploratoire et visualisations
# ============================================================

suppressPackageStartupMessages({
  library(DBI); library(RPostgres); library(dplyr); library(tidyr); library(lubridate); library(ggplot2)
})

# ============================================================
# 0. PARAMETRES GRAPHIQUES ET SORTIES
# ============================================================

source("04_style.R")
dir.create("figures", recursive = TRUE, showWarnings = FALSE)
dir.create("results", recursive = TRUE, showWarnings = FALSE)

safe_mean <- function(x) if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)
safe_min <- function(x) if (all(is.na(x))) NA_real_ else min(x, na.rm = TRUE)
safe_max <- function(x) if (all(is.na(x))) NA_real_ else max(x, na.rm = TRUE)
safe_sum <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)

# ============================================================
# 1. CHARGEMENT DES DONNEES DEPUIS POSTGRESQL
# ============================================================

get_env <- function(name, default = NULL) {
  value <- Sys.getenv(name, unset = "")
  if (!nzchar(value)) value <- default
  if (is.null(value) || !nzchar(value)) stop("Variable d'environnement manquante : ", name, call. = FALSE)
  value
}

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

config <- list(
  dbname = get_env("POSTGRES_DB"),
  user = get_env("POSTGRES_USER"),
  password = get_env("POSTGRES_PASSWORD"),
  host = get_env("POSTGRES_HOST", "localhost"),
  port = as.integer(get_env("POSTGRES_PORT", "5432"))
)

message("Connexion à PostgreSQL...")

con_analysis <- DBI::dbConnect(
  RPostgres::Postgres(),
  dbname = config$dbname,
  host = config$host,
  port = config$port,
  user = config$user,
  password = config$password
)

message("Connexion PostgreSQL OK.")

required_tables <- c("cities", "weather_hourly", "weather_daily")
missing_tables <- setdiff(required_tables, DBI::dbListTables(con_analysis))

if (length(missing_tables) > 0) {
  DBI::dbDisconnect(con_analysis)
  stop("Tables SQL absentes : ", paste(missing_tables, collapse = ", "), call. = FALSE)
}

# ============================================================
# Requête SQL
# ============================================================

sql_weather <- "
SELECT
    h.datetime,
    h.temperature_2m,
    h.relative_humidity_2m,
    h.precipitation,
    h.rain,
    h.surface_pressure,
    h.cloud_cover,
    h.wind_speed_10m,
    h.wind_direction_10m,
    c.name AS city,
    c.latitude,
    c.longitude,
    h.year,
    h.month,
    h.day,
    h.hour,
    h.season,
    h.rain_flag
FROM weather_hourly h
INNER JOIN cities c ON h.city_id = c.city_id
ORDER BY h.datetime, c.name
"

message("Lecture des données depuis PostgreSQL...")

weather_clean <- DBI::dbGetQuery(con_analysis, sql_weather)

DBI::dbDisconnect(con_analysis)
rm(con_analysis)
gc()

message("Connexion PostgreSQL fermée.")

# ============================================================
# Préparation des données
# ============================================================

weather_clean <- weather_clean |>
  mutate(
    datetime = as.POSIXct(datetime, tz = "UTC"),
    date = as.Date(datetime),
    city = factor(city, levels = city_order)
  )

if (nrow(weather_clean) == 0) stop("La requête SQL ne retourne aucune donnée.", call. = FALSE)

if (nrow(weather_clean) != 219120) {
  warning("Nombre de lignes inattendu : ", nrow(weather_clean), " au lieu de 219120.")
}

print(dim(weather_clean))
print(table(weather_clean$city, useNA = "ifany"))

cat("============================================\n")
cat("DONNEES CHARGEES DEPUIS POSTGRESQL\n")
cat("============================================\n")
cat("Nombre de lignes : ", nrow(weather_clean), "\n")
cat("Nombre de colonnes : ", ncol(weather_clean), "\n")
cat("\nVilles :\n")
print(unique(weather_clean$city))
cat("\nPeriode :\n")
print(range(weather_clean$date, na.rm = TRUE))
cat("\nSource : PostgreSQL / weather_hourly + cities\n")
cat("Analyse prête.\n")

# ============================================================
# 2. TEMPERATURE MOYENNE PAR VILLE
# ============================================================

temperature_city <- weather_clean |>
  group_by(city) |>
  summarise(
    temperature_mean = safe_mean(temperature_2m),
    temperature_min = safe_min(temperature_2m),
    temperature_max = safe_max(temperature_2m),
    .groups = "drop"
  )

print(temperature_city)
write.csv(temperature_city, "results/01_temperature_city.csv", row.names = FALSE, fileEncoding = "UTF-8")

p_temperature_city <- ggplot(temperature_city, aes(x = city, y = temperature_mean, color = city)) +
  geom_errorbar(aes(ymin = temperature_min, ymax = temperature_max), width = 0.15, linewidth = 1) +
  geom_point(size = 5) +
  geom_text(aes(label = paste0(round(temperature_mean, 1), " °C")), vjust = -1.2, size = 4, fontface = "bold") +
  geom_text(aes(y = temperature_min, label = paste0(round(temperature_min, 1), " °C")), vjust = 1.4, size = 3.3) +
  geom_text(aes(y = temperature_max, label = paste0(round(temperature_max, 1), " °C")), vjust = -0.7, size = 3.3) +
  scale_color_manual(values = city_colors) +
  scale_y_continuous(expand = expansion(mult = c(0.08, 0.15))) +
  labs(title = "Température moyenne par ville", subtitle = "Moyenne sur la période 2021–2025 avec minimum et maximum observés", x = "Ville", y = "Température (°C)") +
  theme_minimal(base_size = 14) +
  theme(legend.position = "none", plot.title = element_text(face = "bold", size = 18), plot.subtitle = element_text(size = 11), panel.grid.minor = element_blank())

print(p_temperature_city)
ggsave("figures/01_temperature_mean_city.png", p_temperature_city, width = 11, height = 7, dpi = 300)

# ============================================================
# 3. TEMPERATURE MOYENNE MENSUELLE
# ============================================================

temperature_monthly <- weather_clean |>
  group_by(city, year, month) |>
  summarise(temperature_mean = safe_mean(temperature_2m), .groups = "drop") |>
  mutate(date = as.Date(paste(year, month, "01", sep = "-")))

print(head(temperature_monthly))
write.csv(temperature_monthly, "results/02_temperature_monthly.csv", row.names = FALSE, fileEncoding = "UTF-8")

p_temperature_monthly <- ggplot(temperature_monthly, aes(x = date, y = temperature_mean, color = city)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.4) +
  scale_color_manual(values = city_colors) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y", expand = expansion(mult = c(0.01, 0.02))) +
  labs(title = "Évolution mensuelle de la température moyenne", subtitle = "Évolution climatique mensuelle pour chaque ville entre 2021 et 2025", x = "Date", y = "Température moyenne (°C)") +
  theme_minimal(base_size = 13) +
  theme(legend.position = "right", legend.title = element_text(face = "bold"), plot.title = element_text(face = "bold", size = 18), panel.grid.minor = element_blank())

print(p_temperature_monthly)
ggsave("figures/02_temperature_monthly.png", p_temperature_monthly, width = 12, height = 7.5, dpi = 300)

# ============================================================
# 4. TEMPERATURE PAR SAISON
# ============================================================

temperature_season <- weather_clean |>
  group_by(city, season) |>
  summarise(temperature_mean = safe_mean(temperature_2m), .groups = "drop")

print(temperature_season)
write.csv(temperature_season, "results/03_temperature_season.csv", row.names = FALSE, fileEncoding = "UTF-8")

p_temperature_season <- ggplot(temperature_season, aes(x = season, y = temperature_mean, fill = city)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  geom_text(aes(label = round(temperature_mean, 1)), position = position_dodge(width = 0.8), vjust = -0.4, size = 3.5) +
  scale_fill_manual(values = city_colors) +
  labs(title = "Température moyenne par saison", subtitle = "Comparaison des profils saisonniers entre les cinq villes", x = "Saison", y = "Température moyenne (°C)", fill = "Ville") +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold", size = 18), panel.grid.minor = element_blank())

print(p_temperature_season)
ggsave("figures/03_temperature_season.png", p_temperature_season, width = 12, height = 7, dpi = 300)

# ============================================================
# 5. JOURS DE PLUIE
# ============================================================

rainy_days <- weather_clean |>
  group_by(city, date) |>
  summarise(rainy_day = if (all(is.na(rain_flag))) NA_real_ else max(rain_flag, na.rm = TRUE), .groups = "drop") |>
  group_by(city) |>
  summarise(rainy_days = sum(rainy_day, na.rm = TRUE), total_days = n(), rainy_day_rate = rainy_days / total_days * 100, .groups = "drop")

print(rainy_days)
write.csv(rainy_days, "results/04_rainy_days.csv", row.names = FALSE, fileEncoding = "UTF-8")

p_rainy_days <- ggplot(rainy_days, aes(x = city, y = rainy_days, fill = city)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = paste0(rainy_days, " jours\n", round(rainy_day_rate, 1), "%")), vjust = -0.3, size = 4, fontface = "bold") +
  scale_fill_manual(values = city_colors) +
  labs(title = "Nombre de jours de pluie par ville", subtitle = "Nombre de jours avec au moins un épisode de pluie sur 2021–2025", x = "Ville", y = "Nombre de jours de pluie") +
  theme_minimal(base_size = 14) +
  theme(legend.position = "none", plot.title = element_text(face = "bold", size = 18), panel.grid.minor = element_blank())

print(p_rainy_days)
ggsave("figures/04_rainy_days.png", p_rainy_days, width = 11, height = 7, dpi = 300)

# ============================================================
# 6. PRECIPITATIONS MENSUELLES
# ============================================================

precipitation_monthly <- weather_clean |>
  group_by(city, year, month) |>
  summarise(precipitation_total = safe_sum(precipitation), .groups = "drop") |>
  mutate(date = as.Date(paste(year, month, "01", sep = "-")))

print(head(precipitation_monthly))
write.csv(precipitation_monthly, "results/05_precipitation_monthly.csv", row.names = FALSE, fileEncoding = "UTF-8")

# ============================================================
# 7. GRAPHIQUE - PRECIPITATIONS CORRIGE
# ============================================================

p_precipitation <- ggplot(precipitation_monthly, aes(x = date, y = precipitation_total, color = city)) +
  geom_line(linewidth = 0.7, alpha = 0.9) +
  geom_point(size = 1.5, alpha = 0.9) +
  scale_color_manual(values = city_colors) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y", expand = expansion(mult = c(0.01, 0.02))) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.08))) +
  labs(title = "Évolution mensuelle des précipitations", subtitle = "Cumul mensuel des précipitations entre 2021 et 2025", x = "Date", y = "Précipitations mensuelles (mm)", color = "Ville") +
  theme_minimal(base_size = 13) +
  theme(legend.position = "right", legend.title = element_text(face = "bold"), plot.title = element_text(face = "bold", size = 18), panel.grid.minor = element_blank())

print(p_precipitation)
ggsave("figures/05_precipitation_monthly.png", p_precipitation, width = 12, height = 7.5, dpi = 300)

# ============================================================
# 8. HUMIDITE MOYENNE
# ============================================================

humidity_city <- weather_clean |>
  group_by(city) |>
  summarise(humidity_mean = safe_mean(relative_humidity_2m), .groups = "drop")

print(humidity_city)
write.csv(humidity_city, "results/06_humidity_city.csv", row.names = FALSE, fileEncoding = "UTF-8")

p_humidity <- ggplot(humidity_city, aes(x = city, y = humidity_mean, fill = city)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = paste0(round(humidity_mean, 1), "%")), vjust = -0.4, size = 4, fontface = "bold") +
  scale_fill_manual(values = city_colors) +
  scale_y_continuous(limits = c(0, 90)) +
  labs(title = "Humidité relative moyenne par ville", subtitle = "Moyenne de l'humidité relative sur la période 2021–2025", x = "Ville", y = "Humidité relative moyenne (%)") +
  theme_minimal(base_size = 14) +
  theme(legend.position = "none", plot.title = element_text(face = "bold", size = 18), panel.grid.minor = element_blank())

print(p_humidity)
ggsave("figures/06_humidity_city.png", p_humidity, width = 11, height = 7, dpi = 300)

# ============================================================
# 9. VENT
# ============================================================

wind_city <- weather_clean |>
  group_by(city) |>
  summarise(wind_mean = safe_mean(wind_speed_10m), wind_max = safe_max(wind_speed_10m), .groups = "drop")

print(wind_city)
write.csv(wind_city, "results/07_wind_city.csv", row.names = FALSE, fileEncoding = "UTF-8")

p_wind <- ggplot(wind_city, aes(x = city, y = wind_mean, color = city)) +
  geom_errorbar(aes(ymin = wind_mean, ymax = wind_max), width = 0.15, linewidth = 1) +
  geom_point(size = 5) +
  geom_text(aes(label = paste0(round(wind_mean, 1), " km/h")), vjust = -1.1, size = 4, fontface = "bold") +
  geom_text(aes(y = wind_max, label = paste0(round(wind_max, 1), " km/h")), vjust = -0.7, size = 3.5, fontface = "bold") +
  scale_color_manual(values = city_colors) +
  scale_y_continuous(expand = expansion(mult = c(0.03, 0.18))) +
  labs(title = "Vitesse du vent par ville", subtitle = "Moyenne et maximum observés sur la période 2021–2025", x = "Ville", y = "Vitesse du vent (km/h)") +
  coord_cartesian(clip = "off") +
  theme_minimal(base_size = 14) +
  theme(legend.position = "none", plot.title = element_text(face = "bold", size = 18), panel.grid.minor = element_blank())

print(p_wind)
ggsave("figures/07_wind_city.png", p_wind, width = 11, height = 7, dpi = 300)

# ============================================================
# 10. TEMPERATURE ET HUMIDITE
# ============================================================

set.seed(123)
weather_sample <- weather_clean |> slice_sample(n = min(20000, nrow(weather_clean)))

p_temp_humidity <- ggplot(weather_sample, aes(x = temperature_2m, y = relative_humidity_2m, color = city)) +
  geom_point(alpha = 0.25, size = 1) +
  geom_smooth(method = "lm", se = FALSE, linewidth = 1.1) +
  scale_color_manual(values = city_colors) +
  facet_wrap(~ city) +
  labs(title = "Relation entre température et humidité", subtitle = "Nuage de points et tendance linéaire par ville", x = "Température (°C)", y = "Humidité relative (%)", color = "Ville") +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold", size = 18), panel.grid.minor = element_blank())

print(p_temp_humidity)
ggsave("figures/08_temperature_humidity.png", p_temp_humidity, width = 12, height = 8, dpi = 300)

# ============================================================
# 11. MATRICE DE CORRELATION
# ============================================================

correlation_data <- weather_clean |>
  select(temperature_2m, relative_humidity_2m, precipitation, surface_pressure, cloud_cover, wind_speed_10m)

correlation_matrix <- cor(correlation_data, use = "complete.obs")
print(correlation_matrix)
write.csv(as.data.frame(correlation_matrix), "results/09_correlation_matrix.csv", row.names = TRUE, fileEncoding = "UTF-8")

correlation_long <- as.data.frame(correlation_matrix) |>
  mutate(variable_1 = rownames(correlation_matrix)) |>
  pivot_longer(cols = -variable_1, names_to = "variable_2", values_to = "correlation") |>
  mutate(
    variable_1 = recode(variable_1, temperature_2m = "Température", relative_humidity_2m = "Humidité relative", precipitation = "Précipitations", surface_pressure = "Pression", cloud_cover = "Nébulosité", wind_speed_10m = "Vitesse du vent"),
    variable_2 = recode(variable_2, temperature_2m = "Température", relative_humidity_2m = "Humidité relative", precipitation = "Précipitations", surface_pressure = "Pression", cloud_cover = "Nébulosité", wind_speed_10m = "Vitesse du vent")
  )

write.csv(correlation_long, "results/09_correlation_long.csv", row.names = FALSE, fileEncoding = "UTF-8")

p_correlation <- ggplot(correlation_long, aes(x = variable_1, y = variable_2, fill = correlation)) +
  geom_tile(color = "white", linewidth = 0.6) +
  geom_text(aes(label = round(correlation, 2)), size = 4, fontface = "bold") +
  scale_fill_gradient2(low = correlation_low, mid = correlation_mid, high = correlation_high, midpoint = 0, limits = c(-1, 1)) +
  labs(title = "Matrice de corrélation des variables météorologiques", subtitle = "Corrélations calculées sur l'ensemble des observations", x = "", y = "", fill = "Corrélation") +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold", size = 18), axis.text.x = element_text(angle = 45, hjust = 1), panel.grid = element_blank())

print(p_correlation)
ggsave("figures/09_correlation.png", p_correlation, width = 11, height = 9, dpi = 300)

# ============================================================
# 12. RESUME FINAL
# ============================================================

cat("\n")
cat("============================================\n")
cat("ANALYSE TERMINEE\n")
cat("============================================\n")
cat("Figures générées :\n")
print(list.files("figures", pattern = "\\.png$"))
cat("\nNombre de figures : ")
print(length(list.files("figures", pattern = "\\.png$")))

saveRDS(
  list(
    temperature_city = temperature_city,
    temperature_monthly = temperature_monthly,
    temperature_season = temperature_season,
    rainy_days = rainy_days,
    precipitation_monthly = precipitation_monthly,
    humidity_city = humidity_city,
    wind_city = wind_city,
    correlation_matrix = correlation_matrix,
    correlation_long = correlation_long,
    plots = list(
      temperature_city = p_temperature_city,
      temperature_monthly = p_temperature_monthly,
      temperature_season = p_temperature_season,
      rainy_days = p_rainy_days,
      precipitation_monthly = p_precipitation,
      humidity_city = p_humidity,
      wind_city = p_wind,
      temperature_humidity = p_temp_humidity,
      correlation = p_correlation
    )
  ),
  "results/analysis_objects.rds"
)

cat("\nRésultats CSV :\n")
print(list.files("results", pattern = "\\.csv$"))
cat("\nAnalyse terminée.\n")