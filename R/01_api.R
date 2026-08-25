

library(httr2)
library(jsonlite)
library(dplyr)
library(purrr)
library(lubridate)

# Liste des villes étudiées
cities <- tibble(
  city = c("Lille", "Paris", "Madrid", "Rome", "Stockholm"),
  latitude = c(50.6292, 48.8566, 40.4168, 41.9028, 59.3293),
  longitude = c(3.0573, 2.3522, -3.7038, 12.4964, 18.0686)
)

print(cities)

# Paramètres de récupération

start_date <- "2021-01-01"
end_date   <- "2025-12-31"

hourly_variables <- c(
  "temperature_2m",
  "relative_humidity_2m",
  "precipitation",
  "rain",
  "surface_pressure",
  "cloud_cover",
  "wind_speed_10m",
  "wind_direction_10m"
)

# Fonction de récupération Open-Meteo

get_weather_data <- function(city_name, latitude, longitude) {

  message("Récupération des données pour : ", city_name)

  response <- request("https://archive-api.open-meteo.com/v1/archive") |>
    req_url_query(
      latitude = latitude,
      longitude = longitude,
      start_date = start_date,
      end_date = end_date,
      hourly = paste(hourly_variables, collapse = ","),
      timezone = "auto"
    ) |>
    req_perform()

  data <- resp_body_json(response, simplifyVector = TRUE)

  weather <- tibble(
    datetime = data$hourly$time,
    temperature_2m = data$hourly$temperature_2m,
    relative_humidity_2m = data$hourly$relative_humidity_2m,
    precipitation = data$hourly$precipitation,
    rain = data$hourly$rain,
    surface_pressure = data$hourly$surface_pressure,
    cloud_cover = data$hourly$cloud_cover,
    wind_speed_10m = data$hourly$wind_speed_10m,
    wind_direction_10m = data$hourly$wind_direction_10m
  ) |>
    mutate(
      city = city_name,
      latitude = latitude,
      longitude = longitude
    )

  return(weather)
}


# Récupération des 5 villes

weather_raw <- pmap_dfr(
  cities,
  function(city, latitude, longitude) {
    get_weather_data(
      city_name = city,
      latitude = latitude,
      longitude = longitude
    )
  }
)

# Vérifications
glimpse(weather_raw)

table(weather_raw$city)

colSums(is.na(weather_raw))

# Création du dossier si nécessaire
dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)

# Export CSV
write.csv(
  weather_raw,
  "data/raw/weather_raw.csv",
  row.names = FALSE
)

message("Données sauvegardées dans data/raw/weather_raw.csv")