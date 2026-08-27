$code = @'
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
      APP_DATA$temperature_season[APP_DATA$temperature_season$city %in% cities_sel, ] |>
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
      cities_sel <- .get_cities("rain")
      APP_DATA$precipitation_monthly[APP_DATA$precipitation_monthly$city %in% cities_sel, ]
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
      cities_sel <- .get_cities("rain")
      APP_DATA$rainy_days[APP_DATA$rainy_days$city %in% cities_sel, ] |>
        mutate(rate=round(rainy_days/total_days*100, 1))
    } else return(plotly_empty())

    plot_ly(d, x=~city, y=~rainy_days, color=~city,
            colors = .palette(unique(d$city)), type="bar",
            text=~paste0(rainy_days," j. (",rate,"%)"), textposition="outside") |>
      .dark_layout("Jours de pluie par ville", ylab="Jours",
                   unified_hover=FALSE) |>
      layout(showlegend=FALSE)
  })

  # ── Vent & Humidite ───────────────────────────────────────
  output$wind_chart <- renderPlotly({
    d <- if (APP_DATA$mode == "db") {
      .filter_daily("wind") |>
        group_by(city) |>
        summarise(wind_mean=mean(wind_speed_mean, na.rm=TRUE),
                  wind_max=max(wind_speed_max, na.rm=TRUE), .groups="drop")
    } else if (APP_DATA$mode == "cache") {
      cities_sel <- .get_cities("wind")
      APP_DATA$wind_city[APP_DATA$wind_city$city %in% cities_sel, ]
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
      cities_sel <- .get_cities("wind")
      APP_DATA$humidity_city[APP_DATA$humidity_city$city %in% cities_sel, ]
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
'@

$content = Get-Content shiny/app.R -Raw
$content = $content -replace '(?s)  output\ <- renderPlotly\(\{.*?(?=  # ── Prediction \(LAZY LOADING\) ─────────────────────────────)', ($code + "
")
Set-Content shiny/app.R $content
