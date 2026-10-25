# Test helpers: fixtures shared by the regression tests.
#
# The real public fixture is `nc.gpkg`, shipped by the sf package (North
# Carolina SIDS counties). Synthetic edge cases are built
# here; no large downloads.

# Layers must be found with terrio's own read; load terrio after sf so its
# read_sf/write_sf mask sf's.
.need_sf <- function() {
  if (!requireNamespace("sf", quietly = TRUE)) {
    skip("the 'sf' package is not installed")
  }
  invisible(NULL)
}

.terrio_first <- function() {
  # Load terrio after sf inside tests.
  if (!"read_sf" %in% ls(asNamespace("terrio"))) {
    skip("terrio namespace incomplete")
  }
}

.nc_gpkg_path <- function() {
  system.file("gpkg/nc.gpkg", package = "sf")
}

# A synthetic edge-case terrio_layer: null and empty geometries, booleans,
# small and big (int64) integers, ISO date strings, NA and UTF-8 text.
.edge_layer <- function(missing = FALSE) {
  .need_sf()
  n <- 6L
  geom <- list(
    NULL, # null geometry
    sf::st_as_binary(sf::st_point(c(0, 0))),
    sf::st_as_binary(sf::st_polygon()), # empty polygon
    sf::st_as_binary(sf::st_point(c(1, 1))),
    sf::st_as_binary(sf::st_linestring(rbind(c(0, 0), c(1, 1)))),
    sf::st_as_binary(sf::st_point(c(2, 2)))
  )
  if (!missing) {
    geom[[1]] <- sf::st_as_binary(sf::st_point(c(-1, -1)))
    geom[[3]] <- sf::st_as_binary(sf::st_point(c(.5, .5)))
  }
  df <- data.frame(
    flag = c(TRUE, FALSE, NA, TRUE, FALSE, TRUE),
    small = c(1L, 2L, NA, 3L, 4L, 5L),
    big = c(2^40, 2^40 + 1, NA, 5e9, 3, 7), # int64 above 2^31
    when = c("2024-01-01", NA, "2024-06-15", "1999-12-31", "2020-02-29", "2026-10-25"),
    name = c("caf\u00e9", NA, "\u00fc", "\u6771\u4eac", "plain", "z"),
    stringsAsFactors = FALSE
  )
  attr(df, "row.names") <- .set_row_names(n)
  class(df) <- c("terrio_layer", "data.frame")
  attr(df, "terrio_field_types") <- c("flag/Boolean", "small/Integer", "big/Integer", "when/Date", "name/Text")
  attr(df, "crs_wkt") <- sf::st_crs(4326)$wkt
  attr(df, "crs_epsg") <- 4326L
  attr(df, "crs") <- "EPSG:4326"
  attr(df, "layer_name") <- "edge"
  attr(df, "geometry_type") <- "Mixed"
  attr(df, "geometry") <- geom
  attr(df, "driver") <- "manual"
  attr(df, "n_features") <- n
  df
}

.point_fixture <- function(...) {
  sf::st_sf(..., geometry = sf::st_sfc(sf::st_point(c(1, 2)), sf::st_point(c(3, 4)), crs = 4326))
}
