library(dplyr)
library(lubridate)

# Charger les données brutes
weather_raw <- read.csv("data/raw/weather_raw.csv")

# Nettoyage et création de nouvelles variables
weather_clean <- weather_raw |>
  mutate(
    datetime = ymd_hm(datetime),

    date = as.Date(datetime),
    year = year(datetime),
    month = month(datetime),
    day = day(datetime),
    hour = hour(datetime),

    season = case_when(
      month %in% c(12, 1, 2) ~ "Winter",
      month %in% c(3, 4, 5) ~ "Spring",
      month %in% c(6, 7, 8) ~ "Summer",
      month %in% c(9, 10, 11) ~ "Autumn"
    ),

    rain_flag = if_else(rain > 0, 1, 0)
  ) |>
  distinct()

# Vérifications
glimpse(weather_clean)

dim(weather_clean)

colSums(is.na(weather_clean))

sum(duplicated(weather_clean))

table(weather_clean$season)

table(weather_clean$rain_flag)

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

write.csv(
  weather_clean,
  "data/processed/weather_clean.csv",
  row.names = FALSE
)

message("Données nettoyées sauvegardées dans data/processed/weather_clean.csv")

# Contrôles qualité métier

quality_report <- weather_clean |>
  group_by(city) |>
  summarise(
    nb_rows = n(),

    temp_min = min(temperature_2m),
    temp_max = max(temperature_2m),
    temp_mean = mean(temperature_2m),

    humidity_min = min(relative_humidity_2m),
    humidity_max = max(relative_humidity_2m),

    precipitation_min = min(precipitation),
    precipitation_max = max(precipitation),

    pressure_min = min(surface_pressure),
    pressure_max = max(surface_pressure),

    cloud_min = min(cloud_cover),
    cloud_max = max(cloud_cover),

    wind_speed_min = min(wind_speed_10m),
    wind_speed_max = max(wind_speed_10m),

    wind_direction_min = min(wind_direction_10m),
    wind_direction_max = max(wind_direction_10m)
  )

print(quality_report)

# Vérification des plages attendues

sum(weather_clean$relative_humidity_2m < 0 |
    weather_clean$relative_humidity_2m > 100)

sum(weather_clean$cloud_cover < 0 |
    weather_clean$cloud_cover > 100)

sum(weather_clean$wind_direction_10m < 0 |
    weather_clean$wind_direction_10m > 360)

sum(weather_clean$wind_speed_10m < 0)

sum(weather_clean$precipitation < 0)

sum(weather_clean$rain < 0)

write.csv(
  quality_report,
  "data/processed/quality_report.csv",
  row.names = FALSE
)