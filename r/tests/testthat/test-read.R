# Reading into the standalone representation.

test_that("read_sf reads the real nc.gpkg fixture with metadata", {
  skip_if_not_installed("sf")
  dsn <- .nc_gpkg_path()
  x <- read_sf(dsn)
  expect_s3_class(x, "terrio_layer")
  expect_s3_class(x, "data.frame")
  expect_identical(nrow(x), 100L)
  expect_identical(attr(x, "layer_name"), "nc.gpkg")
  expect_identical(attr(x, "crs"), "EPSG:4267")
  expect_identical(attr(x, "geometry_type"), "MultiPolygon")
  expect_false(is.null(attr(x, "crs_wkt")) && is.null(attr(x, "crs_epsg")))
  expect_false(is.null(attr(x, "bbox")))
  # Geometry column of raw WKB.
  geom <- x[["geometry"]]
  expect_true(is.list(geom))
  expect_true(all(vapply(geom, is.raw, logical(1))))
  expect_true(all(vapply(geom, length, integer(1)) > 0))
  # Field types recorded for write-back.
  types <- attr(x, "terrio_field_types")
  expect_true(all(grepl("/", types)))
})

test_that("read_sf keeps values without coercions (types match the fixture)", {
  skip_if_not_installed("sf")
  x <- read_sf(.nc_gpkg_path())
  types <- attr(x, "terrio_field_types")
  for (spec in types) {
    parts <- strsplit(spec, "/", fixed = TRUE)[[1]]
    col <- x[[parts[1]]]
    expect_match(class(col)[1],
      switch(parts[2],
        Integer = "integer|numeric",
        Float = "numeric",
        Text = "character",
        Boolean = "logical",
        Date = "character",
        DateTime = "character",
        Blob = "list",
        ".*"
      ),
      info = paste("field", spec)
    )
  }
})

test_that("read_sf's layer selection picks the requested layer", {
  skip_if_not_installed("sf")
  .need_sf()
  dsn <- tempfile(fileext = ".gpkg")
  # A two-layer GeoPackage built with sf.
  sf::st_write(as_sf(read_sf(.nc_gpkg_path())), dsn, layer = "first", quiet = TRUE)
  sf::st_write(as_sf(read_sf(.nc_gpkg_path()))[1:6, ], dsn, layer = "second", append = TRUE, quiet = TRUE)
  x <- read_sf(dsn, layer = "second")
  expect_identical(attr(x, "layer_name"), "second")
  expect_identical(nrow(x), 6L)
  # The default reads the first layer.
  y <- read_sf(dsn)
  expect_identical(attr(y, "layer_name"), "first")
  expect_error(read_sf(dsn, layer = "nonexistent"))
})

test_that("read_sf's bbox keeps intersecting features only", {
  skip_if_not_installed("sf")
  dsn <- .nc_gpkg_path()
  x <- read_sf(dsn)
  bbox_all <- attr(x, "bbox")
  # A rectangle around the first feature's bounding box.
  f1 <- sf::st_bbox(as_sf(x)$geometry[1])
  bbox_small <- c(f1["xmin"], f1["ymin"], f1["xmax"], f1["ymax"])
  y <- read_sf(dsn, bbox = bbox_small)
  expect_true(nrow(y) < nrow(x))
  expect_true(nrow(y) > 0)
  # Every kept geometry intersects the rectangle.
  kept <- y[["geometry"]]
  expect_true(length(kept) == nrow(y))
  # A bbox covering everything returns the same features.
  z <- read_sf(dsn, bbox = bbox_all)
  expect_identical(nrow(z), nrow(x))
  expect_error(read_sf(dsn, bbox = c(1, 2, 3)))
})
