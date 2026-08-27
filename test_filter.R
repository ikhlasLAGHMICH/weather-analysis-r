library(dplyr)
df <- data.frame(
  city = "Paris",
  date = as.Date(c("2021-01-01", "2022-01-01"))
)
selected_dates <- as.Date(c("2022-01-01", "2025-01-01"))
selected_cities <- "Paris"

res <- df |> dplyr::filter(city %in% !!selected_cities, date >= !!selected_dates[1], date <= !!selected_dates[2])
print(res)
