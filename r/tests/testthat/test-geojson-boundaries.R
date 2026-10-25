test_that("GeoJSONSeq never silently reprojects accepted output", {
  skip_if_not_installed("sf")
  x <- sf::st_sf(id = 1L, geometry = sf::st_sfc(sf::st_point(c(1234, 5678)), crs = 3857))
  seq <- tempfile(fileext = ".geojsonl")
  expect_error(write_sf(x, seq, driver = "GeoJSONSeq"), "EPSG:4326")
  expect_false(file.exists(seq))
  # Ordinary GeoJSON can name this EPSG and must retain the actual numbers.
  json <- tempfile(fileext = ".geojson")
  write_sf(x, json)
  y <- as_sf(read_sf(json))
  expect_true(sf::st_crs(y) == sf::st_crs(x))
  expect_identical(sf::st_coordinates(y), sf::st_coordinates(x))
  wgs <- sf::st_sf(id = 1L, geometry = sf::st_sfc(sf::st_point(c(1, 2)), crs = 4326))
  write_sf(wgs, seq, driver = "GeoJSONSeq")
  expect_identical(sf::st_coordinates(as_sf(read_sf(seq))), sf::st_coordinates(wgs))
})

test_that("zero-feature GeoJSON refuses schema loss while preserving formats work", {
  skip_if_not_installed("sf")
  x <- .point_fixture(id = 1:2, name = c("a", "b"))[0, ]
  for (ext in c("geojson", "geojsonl")) {
    p <- tempfile(fileext = paste0(".", ext))
    expect_error(write_sf(x, p), "zero-feature")
    expect_false(file.exists(p))
  }
  for (ext in c("gpkg", "fgb", "parquet")) {
    p <- tempfile(fileext = paste0(".", ext))
    write_sf(x, p)
    y <- read_sf(p)
    expect_identical(y$id, integer())
    expect_identical(y$name, character())
    expect_identical(attr(y, "terrio_field_types"), c("id/Integer", "name/Text"))
  }
})

test_that("known date-looking Text is not silently retyped by GeoJSON", {
  skip_if_not_installed("sf")
  for (text in c("2024-01-01", "2024-01-01T00:00:00Z", "2024-01-01 00:00:00", "2024-01-01-label")) {
    x <- .point_fixture(name = c(text, "plain"))
    for (ext in c("geojson", "geojsonl")) {
      p <- tempfile(fileext = paste0(".", ext))
      expect_error(write_sf(x, p), "YYYY-MM-DD")
      expect_false(file.exists(p))
    }
    p <- tempfile(fileext = ".gpkg")
    write_sf(x, p)
    y <- read_sf(p)
    expect_identical(y$name, x$name)
    expect_identical(attr(y, "terrio_field_types"), "name/Text")
  }
})
