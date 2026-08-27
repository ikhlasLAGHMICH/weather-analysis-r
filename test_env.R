source('shiny/app.R')
print('Data loaded OK.')
cat('Daily rows: ', nrow(APP_DATA$daily), '\n')
cat('Monthly rows: ', nrow(APP_DATA$monthly), '\n')
