# Layer listing.

test_that("terrio_layers lists the names of a GeoPackage", {
  skip_if_not_installed("sf")
  dsn <- .nc_gpkg_path()
  layers <- terrio_layers(dsn)
  expect_s3_class(layers, "data.frame")
  expect_true("layer" %in% names(layers))
  expect_true(nrow(layers) >= 1L)
})

test_that("terrio_layers(detailed=TRUE) reports counts, types, CRS and fields", {
  skip_if_not_installed("sf")
  dsn <- .nc_gpkg_path()
  s <- terrio_layers(dsn, detailed = TRUE)
  expect_s3_class(s, "data.frame")
  expect_true(all(c("layer", "n_features", "geometry_type", "crs", "fields") %in% names(s)))
  expect_true(all(s$n_features > 0))
  expect_true(all(grepl("EPSG:", s$crs)))
  # The engine reads attributes and geometries with their CRS metadata.
  expect_true(all(grepl("/(Float|Integer|Text)", s$fields)))
})

test_that("terrio_layers on a missing file fails with an explicit error", {
  expect_error(terrio_layers(tempfile("missing", fileext = ".gpkg")))
})
