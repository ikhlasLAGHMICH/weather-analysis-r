$content = Get-Content shiny/app.R -Raw
$content = $content -replace '(?s)        plotlyOutput\("temp_season_chart",  height = "360px"\)\r?\n      \)\r?\n    \)\r?\n  \),\r?\n\r?\n        h3\("Precipitations et jours de pluie", class = "section-title"\),',
        "        plotlyOutput("temp_season_chart",  height = "360px")
      )
    )
  ),

  # ── Tab 3 : Precipitations ───────────────────────────────────
  tabPanel(
    "Precipitations", icon = icon("cloud-rain"),
    sidebarLayout(
      sidebarPanel(width = 2, sidebar_filters("rain")),
      mainPanel(width = 10,
        h3("Precipitations et jours de pluie", class = "section-title"),"

Set-Content shiny/app.R $content
