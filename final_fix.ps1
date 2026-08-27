$content = Get-Content shiny/app.R -Raw
$content = $content -replace 'cities_sel <- \.get_cities\("temp"\); req\(length\(cities_sel\) > 0\)\s*d <- if \(APP_DATA\$mode == "db"\) \{\s*APP_DATA\$daily \|> dplyr::filter\(city %in% cities_sel\) \|>', 'd <- if (APP_DATA$mode == "db") { .filter_daily("temp") |>'

$content = $content -replace 'cities_sel <- \.get_cities\("rain"\); req\(length\(cities_sel\) > 0\)\s*d <- if \(APP_DATA\$mode == "db"\) \{\s*APP_DATA\$daily \|> dplyr::filter\(city %in% cities_sel\) \|>', 'd <- if (APP_DATA$mode == "db") { .filter_daily("rain") |>'

$content = $content -replace 'cities_sel <- \.get_cities\("wind"\); req\(length\(cities_sel\) > 0\)\s*d <- if \(APP_DATA\$mode == "db"\) \{\s*APP_DATA\$daily \|> dplyr::filter\(city %in% cities_sel\) \|>', 'd <- if (APP_DATA$mode == "db") { .filter_daily("wind") |>'

$content = $content -replace 'cities_sel <- \.get_cities\("wind"\)\s*d <- if \(APP_DATA\$mode == "db"\) \{\s*req\(length\(cities_sel\) > 0\)\s*num_cols <- APP_DATA\$daily \|> dplyr::filter\(city %in% cities_sel\) \|>', 'd <- if (APP_DATA$mode == "db") { num_cols <- .filter_daily("wind") |>'
Set-Content shiny/app.R $content
