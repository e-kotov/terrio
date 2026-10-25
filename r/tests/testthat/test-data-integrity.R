# Data-integrity regressions, including writes rejected before
# touching a destination. Tests use an independent sf/GDAL writer for inputs.
test_that("literal NA, actual NA, empty text and Unicode remain distinct", {
  skip_if_not_installed("sf")
  x <- .point_fixture(s = c("NA", NA_character_))
  for (values in list(c("NA", NA_character_), c("", "\u6771\u4eac"))) {
    x$s <- values
    p <- tempfile(fileext = ".gpkg")
    write_sf(x, p)
    expect_identical(read_sf(p)$s, values)
  }
})

test_that("R integer sentinel and int64 minimum cannot silently lose values", {
  p <- tempfile(fileext = ".geojson")
  fixture <- function(value) paste0('{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"i":', value, '},"geometry":{"type":"Point","coordinates":[0,0]}}]}')
  writeLines(fixture("-2147483648"), p)
  expect_identical(read_sf(p)$i, -2147483648)
  writeLines(fixture("-9223372036854775808"), p)
  expect_error(read_sf(p), "beyond 2\\^53")
  for (value in c("9007199254740992", "-9007199254740992")) {
    writeLines(fixture(value), p)
    expect_identical(read_sf(p)$i, as.numeric(value))
  }
})

test_that("Integer writes reject fractions, NaN and infinity before any output", {
  skip_if_not_installed("sf")
  x <- as_terrio(.point_fixture(i = 1:2))
  for (v in c(1.9, -2.9, NaN, Inf, 2^54)) {
    x$i <- c(v, 2)
    p <- tempfile(fileext = ".fgb")
    expect_error(write_sf(x, p), "Integer|integer values")
    expect_false(file.exists(p))
  }
  x$i <- c(NA_real_, 2^40)
  p <- tempfile(fileext = ".gpkg")
  write_sf(x, p)
  expect_identical(read_sf(p)$i, x$i)
})

test_that("classed numeric storage is rejected instead of reinterpreted", {
  skip_if_not_installed("sf")
  x <- .point_fixture(i = c(1, 2))
  class(x$i) <- "integer64"
  expect_error(as_terrio(x), "integer64")
  class(x$i) <- "unsupported_numeric_class"
  expect_error(as_terrio(x), "unsupported")
})

test_that("fractional timestamps are explicitly unsupported; Date and whole seconds work", {
  skip_if_not_installed("sf")
  x <- .point_fixture(t = as.POSIXct(c(1704110400, 1704110401), origin = "1970-01-01", tz = "UTC"))
  expect_identical(as_terrio(x)$t, c("2024-01-01T12:00:00+0000", "2024-01-01T12:00:01+0000"))
  x$t[1] <- x$t[1] + .123456
  expect_error(as_terrio(x), "fractional POSIXct")
})

test_that("selection retains CRS/schema and writes match names rather than position", {
  skip_if_not_installed("sf")
  x <- as_terrio(.point_fixture(a = 1:2, b = c("x", "y")))
  y <- x[2:1, c("geometry", "b", "a"), drop = FALSE]
  expect_identical(sf::st_crs(as_sf(y))$epsg, 4326L)
  expect_null(attr(y, "bbox"))
  p <- tempfile(fileext = ".fgb")
  write_sf(y, p)
  z <- read_sf(p)
  expect_identical(z$a, c(2L, 1L))
  expect_identical(z$b, c("y", "x"))
  expect_identical(class(x[, "a", drop = FALSE]), "data.frame")
  names(x)[1] <- "renamed"
  expect_error(write_sf(x, tempfile(fileext = ".fgb")), "names differ")
})

test_that("empty conversion keeps typed attribute columns and CRS", {
  skip_if_not_installed("sf")
  x <- sf::st_sf(a = integer(), b = character(), geometry = sf::st_sfc(crs = 4326))
  y <- as_sf(as_terrio(x))
  expect_identical(y$a, integer())
  expect_identical(y$b, character())
  expect_identical(sf::st_crs(y)$epsg, 4326L)
})

test_that("slash field names work and geometry attribute collisions fail explicitly", {
  skip_if_not_installed("sf")
  x <- .point_fixture(a = 1:2)
  names(x)[1] <- "a/b"
  p <- tempfile(fileext = ".gpkg")
  write_sf(x, p)
  expect_identical(read_sf(p)[["a/b"]], 1:2)
  p <- tempfile(fileext = ".geojson")
  writeLines('{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"geometry":"text"},"geometry":{"type":"Point","coordinates":[1,2]}}]}', p)
  expect_error(read_sf(p), "reserved")
})

test_that("nullable Blob and integer replacement of Float are supported", {
  skip_if_not_installed("sf")
  x <- .point_fixture(blob = I(list(as.raw(1:3), NULL)), f = c(1.5, 2.5))
  x <- as_terrio(x)
  x$f <- 1:2
  p <- tempfile(fileext = ".gpkg")
  write_sf(x, p)
  y <- read_sf(p)
  expect_identical(unclass(y$blob), list(as.raw(1:3), NULL))
  expect_identical(y$f, c(1, 2))
})

test_that("default writes and failed replacement preserve unrelated existing layers", {
  skip_if_not_installed("sf")
  x <- .point_fixture(id = 1:2)
  p <- tempfile(fileext = ".gpkg")
  sf::st_write(x, p, layer = "one", quiet = TRUE)
  sf::st_write(x, p, layer = "unrelated", quiet = TRUE)
  before <- readBin(p, "raw", n = file.info(p)$size)
  expect_error(write_sf(x, p, layer = "new"), "already exists")
  expect_identical(readBin(p, "raw", n = file.info(p)$size), before)
  bad <- as_terrio(x); bad$geometry[[1]] <- as.raw(1:3)
  expect_error(write_sf(bad, p, overwrite = TRUE))
  expect_identical(readBin(p, "raw", n = file.info(p)$size), before)
  write_sf(x, p, layer = "replacement", overwrite = TRUE)
  expect_identical(terrio_layers(p)$layer, "replacement")
})

test_that("M reads and writes, SRID EWKB and trailing bytes fail instead of corrupting coordinates", {
  skip_if_not_installed("sf")
  for (dim in c("XYM", "XYZM")) {
    point <- if (dim == "XYM") sf::st_point(c(1, 2, 9), dim = dim) else sf::st_point(c(1, 2, 3, 9), dim = dim)
    x <- sf::st_sf(id = 1L, geometry = sf::st_sfc(point, crs = 4326))
    expect_error(write_sf(x, tempfile(fileext = ".gpkg")), "M/XYZM")
    p <- tempfile(fileext = ".gpkg")
    sf::st_write(x, p, quiet = TRUE)
    expect_error(read_sf(p), "M/XYZM")
  }
  x <- as_terrio(.point_fixture(id = 1:2))
  x$geometry <- I(unclass(sf::st_as_binary(sf::st_geometry(.point_fixture(id = 1:2)), EWKB = TRUE)))
  expect_error(write_sf(x, tempfile(fileext = ".fgb")), "EWKB")
  x <- as_terrio(.point_fixture(id = 1:2))
  x$geometry[[1]] <- c(x$geometry[[1]], as.raw(0))
  expect_error(write_sf(x, tempfile(fileext = ".fgb")), "WKB length")
})

test_that("bbox validates inputs and excludes features without geometry", {
  skip_if_not_installed("sf")
  p <- tempfile(fileext = ".fgb")
  write_sf(.edge_layer(), p)
  for (bbox in list(c(NA, 1, 2, 3), c(1, NaN, 2, 3), c(2, 1, 1, 3), c(1, 2, Inf, 3))) {
    expect_error(read_sf(p, bbox = bbox), "bbox")
  }
  expect_identical(nrow(read_sf(p, bbox = c(100L, 100L, 101L, 101L))), 0L)
})
