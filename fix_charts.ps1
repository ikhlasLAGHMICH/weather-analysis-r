$content = Get-Content shiny/app.R -Raw
$content = $content -replace 'cities_sel <- \.get_cities\("temp"\); req\(length\(cities_sel\) > 0\)\s*d <- if \(APP_DATA\ == "db"\) \{\s*APP_DATA\ \|> dplyr::filter\(city %in% cities_sel\) \|>', 'd <- if (APP_DATA == "db") { .filter_daily("temp") |>'

$content = $content -replace 'cities_sel <- \.get_cities\("rain"\); req\(length\(cities_sel\) > 0\)\s*d <- if \(APP_DATA\ == "db"\) \{\s*APP_DATA\ \|> dplyr::filter\(city %in% cities_sel\) \|>', 'd <- if (APP_DATA == "db") { .filter_daily("rain") |>'

$content = $content -replace 'cities_sel <- \.get_cities\("wind"\); req\(length\(cities_sel\) > 0\)\s*d <- if \(APP_DATA\ == "db"\) \{\s*APP_DATA\ \|> dplyr::filter\(city %in% cities_sel\) \|>', 'd <- if (APP_DATA == "db") { .filter_daily("wind") |>'

$content = $content -replace 'cities_sel <- \.get_cities\("wind"\)\s*d <- if \(APP_DATA\ == "db"\) \{\s*req\(length\(cities_sel\) > 0\)\s*APP_DATA\ \|> dplyr::filter\(city %in% cities_sel\) \|>', 'd <- if (APP_DATA == "db") { .filter_daily("wind") |>'

Set-Content shiny/app.R $content
