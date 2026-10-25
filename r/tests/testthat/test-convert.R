# Conversions between the standalone representation and 'sf'.

test_that("as_sf converts the nc fixture with CRS, attributes and geometry", {
  skip_if_not_installed("sf")
  x <- read_sf(.nc_gpkg_path())
  sf_x <- as_sf(x)
  expect_s3_class(sf_x, "sf")
  expect_identical(nrow(sf_x), 100L)
  expect_identical(sf::st_crs(sf_x)$epsg, 4267L)
  expect_true("AREA" %in% names(sf_x))
  expect_s3_class(sf_x$geometry, "sfc")
  # Geometries match sf's own read of the same file (WKB-level).
  sf_read <- sf::st_read(.nc_gpkg_path(), quiet = TRUE)
  expect_identical(sf::st_as_binary(sf::st_geometry(sf_x))[[1]], sf::st_as_binary(sf::st_geometry(sf_read))[[1]])
})

test_that("as_terrio converts sf back with field types and geometry", {
  skip_if_not_installed("sf")
  sf_x <- as_sf(read_sf(.nc_gpkg_path()))
  x <- as_terrio(sf_x, layer = "nc")
  expect_s3_class(x, "terrio_layer")
  expect_identical(attr(x, "layer_name"), "nc")
  expect_identical(attr(x, "crs"), "EPSG:4267")
  expect_true(is.raw(x[["geometry"]][[1]]))
  # Round trip through the engine keeps values and WKB.
  orig <- read_sf(.nc_gpkg_path())
  expect_identical(x$AREA, orig$AREA)
  expect_identical(x[["geometry"]], orig[["geometry"]])
})

test_that("as_terrio maps R Date and POSIXct columns to ISO strings with types", {
  skip_if_not_installed("sf")
  .need_sf()
  sf_x <- sf::st_sf(
    d = as.Date(c("2024-01-01", "2024-06-15")),
    t = as.POSIXct(c("2024-01-01 12:00:00", "2024-06-15 08:30:00"), tz = "UTC"),
    geometry = sf::st_sfc(sf::st_point(c(0, 0)), sf::st_point(c(1, 1)), crs = 4326)
  )
  x <- as_terrio(sf_x)
  types <- attr(x, "terrio_field_types")
  expect_true("d/Date" %in% types)
  expect_true("t/DateTime" %in% types)
  expect_identical(x$d, c("2024-01-01", "2024-06-15"))
  expect_match(x$t[1], "^2024-01-01T12:00:00")
})

test_that("as_terrio errors on unsupported column types explicitly", {
  skip_if_not_installed("sf")
  sf_x <- sf::st_sf(
    lst = I(list(data.frame(a = 1))),
    geometry = sf::st_sfc(sf::st_point(c(0, 0)), crs = 4326)
  )
  expect_error(as_terrio(sf_x))
})

test_that("as_sf and as_terrio error on wrong input classes", {
  skip_if_not_installed("sf")
  expect_error(as_sf(data.frame(a = 1)))
  expect_error(as_terrio(list(a = 1)))
})

test_that("the edge layer converts to sf and back with null and empty geometries", {
  skip_if_not_installed("sf")
  x <- .edge_layer(missing = TRUE)
  sf_x <- as_sf(x)
  expect_s3_class(sf_x, "sf")
  expect_identical(nrow(sf_x), 6L)
  expect_identical(sf::st_crs(sf_x)$epsg, 4326L)
  # Known policy: st_sfc represents a missing geometry as an empty geometry,
  # so a null geometry converts to the empty representation of sf.
  expect_true(sf::st_is_empty(sf_x$geometry[1]))
  expect_true(sf::st_is_empty(sf_x$geometry[3]))
  back <- as_terrio(sf_x, layer = "edge")
  expect_s3_class(back, "terrio_layer")
  expect_identical(nrow(back), 6L)
  expect_true(is.raw(back[["geometry"]][[1]]))
})
