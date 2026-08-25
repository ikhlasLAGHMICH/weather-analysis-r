CREATE TABLE IF NOT EXISTS cities (
    city_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL
);


CREATE TABLE IF NOT EXISTS weather_hourly (
    weather_id BIGSERIAL PRIMARY KEY,

    city_id INTEGER NOT NULL
        REFERENCES cities(city_id) ON DELETE RESTRICT,

    datetime TIMESTAMP NOT NULL,

    temperature_2m DOUBLE PRECISION,
    relative_humidity_2m SMALLINT,
    precipitation DOUBLE PRECISION,
    rain DOUBLE PRECISION,
    surface_pressure DOUBLE PRECISION,
    cloud_cover SMALLINT,
    wind_speed_10m DOUBLE PRECISION,
    wind_direction_10m SMALLINT,

    year SMALLINT,
    month SMALLINT,
    day SMALLINT,
    hour SMALLINT,

    season VARCHAR(10),
    rain_flag SMALLINT,

    CONSTRAINT uq_weather_hourly
        UNIQUE (city_id, datetime),

    CONSTRAINT chk_humidity
        CHECK (relative_humidity_2m BETWEEN 0 AND 100),

    CONSTRAINT chk_cloud_cover
        CHECK (cloud_cover BETWEEN 0 AND 100),

    CONSTRAINT chk_wind_direction
        CHECK (wind_direction_10m BETWEEN 0 AND 360),

    CONSTRAINT chk_wind_speed
        CHECK (wind_speed_10m >= 0),

    CONSTRAINT chk_precipitation
        CHECK (precipitation >= 0),

    CONSTRAINT chk_rain
        CHECK (rain >= 0),

    CONSTRAINT chk_rain_flag
        CHECK (rain_flag IN (0, 1)),

    CONSTRAINT chk_month
        CHECK (month BETWEEN 1 AND 12),

    CONSTRAINT chk_hour
        CHECK (hour BETWEEN 0 AND 23),

    CONSTRAINT chk_season
        CHECK (season IN ('Winter', 'Spring', 'Summer', 'Autumn'))
);


CREATE TABLE IF NOT EXISTS weather_daily (
    daily_id BIGSERIAL PRIMARY KEY,

    city_id INTEGER NOT NULL
        REFERENCES cities(city_id) ON DELETE RESTRICT,

    date DATE NOT NULL,

    temp_min DOUBLE PRECISION,
    temp_max DOUBLE PRECISION,
    temp_mean DOUBLE PRECISION,

    humidity_mean DOUBLE PRECISION,

    precipitation_total DOUBLE PRECISION,
    rain_total DOUBLE PRECISION,

    pressure_mean DOUBLE PRECISION,
    cloud_cover_mean DOUBLE PRECISION,

    wind_speed_mean DOUBLE PRECISION,
    wind_speed_max DOUBLE PRECISION,

    rain_flag SMALLINT,

    CONSTRAINT uq_weather_daily
        UNIQUE (city_id, date),

    CONSTRAINT chk_daily_rain_flag
        CHECK (rain_flag IN (0, 1)),

    CONSTRAINT chk_daily_temperature
        CHECK (temp_min <= temp_mean AND temp_mean <= temp_max),

    CONSTRAINT chk_daily_humidity
        CHECK (humidity_mean BETWEEN 0 AND 100),

    CONSTRAINT chk_daily_non_negative
        CHECK (precipitation_total >= 0 AND rain_total >= 0
               AND wind_speed_mean >= 0 AND wind_speed_max >= 0),

    CONSTRAINT chk_daily_cloud_cover
        CHECK (cloud_cover_mean BETWEEN 0 AND 100)
);


CREATE TABLE IF NOT EXISTS predictions (
    prediction_id BIGSERIAL PRIMARY KEY,

    city_id INTEGER NOT NULL
        REFERENCES cities(city_id) ON DELETE RESTRICT,

    prediction_datetime TIMESTAMP NOT NULL,

    model_name VARCHAR(100) NOT NULL,
    target VARCHAR(50) NOT NULL,

    predicted_value DOUBLE PRECISION,
    probability DOUBLE PRECISION,

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_probability
        CHECK (
            probability IS NULL
            OR probability BETWEEN 0 AND 1
        ),

    CONSTRAINT uq_prediction
        UNIQUE (city_id, prediction_datetime, model_name, target)
);


CREATE INDEX IF NOT EXISTS idx_weather_hourly_city_datetime
    ON weather_hourly(city_id, datetime);

CREATE INDEX IF NOT EXISTS idx_weather_daily_city_date
    ON weather_daily(city_id, date);

CREATE INDEX IF NOT EXISTS idx_predictions_city_datetime
    ON predictions(city_id, prediction_datetime);
