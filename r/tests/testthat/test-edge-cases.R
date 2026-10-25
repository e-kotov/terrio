# Synthetic edge cases: null vs empty geometries, value policies, UTF-8,
# formats beyond GeoPackage.

test_that("the synthetic edge layer round trips values exactly", {
  skip_if_not_installed("sf")
  x <- .edge_layer()
  # GPKG preserves SQL Date fields, but rejects null/empty geometry in this
  # prototype. Use ordinary independent point WKB for this value/schema test.
  geom <- attr(x, "geometry")
  geom[[1]] <- sf::st_as_binary(sf::st_point(c(-1, -1)))
  geom[[3]] <- sf::st_as_binary(sf::st_point(c(.5, .5)))
  attr(x, "geometry") <- geom
  gpkg <- tempfile(fileext = ".gpkg")
  write_sf(x, gpkg, layer = "edge")
  y <- read_sf(gpkg)
  expect_identical(nrow(y), 6L)
  expect_identical(attr(y, "terrio_field_types"), attr(x, "terrio_field_types"))
  expect_identical(y$flag, x$flag)
  expect_identical(y$small, x$small)
  expect_identical(y$big, x$big) # int64 above 2^31, held as double
  expect_identical(y$when, x$when) # ISO-8601 strings, no Date coercion
  expect_identical(y$name, x$name) # NA and UTF-8 kept
  expect_identical(attr(y, "crs"), "EPSG:4326")
})

test_that("null/empty I/O is refused until the engine preserves state and dimensions", {
  skip_if_not_installed("sf")
  for (ext in c("gpkg", "geojson", "fgb", "parquet", "shp")) {
    p <- tempfile(fileext = paste0(".", ext))
    expect_error(write_sf(.edge_layer(missing = TRUE), p), "null/empty")
    expect_false(file.exists(p))
  }
})

test_that("other supported formats round trip", {
  skip_if_not_installed("sf")
  x <- .edge_layer()
  for (ext in c("geojson", "fgb")) {
    dsn <- tempfile(fileext = paste0(".", ext))
    write_sf(x, dsn)
    y <- read_sf(dsn)
    expect_identical(nrow(y), 6L, info = ext)
    # FlatGeobuf spatial indexing may reorder features; align by the unique
    # small field (including its single NA) before comparing text values.
    expect_identical(y$name[match(x$small, y$small)], x$name, info = ext)
  }
})

test_that("GeoParquet round trips through the engine", {
  skip_if_not_installed("sf")
  x <- read_sf(.nc_gpkg_path())
  pq <- tempfile(fileext = ".parquet")
  write_sf(x, pq, driver = "GeoParquet")
  y <- read_sf(pq)
  expect_identical(nrow(y), 100L)
  expect_identical(attr(y, "crs"), "EPSG:4267")
  expect_identical(y$AREA, x$AREA)
  expect_identical(y$NAME, x$NAME)
  expect_identical(y[["geometry"]], x[["geometry"]])
})

test_that("integer representation policy: int32 stays integer, int64 becomes double", {
  skip_if_not_installed("sf")
  # The real fixture: an int32 field stays R integer.
  x <- read_sf(.nc_gpkg_path())
  expect_true(is.integer(x$CRESS_ID))
  # The edge fixture: int64 values above 2^31 come back as double.
  fgb <- tempfile(fileext = ".fgb")
  write_sf(.edge_layer(), fgb)
  y <- read_sf(fgb)
  expect_true(is.integer(y$small))
  expect_true(is.double(y$big))
})
