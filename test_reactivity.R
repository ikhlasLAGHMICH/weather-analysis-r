library(shiny)
library(dplyr)
library(plotly)

city_order <- c("Paris", "Lille")
APP_DATA <- list(
  mode = "db",
  monthly = data.frame(
    city = rep(c("Paris", "Lille"), each = 20),
    date = rep(seq(as.Date("2021-01-01"), by = "month", length.out = 20), 2),
    temperature_mean = runif(40, 5, 25)
  )
)

ui <- fluidPage(
  selectInput("cities_temp", "Villes", choices = city_order, selected = city_order, multiple = TRUE),
  dateRangeInput("date_temp", "Dates", start = "2021-01-01", end = "2022-08-01"),
  plotlyOutput("chart")
)

server <- function(input, output, session) {
  .get_cities <- function(p) input[[paste0("cities_", p)]]
  .get_dates <- function(p) input[[paste0("date_", p)]]
  
  .filter_monthly <- function(prefix) {
    selected_cities <- .get_cities(prefix)
    selected_dates <- .get_dates(prefix)
    req(length(selected_cities) > 0, !anyNA(selected_dates))
    
    APP_DATA$monthly |>
      dplyr::filter(city %in% !!selected_cities, date >= !!selected_dates[1], date <= !!selected_dates[2])
  }
  
  output$chart <- renderPlotly({
    d <- .filter_monthly("temp")
    req(nrow(d) > 0)
    plot_ly(d, x = ~date, y = ~temperature_mean, color = ~city, type="scatter", mode="lines")
  })
  
  observe({
    print(input$cities_temp)
    print(input$date_temp)
  })
  
  # Quit after 3 seconds for test
  observeEvent(invalidateLater(3000), { stopApp() })
}
shinyApp(ui, server)
