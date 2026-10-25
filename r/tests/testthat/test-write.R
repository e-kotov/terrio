# Writes, format round trips and the documented value policies.

test_that("write_sf and read_sf round trip the nc fixture byte-identically", {
  skip_if_not_installed("sf")
  x <- read_sf(.nc_gpkg_path())
  dsn <- tempfile(fileext = ".geojson")
  write_sf(x, dsn)
  y <- read_sf(dsn)
  expect_identical(nrow(y), nrow(x))
  expect_identical(attr(y, "terrio_field_types"), attr(x, "terrio_field_types"))
  expect_identical(y$AREA, x$AREA)
  expect_identical(y$NAME, x$NAME)
  # WKB geometries survive the round trip.
  expect_identical(y[["geometry"]], x[["geometry"]])
  # And back to GeoPackage.
  gpkg <- tempfile(fileext = ".gpkg")
  write_sf(y, gpkg, layer = "nc")
  z <- read_sf(gpkg)
  expect_identical(z[["geometry"]], x[["geometry"]])
  expect_identical(z$AREA, x$AREA)
})

test_that("write_sf accepts an sf object and keeps its CRS", {
  skip_if_not_installed("sf")
  .need_sf()
  sf_x <- as_sf(read_sf(.nc_gpkg_path()))
  dsn <- tempfile(fileext = ".gpkg")
  write_sf(sf_x, dsn, layer = "nc")
  y <- read_sf(dsn)
  expect_identical(attr(y, "crs"), "EPSG:4267")
  expect_identical(nrow(y), 100L)
  expect_identical(y[["geometry"]], read_sf(.nc_gpkg_path())[["geometry"]])
})

test_that("write_sf errors on an unguessable format explicitly", {
  skip_if_not_installed("sf")
  x <- read_sf(.nc_gpkg_path())
  expect_error(write_sf(x, tempfile(fileext = ".unknownext")))
  expect_error(write_sf(x, tempfile(fileext = ".gpkg"), driver = "Nope"))
})

test_that("int64 values above 2^53 fail instead of being lost", {
  x <- .edge_layer()
  y <- x
  y$big[1] <- 2^62
  expect_error(write_sf(y, tempfile(fileext = ".gpkg"), layer = "edge"))
})

test_that("documented type mismatches fail explicitly", {
  x <- .edge_layer()
  y <- x
  y$when <- as.Date(y$when) # a Date class where the policy keeps ISO strings
  expect_error(write_sf(y, tempfile(fileext = ".gpkg"), layer = "edge"))
  z <- x
  z$flag <- 1L # an Integer where the policy keeps Boolean
  expect_error(write_sf(z, tempfile(fileext = ".gpkg"), layer = "edge"))
})
