# set memory
options(java.parameters = "-Xmx4G")

# libraries
library(r5r)
library(tidyverse)
library(sfarrow)
library(sf)

# data
centroids <- st_read_parquet('./data/centroids.parquet')
hexagons <- st_read_parquet('./data/hexagons.parquet')

# a little bit of clean up
centroids <- st_transform(centroids, crs = 4326)

centroids <- centroids %>%
  mutate(lon = unlist(map(centroids$geometry,1)),
         lat = unlist(map(centroids$geometry,2)))
centroids <- centroids %>% rename(id = oriID)
centroids <- st_set_geometry(centroids,NULL)

# r5r setup
r5r_core <- setup_r5('./data/pbf', elevation = 'TOBLER', overwrite = T)


# generate origin-destination matrices
departure_datetime <- as.POSIXct("13-05-2019 14:00:00",
                                 format = "%d-%m-%Y %H:%M:%S")

# for adults
adults_15 <- travel_time_matrix(r5r_core = r5r_core,
                                 origins = centroids,
                                 destinations = centroids,
                                 mode = 'WALK',
                                 departure_datetime = departure_datetime,
                                 max_walk_dist = 2000,
                                 max_trip_duration = 15,
                                 verbose = FALSE,
                                 walk_speed = 4.5
)

# for seniors
seniors_15 <- travel_time_matrix(r5r_core = r5r_core,
                                 origins = centroids,
                                 destinations = centroids,
                                 mode = 'WALK',
                                 departure_datetime = departure_datetime,
                                 max_walk_dist = 2000,
                                 max_trip_duration = 15,
                                 verbose = FALSE,
                                 walk_speed = 3.2
)

# resetting
stop_r5(r5r_core)
rJava::.jgc(R.gc = TRUE)

# rearrange data and calculate access scores
access_adults = adults_15 %>% group_by(from_id) %>% summarise(n = n())
access_seniors = seniors_15 %>% group_by(from_id) %>% summarise(n = n())

access_scores = merge(hexagons, access_adults, by.x = 'hex_id', by.y = 'from_id')
access_scores = access_scores %>% rename("n_adults" = "n")
access_scores = merge(access_scores, access_seniors, by.x = 'hex_id', by.y = 'from_id')
access_scores = access_scores %>% rename('n_seniors' = 'n')

access_scores = access_scores %>% select('hex_id', 'n_adults', 'n_seniors', 'geometry')

# save results
st_write_parquet(access_scores, './results/access_scores.parquet')
