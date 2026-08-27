







#   - Chargement donnees : PostgreSQL (priorite) → cache RDS (fallback partiel)
#   - Modele ML : Lazy Loading autonome (pas besoin de DB pour inferer)
#   - 6 onglets : Accueil | Temperatures | Precipitations | Vent & Humidite
#                 Prediction | A propos
# ============================================================

suppressPackageStartupMessages({
  library(shiny)
  library(shinythemes)
  library(plotly)
  library(dplyr)
  library(lubridate)
  library(DBI)
  library(RPostgres)
  library(ranger)
})

# ============================================================
# DETECTION DE LA RACINE DU PROJET
# ============================================================
# app.R peut etre lance depuis shiny/ ou depuis la racine.
# On detecte le contexte et on resout tous les chemins a partir de .root.

.root <- if (file.exists("R/model_helpers.R")) {
  "."
} else if (file.exists("../R/model_helpers.R")) {
  ".."
} else {
  stop("Impossible de localiser la racine du projet.", call. = FALSE)
}

source(file.path(.root, "04_style.R"),         local = TRUE)
source(file.path(.root, "R", "model_helpers.R"), local = TRUE)

# ============================================================
# CHARGEMENT DES DONNEES AU DEMARRAGE
# ============================================================

.db_connect <- function() {
  env_path <- file.path(.root, ".env")
  load_env_file(env_path)
  DBI::dbConnect(
    RPostgres::Postgres(),
    dbname   = get_env("POSTGRES_DB"),
    host     = get_env("POSTGRES_HOST", "localhost"),
    port     = as.integer(get_env("POSTGRES_PORT", "5432")),
    user     = get_env("POSTGRES_USER"),
    password = get_env("POSTGRES_PASSWORD")
  )
}

.load_from_db <- function() {
  con <- .db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

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

  list(mode = "db", daily = daily, monthly = monthly)
}

.load_from_cache <- function() {
  cache_path <- file.path(.root, "results", "analysis_objects.rds")
  if (!file.exists(cache_path)) return(list(mode = "none"))
  cache <- readRDS(cache_path)
  list(
    mode                  = "cache",
    temperature_monthly   = cache$temperature_monthly,
    temperature_city      = cache$temperature_city,
    temperature_season    = cache$temperature_season,
    rainy_days            = cache$rainy_days,
    precipitation_monthly = cache$precipitation_monthly,
    humidity_city         = cache$humidity_city,
    wind_city             = cache$wind_city,
    correlation_long      = cache$correlation_long
  )
}

# Tentative DB, fallback cache — credentials jamais exposes en UI
APP_DATA <- tryCatch(
  .load_from_db(),
  error = function(e) {
    message("[Shiny] Bascule sur cache local : ", conditionMessage(e))
    .load_from_cache()
  }
)

# Plage de dates pour les inputs
DATE_MIN <- if (APP_DATA$mode == "db") min(APP_DATA$daily$date) else as.Date("2021-01-01")
DATE_MAX <- if (APP_DATA$mode == "db") max(APP_DATA$daily$date) else as.Date("2025-12-31")

# ============================================================
# CSS PERSONNALISE
# ============================================================

CUSTOM_CSS <- "
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700&display=swap');
  body { font-family: 'Inter', sans-serif; }

  .kpi-box {
    background: linear-gradient(135deg, #1e2433, #252d40);
    border: 1px solid #3a4055;
    border-radius: 14px;
    padding: 22px 16px;
    text-align: center;
    margin: 6px;
    transition: transform .2s ease, box-shadow .2s ease;
  }
  .kpi-box:hover {
    transform: translateY(-4px);
    box-shadow: 0 10px 24px rgba(0,0,0,.45);
    border-color: #00d4aa55;
  }
  .kpi-value { font-size: 2.1em; font-weight: 700; color: #00d4aa; line-height: 1.1; }
  .kpi-label { font-size: .78em; color: #8899aa; text-transform: uppercase; letter-spacing: .09em; margin-top: 6px; }

  .mode-banner {
    background-color: #7a5c00;
    color: #ffe082;
    padding: 9px 16px;
    border-radius: 7px;
    font-size: .87em;
    margin-bottom: 14px;
  }

  .pred-card-yes {
    background: linear-gradient(135deg, #0d2f44, #0a3d55);
    border: 2px solid #00b4d8;
    border-radius: 14px;
    padding: 30px 20px;
    text-align: center;
    color: #00d4ff;
    font-size: 1.9em;
    font-weight: 700;
  }
  .pred-card-no {
    background: linear-gradient(135deg, #2e1a0e, #4a2a0a);
    border: 2px solid #ff9800;
    border-radius: 14px;
    padding: 30px 20px;
    text-align: center;
    color: #ffb74d;
    font-size: 1.9em;
    font-weight: 700;
  }
  .pred-card-wait {
    background: #1e2433;
    border: 1px dashed #3a4055;
    border-radius: 14px;
    padding: 30px 20px;
    text-align: center;
    color: #8899aa;
    font-size: 1.1em;
  }
  .pred-prob-bar-container {
    background: #333;
    border-radius: 8px;
    height: 12px;
    margin-top: 14px;
    overflow: hidden;
  }
  .pred-prob-bar {
    height: 100%;
    border-radius: 8px;
    background: linear-gradient(90deg, #00b4d8, #00d4aa);
    transition: width .4s ease;
  }

  .section-title {
    border-left: 4px solid #00d4aa;
    padding-left: 12px;
    margin-bottom: 16px;
    font-weight: 600;
    color: #dde;
  }
  .nav-tabs .nav-link { font-weight: 500; }
"

# ============================================================
# HELPER UI
# ============================================================

sidebar_filters <- function(ns_prefix) {
  tagList(
    h5("Filtres", style = "color:#aaa; text-transform:uppercase; font-size:.78em; letter-spacing:.08em;"),
    selectInput(
      paste0("cities_", ns_prefix), "Villes",
      choices  = city_order,
      selected = city_order,
      multiple = TRUE
    ),
    dateRangeInput(
      paste0("date_", ns_prefix), "Periode",
      start    = DATE_MIN, end = DATE_MAX,
      min      = DATE_MIN, max = DATE_MAX,
      format   = "dd/mm/yyyy",
      language = "fr"
    )
  )
}

kpi_box_ui <- function(output_id) {
  uiOutput(output_id)
}

# ============================================================
# UI
# ============================================================

ui <- navbarPage(
  title  = span(icon("cloud-sun"), " MeteoAnalyse"),
  theme  = shinythemes::shinytheme("darkly"),
  id     = "main_nav",
  header = tags$head(
    tags$style(HTML(CUSTOM_CSS)),
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1")
  ),

  # ── Tab 1 : Accueil ─────────────────────────────────────────
  tabPanel(
    "Accueil", icon = icon("house"),
    fluidRow(
      column(12,
        h2("Dashboard Meteorologique", class = "section-title"),
        tags$p("Analyse historique · 5 villes europeennes · 2021–2025",
               style = "color:#8899aa; margin-bottom:10px;"),
        uiOutput("mode_banner_ui")
      )
    ),
    hr(),
    fluidRow(
      column(3, sidebar_filters("home")),
      column(9,
        h4("Indicateurs cles", class = "section-title"),
        fluidRow(
          column(3, kpi_box_ui("kpi_temp")),
          column(3, kpi_box_ui("kpi_rain")),
          column(3, kpi_box_ui("kpi_precip")),
          column(3, kpi_box_ui("kpi_wind"))
        ),
        hr(),
        h4("Evolution mensuelle des temperatures", class = "section-title"),
        plotlyOutput("home_temp_chart", height = "360px")
      )
    )
  ),

  # ── Tab 2 : Temperatures ────────────────────────────────────
  tabPanel(
    "Temperatures", icon = icon("thermometer-half"),
    sidebarLayout(
      sidebarPanel(width = 2, sidebar_filters("temp")),
      mainPanel(width = 10,
        h3("Temperatures", class = "section-title"),
        plotlyOutput("temp_monthly_chart", height = "400px"),
        hr(),
        plotlyOutput("temp_season_chart",  height = "360px")
      )
    )
  ),

  # ── Tab 3 : Precipitations ───────────────────────────────────
  tabPanel(
    "Precipitations", icon = icon("cloud-rain"),
    sidebarLayout(
      sidebarPanel(width = 2, sidebar_filters("rain")),
      mainPanel(width = 10,
        h3("Precipitations et jours de pluie", class = "section-title"),
        plotlyOutput("precip_monthly_chart", height = "400px"),
        hr(),
        plotlyOutput("rainy_days_chart",     height = "340px")
      )
    )
  ),

  # ── Tab 4 : Vent & Humidite ──────────────────────────────────
  tabPanel(
    "Vent & Humidite", icon = icon("wind"),
    sidebarLayout(
      sidebarPanel(width = 2, sidebar_filters("wind")),
      mainPanel(width = 10,
        h3("Vent, Humidite et Correlations", class = "section-title"),
        fluidRow(
          column(6, plotlyOutput("wind_chart",     height = "340px")),
          column(6, plotlyOutput("humidity_chart", height = "340px"))
        ),
        hr(),
        plotlyOutput("correlation_chart", height = "420px")
      )
    )
  ),

  # ── Tab 5 : Prediction (MULTI-INTEMPERIES) ───────────────────
  tabPanel(
    "Prediction", icon = icon("robot"),
    fluidRow(
      # Panneau de saisie
      column(4,
        wellPanel(
          h4("Cible a predire", class = "section-title"),
          selectInput("pred_target", "Type d'intemperie :",
                      choices = setNames(names(WEATHER_EVENTS), sapply(WEATHER_EVENTS, `[[`, "label")),
                      selected = "rain"),
          uiOutput("target_info_ui"),
          hr(),
          h4("Conditions du jour J", class = "section-title"),
          selectInput("pred_city",   "Ville",
                      choices = city_order, selected = "Paris"),
          selectInput("pred_month",  "Mois",
                      choices = setNames(1:12, month.name), selected = "11"),
          selectInput("pred_season", "Saison",
                      choices = c("Winter", "Spring", "Summer", "Autumn"),
                      selected = "Autumn"),
          hr(),
          sliderInput("pred_temp_mean", "Temperature moyenne (C)",   -20, 45, 15, 0.5),
          sliderInput("pred_temp_min",  "Temperature min (C)",       -25, 40, 10, 0.5),
          sliderInput("pred_temp_max",  "Temperature max (C)",       -15, 50, 20, 0.5),
          sliderInput("pred_humidity",  "Humidite (%)",                0, 100, 70, 1),
          sliderInput("pred_pressure",  "Pression (hPa)",            960, 1040, 1013, 0.5),
          sliderInput("pred_wind_mean", "Vent moyen (km/h)",           0, 100, 15, 0.5),
          sliderInput("pred_wind_max",  "Vent max (km/h)",             0, 200, 30, 0.5),
          sliderInput("pred_cloud",     "Nebulosite (%)",              0, 100, 50, 1),
          sliderInput("pred_precip_lag1","Precipitations J-1 (mm)",   0, 100, 5, 0.5),
          checkboxInput("pred_flag_lag1", "L'evenement s'est produit hier ?", value = FALSE),
          hr(),
          actionButton("predict_btn", "Predire pour demain (J+1)",
                       class = "btn-success btn-block",
                       icon  = icon("play"),
                       style = "width:100%; font-weight:700; font-size:1.05em;")
        )
      ),
      # Panneau resultat
      column(8,
        h3("Resultat", class = "section-title"),
        uiOutput("prediction_result_ui"),
        hr(),
        h4("Performances du modele utilise", class = "section-title"),
        uiOutput("model_metrics_ui"),
        hr(),
        h4("Importance des variables (Random Forest)", class = "section-title"),
        plotlyOutput("importance_chart", height = "350px")
      )
    )
  ),

  # ── Tab 6 : A propos ────────────────────────────────────────
  tabPanel(
    "A propos", icon = icon("info-circle"),
    fluidRow(column(8, offset = 2,
      h3("Projet Data — Analyse meteorologique", class = "section-title"),
      p("Developpe dans le cadre d'un cours de Data Science en R.", style="color:#aaa;"),
      h4("Source des donnees"),
      tags$ul(
        tags$li("API Open-Meteo (archive historique 2021–2025)"),
        tags$li("5 villes : Stockholm, Lille, Paris, Madrid, Rome")
      ),
      h4("Architecture"),
      tags$pre(style="background:#1e2433; padding:14px; border-radius:8px; color:#cdd;",
        "Open-Meteo API\n  → 01_api.R       (Ikhlas — collecte)\n  → 02_cleaning.R (Ikhlas — nettoyage)\n  → 03_database.R (Cabrel — PostgreSQL)\n  → 04_analysis.R (Maria — visualisations)\n  → 05_model.R    (Gills — ML multi-cibles)\n  → shiny/app.R   (Gills — dashboard dynamique)"
      ),
      h4("Membres"),
      tags$ul(
        tags$li("Ikhlas : API & collecte des donnees"),
        tags$li("Cabrel : Base SQL & qualite"),
        tags$li("Maria : Analyse exploratoire & visualisations"),
        tags$li("Gills : Machine Learning Multi-Intemperies & Application Shiny")
      ),
      h4("Technologies"),
      tags$ul(
        tags$li("R : dplyr, lubridate, ggplot2, ranger, pROC"),
        tags$li("Base de donnees : PostgreSQL 16 (Docker)"),
        tags$li("Shiny : shiny, shinythemes, plotly")
      )
    ))
  )
)

# ============================================================
# SERVER
# ============================================================

server <- function(input, output, session) {

  # ── Banniere de mode ───────────────────────────────────────
  output$mode_banner_ui <- renderUI({
    switch(APP_DATA$mode,
      cache = div(class = "mode-banner",
                  icon("exclamation-triangle"),
                  " Mode hors-ligne — donnees chargees depuis le cache local."),
      none  = div(class = "mode-banner",
                  icon("times-circle"),
                  " Aucune source de donnees disponible."),
      NULL
    )
  })

  # ── Helpers filtre communs ─────────────────────────────────
  .get_cities  <- function(prefix) input[[paste0("cities_", prefix)]]
  .get_dates   <- function(prefix) input[[paste0("date_",   prefix)]]

  .filter_daily <- function(prefix) {
    req(APP_DATA$mode == "db")
    cities <- .get_cities(prefix);  dates <- .get_dates(prefix)
    req(length(cities) > 0, !anyNA(dates))
    APP_DATA$daily |>
      filter(city %in% cities, date >= dates[1], date <= dates[2])
  }

  .filter_monthly <- function(prefix) {
    if (APP_DATA$mode == "db") {
      cities <- .get_cities(prefix); dates <- .get_dates(prefix)
      req(length(cities) > 0, !anyNA(dates))
      APP_DATA$monthly |>
        filter(city %in% cities, date >= dates[1], date <= dates[2])
    } else if (APP_DATA$mode == "cache") {
      cities <- .get_cities(prefix)
      APP_DATA$temperature_monthly |> filter(city %in% cities)
    }
  }

  # ── Palette reactive (villes selectionnees) ────────────────
  .palette <- function(cities_vec) {
    cols <- city_colors[intersect(names(city_colors), cities_vec)]
    unname(cols)
  }

  # ── Plotly layout commun ───────────────────────────────────
  .dark_layout <- function(p, title_txt, xlab = "", ylab = "", unified_hover = TRUE) {
    p |> layout(
      title      = list(text = title_txt, font = list(color = "#dde", size = 15)),
      xaxis      = list(title = xlab, color = "#8899aa", gridcolor = "#2a3040", zerolinecolor="#2a3040"),
      yaxis      = list(title = ylab, color = "#8899aa", gridcolor = "#2a3040", zerolinecolor="#2a3040"),
      paper_bgcolor = "#181e2c",
      plot_bgcolor  = "#181e2c",
      legend        = list(font = list(color = "#ccd")),
      hovermode     = if (unified_hover) "x unified" else "closest"
    )
  }



  # ── KPIs Accueil ──────────────────────────────────────────

  .kpi_data <- reactive({

    if (APP_DATA$mode == "db") {

      d <- .filter_daily("home")

      req(nrow(d) > 0)

      list(

        temp   = round(mean(d$temp_mean,          na.rm = TRUE), 1),

        rain   = sum(d$rain_flag == 1,             na.rm = TRUE),

        precip = round(max(d$precipitation_total, na.rm = TRUE), 1),

        wind   = round(max(d$wind_speed_max,      na.rm = TRUE), 1)

      )

    } else if (APP_DATA$mode == "cache") {

      list(

        temp   = round(mean(APP_DATA$temperature_city$temperature_mean, na.rm=TRUE), 1),

        rain   = as.integer(sum(APP_DATA$rainy_days$rainy_days, na.rm=TRUE)),

        precip = NA_real_,

        wind   = round(max(APP_DATA$wind_city$wind_max, na.rm=TRUE), 1)

      )

    } else {

      list(temp=NA, rain=NA, precip=NA, wind=NA)

    }

  })



  .kpi_render <- function(val, label, unit = "") {

    renderUI(div(class = "kpi-box",

      div(class = "kpi-value", if (is.na(val)) "—" else paste0(val, unit)),

      div(class = "kpi-label", label)

    ))

  }



  observe({

    k <- .kpi_data()

    output$kpi_temp   <- .kpi_render(k$temp,  "Temperature moy.", " C")

    output$kpi_rain   <- .kpi_render(k$rain,  "Jours de pluie")

    output$kpi_precip <- .kpi_render(k$precip,"Precipitations max"," mm")

    output$kpi_wind   <- .kpi_render(k$wind,  "Vent max",         " km/h")

  })



  # ── Accueil : temp mensuelle ──────────────────────────────

  output$home_temp_chart <- renderPlotly({

    d <- .filter_monthly("home")

    req(nrow(d) > 0)

    cities_sel <- unique(d$city)

    plot_ly(d, x = ~date, y = ~temperature_mean, color = ~city,

            colors = .palette(cities_sel),

            type = "scatter", mode = "lines+markers", line = list(width=2),

            hovertemplate = "%{x|%b %Y}<br><b>%{y:.1f} C</b><extra>%{fullData.name}</extra>") |>

      .dark_layout("Temperature mensuelle par ville", ylab = "C")

  })



  # ── Temperatures ─────────────────────────────────────────

  output$temp_monthly_chart <- renderPlotly({

    d <- .filter_monthly("temp"); req(nrow(d) > 0)

    plot_ly(d, x = ~date, y = ~temperature_mean, color = ~city,

            colors = .palette(unique(d$city)),

            type = "scatter", mode = "lines", line = list(width=2),

            hovertemplate = "%{x|%b %Y}<br><b>%{y:.1f} C</b><extra>%{fullData.name}</extra>") |>

      .dark_layout("Evolution mensuelle des temperatures", ylab = "C")

  })



  output$temp_season_chart <- renderPlotly({
    d <- if (APP_DATA$mode == "db") {
      .filter_daily("temp") |>
        mutate(season = assign_season(lubridate::month(date)),
               season = factor(season, levels=c("Winter","Spring","Summer","Autumn"))) |>
        group_by(city, season) |>
        summarise(temperature_mean = mean(temp_mean, na.rm=TRUE), .groups="drop")
    } else if (APP_DATA$mode == "cache") {
      cities_sel <- .get_cities("temp"); req(length(cities_sel) > 0)
      APP_DATA$temperature_season |> dplyr::filter(city %in% cities_sel) |>
        mutate(season = factor(season, levels=c("Winter","Spring","Summer","Autumn")))
    } else return(plotly_empty())

    plot_ly(d, x=~season, y=~temperature_mean, color=~city,
            colors = .palette(unique(d$city)), type="bar") |>
      layout(barmode="group") |>
      .dark_layout("Temperature moyenne par saison", xlab="Saison", ylab="C",
                   unified_hover=FALSE)
  })

  # ── Precipitations ────────────────────────────────────────
  output$precip_monthly_chart <- renderPlotly({
    d <- if (APP_DATA$mode == "db") {
      .filter_monthly("rain")
    } else if (APP_DATA$mode == "cache") {
      cities_sel <- .get_cities("rain"); req(length(cities_sel) > 0)
      APP_DATA$precipitation_monthly |> dplyr::filter(city %in% cities_sel)
    } else return(plotly_empty())
    
    req(nrow(d) > 0)
    plot_ly(d, x=~date, y=~precipitation_total, color=~city,
            colors = .palette(unique(d$city)),
            type="scatter", mode="lines+markers", line=list(width=1.8),
            hovertemplate="%{x|%b %Y}<br><b>%{y:.1f} mm</b><extra>%{fullData.name}</extra>") |>
      .dark_layout("Precipitations mensuelles", ylab="mm")
  })

  output$rainy_days_chart <- renderPlotly({
    d <- if (APP_DATA$mode == "db") {
      .filter_daily("rain") |>
        group_by(city) |>
        summarise(rainy_days=sum(rain_flag==1, na.rm=TRUE),
                  total_days=n(), .groups="drop") |>
        mutate(rate=round(rainy_days/total_days*100, 1))
    } else if (APP_DATA$mode == "cache") {
      cities_sel <- .get_cities("rain"); req(length(cities_sel) > 0)
      APP_DATA$rainy_days |> dplyr::filter(city %in% cities_sel) |>
        mutate(rate=round(rainy_days/total_days*100, 1))
    } else return(plotly_empty())

    plot_ly(d, x=~city, y=~rainy_days, color=~city,
            colors = .palette(unique(d$city)), type="bar",
            text=~paste0(rainy_days," j. (",rate,"%)"), textposition="outside") |>
      .dark_layout("Jours de pluie par ville (2021-2025)", ylab="Jours",
                   unified_hover=FALSE) |>
      layout(showlegend=FALSE)
  })

  # ── Vent & Humidite ───────────────────────────────────────
  output$wind_chart <- renderPlotly({
    d <- if (APP_DATA$mode == "db") {
      .filter_daily("wind") |>
        group_by(city) |>
        summarise(wind_mean=mean(wind_speed_mean,na.rm=TRUE),
                  wind_max =max(wind_speed_max, na.rm=TRUE), .groups="drop")
    } else if (APP_DATA$mode == "cache") {
      cities_sel <- .get_cities("wind"); req(length(cities_sel) > 0)
      APP_DATA$wind_city |> dplyr::filter(city %in% cities_sel)
    } else return(plotly_empty())

    plot_ly(d, x=~city, y=~wind_mean, name="Moyenne", type="bar",
            marker=list(color="#00d4aa")) |>
      add_trace(y=~wind_max, name="Maximum", marker=list(color="#ff6b35")) |>
      layout(barmode="group") |>
      .dark_layout("Vitesse du vent (km/h)", ylab="km/h", unified_hover=FALSE)
  })

  output$humidity_chart <- renderPlotly({
    d <- if (APP_DATA$mode == "db") {
      .filter_daily("wind") |>
        group_by(city) |>
        summarise(humidity_mean=mean(humidity_mean, na.rm=TRUE), .groups="drop")
    } else if (APP_DATA$mode == "cache") {
      cities_sel <- .get_cities("wind"); req(length(cities_sel) > 0)
      APP_DATA$humidity_city |> dplyr::filter(city %in% cities_sel)
    } else return(plotly_empty())

    plot_ly(d, x=~city, y=~humidity_mean, color=~city,
            colors=.palette(unique(d$city)), type="bar",
            text=~paste0(round(humidity_mean,1),"%"), textposition="outside") |>
      .dark_layout("Humidite relative moyenne (%)", ylab="%", unified_hover=FALSE) |>
      layout(showlegend=FALSE, yaxis=list(range=c(0,105)))
  })

  output$correlation_chart <- renderPlotly({
    d <- if (APP_DATA$mode == "db") {
      num_cols <- .filter_daily("wind") |>
        select(temp_mean, humidity_mean, precipitation_total,
               pressure_mean, cloud_cover_mean, wind_speed_mean)
      cm <- cor(num_cols, use="complete.obs")
      lbls <- c("Temperature","Humidite","Precipitations","Pression","Nebulosite","Vent")
      colnames(cm) <- rownames(cm) <- lbls
      as.data.frame(cm) |>
        tibble::rownames_to_column("variable_1") |>
        tidyr::pivot_longer(-variable_1, names_to="variable_2", values_to="correlation")
    } else if (APP_DATA$mode == "cache") {
      APP_DATA$correlation_long
    } else return(plotly_empty())

    plot_ly(d, x=~variable_2, y=~variable_1, z=~correlation,
            type="heatmap",
            colorscale=list(c(0,"#2166AC"), c(.5,"#f7f7f7"), c(1,"#B2182B")),
            zmin=-1, zmax=1,
            text=~round(correlation,2), texttemplate="%{text}",
            hovertemplate="%{y} / %{x}<br>r = %{z:.3f}<extra></extra>") |>
      .dark_layout("Matrice de correlation", unified_hover=FALSE) |>
      layout(xaxis=list(tickangle=45))
  })

  # ── Prediction ────────────────────────────────────────────
  current_model <- reactive({
    target <- input$pred_target
    if (is.null(target)) return(NULL)
    
    # Lazy loading autonome
    rds_path <- file.path(.root, "results", paste0(target, "_model.rds"))
    if (!file.exists(rds_path)) return(NULL)
    readRDS(rds_path)
  })

  prediction_result <- eventReactive(input$predict_btn, {
    model_bundle <- current_model()
    req(!is.null(model_bundle))

    req(
      input$pred_temp_min, input$pred_temp_max, input$pred_temp_mean,
      input$pred_humidity, input$pred_pressure, input$pred_wind_mean,
      input$pred_wind_max, input$pred_cloud, input$pred_month,
      input$pred_season, input$pred_city, !is.null(input$pred_flag_lag1),
      input$pred_precip_lag1
    )

    new_obs <- data.frame(
      temp_min         = input$pred_temp_min,
      temp_max         = input$pred_temp_max,
      temp_mean        = input$pred_temp_mean,
      humidity_mean    = input$pred_humidity,
      pressure_mean    = input$pred_pressure,
      wind_speed_mean  = input$pred_wind_mean,
      wind_speed_max   = input$pred_wind_max,
      cloud_cover_mean = input$pred_cloud,
      month            = as.integer(input$pred_month),
      season           = input$pred_season,
      city             = input$pred_city,
      flag_lag1        = as.integer(input$pred_flag_lag1),
      precip_lag1      = input$pred_precip_lag1,
      pressure_lag1    = input$pred_pressure,
      humidity_lag1    = input$pred_humidity,
      stringsAsFactors = FALSE
    )

    predict_weather_event(model_bundle, new_obs)
  })
  output$prediction_result_ui <- renderUI({
    model_bundle <- current_model()
    if (is.null(model_bundle)) {
      return(div(class="mode-banner",
        icon("exclamation-triangle"),
        " Modele non disponible. Executez `make model`."))
    }
    if (input$predict_btn == 0) {
      return(div(class="pred-card-wait",
        icon("arrow-left"), " Renseignez les parametres et cliquez sur 'Predire pour demain'."))
    }
    
    pred     <- prediction_result()
    prob_pct <- round(pred$probability * 100, 1)
    
    event_label <- model_bundle$event_label
    event_icon  <- WEATHER_EVENTS[[model_bundle$event_key]]$icon
    
    if (pred$prediction == "Yes") {
      div(class="pred-card-yes",
        tags$span(style="font-size:1.2em;", event_icon), " ", toupper(event_label), " PROBABLE",
        br(), br(),
        tags$span(style="font-size:.6em; color:#a0d8ef;",
          paste0("Probabilite d'occurrence : ", prob_pct, "%")),
        div(class="pred-prob-bar-container",
          div(class="pred-prob-bar",
              style=paste0("width:", prob_pct, "%; background:linear-gradient(90deg,#00b4d8,#00d4ff);"))
        )
      )
    } else {
      div(class="pred-card-no",
        tags$span(style="font-size:1.2em;", "\u2716"), " PAS DE ", toupper(event_label),
        br(), br(),
        tags$span(style="font-size:.6em; color:#ffe0b2;",
          paste0("Probabilite d'occurrence : ", prob_pct, "%")),
        div(class="pred-prob-bar-container",
          div(class="pred-prob-bar",
              style=paste0("width:", prob_pct, "%; background:linear-gradient(90deg,#ff9800,#ffb74d);"))
        )
      )
    }
  })

  output$model_metrics_ui <- renderUI({
    model_bundle <- current_model()
    if (is.null(model_bundle)) return(NULL)
    
    m <- model_bundle$metrics
    # Convertir 'm' en un data.frame a une seule ligne pour l'affichage (le meilleur modele choisi)
    tags$table(class="table table-dark table-sm table-hover",
      tags$thead(tags$tr(
        tags$th("Modele"), tags$th("Accuracy"), tags$th("Precision"),
        tags$th("Recall"), tags$th("F1"), tags$th("AUC-ROC")
      )),
      tags$tbody(
        tags$tr(
          class = "table-success",
          tags$td(tags$strong(m$model)),
          tags$td(m$accuracy),
          tags$td(m$precision),
          tags$td(m$recall),
          tags$td(m$f1),
          tags$td(m$auc)
        )
      )
    )
  })

  output$importance_chart <- renderPlotly({
    model_bundle <- current_model()
    if (is.null(model_bundle) || is.null(model_bundle$importance)) {
      return(plotly_empty())
    }
    d <- head(model_bundle$importance, 12L)
    d <- d[order(d$importance), ]

    labels_fr <- c(
      temp_mean="Temperature moy.", temp_min="Temperature min",
      temp_max="Temperature max", humidity_mean="Humidite",
      pressure_mean="Pression", wind_speed_mean="Vent moy.",
      wind_speed_max="Vent max", cloud_cover_mean="Nebulosite",
      month="Mois", flag_lag1="Evenement J-1",
      precip_lag1="Precip. J-1", pressure_lag1="Pression J-1",
      humidity_lag1="Humidite J-1", season="Saison",
      cityLille="Ville=Lille", cityMadrid="Ville=Madrid",
      cityParis="Ville=Paris", cityRome="Ville=Rome",
      cityStockholm="Ville=Stockholm"
    )
    d$label <- dplyr::coalesce(labels_fr[d$feature], d$feature)

    plot_ly(d, x=~importance, y=~factor(label, levels=label),
            type="bar", orientation="h",
            marker=list(color="#00d4aa",
                        line=list(color="#00aa88", width=1))) |>
      .dark_layout(paste("Importance des variables —", model_bundle$event_label),
                   xlab="Importance", unified_hover=FALSE)
  })
}

# ============================================================
# LANCEMENT
# ============================================================
shinyApp(ui, server)


