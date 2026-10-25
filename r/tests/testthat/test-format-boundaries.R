test_that("Shapefile driver aliases cannot bypass existing output checks", {
  skip_if_not_installed("sf")
  dir <- tempfile(); dir.create(dir)
  p <- file.path(dir, "protected.shp")
  x <- .point_fixture(id = 1:2)
  write_sf(x, p)
  dbf <- sub("shp$", "dbf", p)
  before <- readBin(dbf, "raw", file.info(dbf)$size)
  x$id <- c(999L, 1000L)
  for (alias in c("ESRI Shapefile", "shapefile", "shp", "esri_shapefile")) {
    expect_error(write_sf(x, sub("shp$", "any", p), driver = alias), "extension")
    expect_identical(readBin(dbf, "raw", file.info(dbf)$size), before)
    expect_error(write_sf(x, p, driver = alias), "already exists")
  }
  # Sidecars alone, including uppercase names, also identify an existing set.
  q <- file.path(dir, "other.shp")
  writeLines("sentinel", file.path(dir, "other.DBF"))
  expect_error(write_sf(x, q), "already exists")
  expect_identical(readLines(file.path(dir, "other.DBF")), "sentinel")
  expect_error(write_sf(x, file.path(dir, "new.SHP")), "lowercase")
})

test_that("GeoJSON unsigned and larger integer lexemes fail before engine coercion", {
  p <- tempfile(fileext = ".geojson")
  json <- function(value) paste0('{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"i":', value, '},"geometry":{"type":"Point","coordinates":[1,2]}}]}')
  for (value in c("9007199254740993", "9223372036854775808", "18446744073709551615", "184467440737095516160", "-9223372036854775808")) {
    writeLines(json(value), p)
    expect_error(read_sf(p), "integer lexeme beyond 2\\^53")
  }
  writeLines(json('"18446744073709551615"'), p)
  expect_identical(read_sf(p)$i, "18446744073709551615")
  writeLines(json("9007199254740992"), p)
  expect_identical(read_sf(p)$i, 2^53)
})

test_that("unsigned source columns cannot wrap into signed integer values", {
  for (f in c("uint64-max.fgb", "uint64-max.parquet")) {
    expect_error(read_sf(test_path("fixtures", f)), "unsigned 64-bit")
  }
})

test_that("DBF integer overflow is rejected before becoming missing", {
  skip_if_not_installed("sf")
  p <- tempfile(fileext = ".shp")
  sf::st_write(sf::st_sf(id = 1L, geometry = sf::st_sfc(sf::st_point(c(1, 2)), crs = 4326)), p, quiet = TRUE)
  dbf <- sub("shp$", "dbf", p)
  original <- readBin(dbf, "raw", file.info(dbf)$size)
  header_size <- readBin(original[9:10], "integer", n = 1, size = 2, endian = "little", signed = FALSE)
  header <- original[seq_len(header_size)]
  expect_identical(header[44], charToRaw("N"))
  header[11:12] <- writeBin(21L, raw(), size = 2, endian = "little")
  header[49] <- as.raw(20)
  header[50] <- as.raw(0)
  set_value <- function(value) writeBin(c(header, charToRaw(" "), charToRaw(sprintf("%20s", value)), as.raw(26)), dbf)
  for (value in c("18446744073709551615", "-9223372036854775808", "9007199254740993")) {
    set_value(value)
    expect_error(read_sf(p), "DBF integer.*2\\^53")
  }
  set_value("9007199254740992")
  expect_identical(read_sf(p)$id, 2^53)
})

test_that("GeoJSON rejects custom CRS but other supported formats retain it", {
  skip_if_not_installed("sf")
  x <- sf::st_sf(id = 1:2, geometry = sf::st_sfc(sf::st_point(c(1, 2)), sf::st_point(c(3, 4)), crs = sf::st_crs("+proj=aeqd +lat_0=45 +lon_0=10 +datum=WGS84 +units=m +no_defs")))
  for (ext in c("geojson", "geojsonl")) {
    p <- tempfile(fileext = paste0(".", ext))
    expect_error(write_sf(x, p, driver = if (ext == "geojson") "GeoJSON" else "GeoJSONSeq"), "explicit EPSG CRS")
    expect_false(file.exists(p))
  }
  p <- tempfile(fileext = ".gpkg")
  write_sf(x, p)
  expect_true(sf::st_crs(as_sf(read_sf(p))) == sf::st_crs(x))
})

test_that("Shapefile lowering is rejected before creating output", {
  skip_if_not_installed("sf")
  x <- .point_fixture(id = 1:2)
  bad <- list(
    sf::st_sf(id = 1L, geometry = sf::st_sfc(sf::st_point(c(1, 2, 3)), crs = 4326)),
    .point_fixture(name = c(strrep("a", 300), "b")),
    .point_fixture(name = c(strrep("\u6771\u4eac", 43), "b")),
    .point_fixture(long_field_name = 1:2),
    .point_fixture(blob = I(list(as.raw(1), as.raw(2)))),
    .point_fixture(time = as.POSIXct(c(0, 1), origin = "1970-01-01", tz = "UTC")),
    .point_fixture(value = c(.1234567891234567, 2)),
    .point_fixture(name = c("trailing ", "normal")),
    .point_fixture(name = c("", "normal")),
    .point_fixture(name = c("***", "normal"))
  )
  for (obj in bad) {
    p <- tempfile(fileext = ".shp")
    expect_error(write_sf(obj, p), "Shapefile")
    expect_false(file.exists(p))
    expect_false(file.exists(sub("shp$", "dbf", p)))
  }
})

test_that("GeoJSON refuses Blob lowering and ambiguous all-null field types", {
  skip_if_not_installed("sf")
  for (x in list(.point_fixture(blob = I(list(as.raw(1), NULL))), .point_fixture(i = c(NA_integer_, NA_integer_)))) {
    p <- tempfile(fileext = ".geojson")
    expect_error(write_sf(x, p), "GeoJSON")
    expect_false(file.exists(p))
  }
})

test_that("canonical XY and XYZ empties are refused consistently before writing", {
  skip_if_not_installed("sf")
  wkts <- c("POINT EMPTY", "LINESTRING EMPTY", "POLYGON EMPTY", "MULTIPOINT EMPTY", "MULTILINESTRING EMPTY", "MULTIPOLYGON EMPTY", "GEOMETRYCOLLECTION EMPTY",
    "POINT Z EMPTY", "LINESTRING Z EMPTY", "POLYGON Z EMPTY", "MULTIPOINT Z EMPTY", "MULTILINESTRING Z EMPTY", "MULTIPOLYGON Z EMPTY", "GEOMETRYCOLLECTION Z EMPTY")
  for (wkt in wkts) {
    x <- sf::st_sf(id = 1L, geometry = sf::st_as_sfc(wkt, crs = 4326))
    for (ext in c("gpkg", "fgb", "parquet", "geojson", "shp")) {
      p <- tempfile(fileext = paste0(".", ext))
      expect_error(write_sf(x, p), "null/empty")
      expect_false(file.exists(p))
    }
  }
})

test_that("independent null/empty inputs error instead of collapsing geometry state", {
  skip_if_not_installed("sf")
  p <- tempfile(fileext = ".geojson")
  for (geom in c('null', '{"type":"Point","coordinates":[]}')) {
    writeLines(paste0('{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"id":1},"geometry":', geom, '}]}'), p)
    expect_error(read_sf(p))
  }
  for (file in c("engine-empty-linestring.fgb", "engine-null-geometry.parquet")) {
    expect_error(read_sf(test_path("fixtures", file)), "null/empty")
  }
  for (ext in "gpkg") {
    for (wkt in c("POINT EMPTY", "LINESTRING EMPTY", "LINESTRING Z EMPTY")) {
      x <- sf::st_sf(id = 1L, geometry = sf::st_as_sfc(wkt, crs = 4326))
      p <- tempfile(fileext = paste0(".", ext))
      sf::st_write(x, p, quiet = TRUE)
      expect_error(read_sf(p), "null/empty")
    }
  }
})
