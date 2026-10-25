# Reading vector data into the standalone R representation.

# The metadata attributes set on every `terrio_layer` object, in the order the
# Rust binding reports them.
.terrio_meta_names <- c(
  "layer_name", "driver", "geometry_type", "crs", "crs_epsg", "crs_wkt",
  "fields", "n_features"
)

# Assembles the standalone representation from the named list the binding
# returns: attribute columns plus a `geometry` list of raw WKB, and metadata
# as attributes. Missing values are `NA` (`NULL` elements for `Blob`); null
# geometries are `NULL` elements of the geometry list and stay distinct from
# empty geometries, which keep their WKB.
.assemble_layer <- function(l) {
  # List columns (raw WKB geometries, Blob fields) must stay list columns.
  cols <- lapply(l$columns, function(c) if (is.list(c)) I(c) else c)
  df <- as.data.frame(cols, stringsAsFactors = FALSE, optional = TRUE)
  attr(df, "row.names") <- .set_row_names(l$n_features)
  class(df) <- c("terrio_layer", "data.frame")
  attr(df, "terrio_field_types") <- l$fields
  attr(df, "crs") <- l$crs
  attr(df, "crs_wkt") <- l$crs_wkt
  attr(df, "crs_epsg") <- l$crs_epsg
  attr(df, "driver") <- l$driver
  attr(df, "layer_name") <- l$layer_name
  attr(df, "geometry_type") <- l$geometry_type
  attr(df, "bbox") <- l$bbox
  attr(df, "n_features") <- nrow(df)
  df
}

# The first layer name of a dataset (cheap for GeoPackage, which terrio lists
# without reading the features).
.first_layer_name <- function(dsn) {
  layers <- vec_list_layers(dsn)$layer
  if (length(layers) == 0L) {
    stop("no layers in '", dsn, "'", call. = FALSE)
  }
  layers[[1L]]
}

# The names and types of the attribute fields, as a data.frame.
.terrio_fields <- function(x) {
  spec <- attr(x, "terrio_field_types")
  if (length(spec) == 0L) {
    return(data.frame(name = character(), type = character()))
  }
  data.frame(
    name = sub("/[^/]*$", "", spec),
    type = sub("^.*/", "", spec),
    stringsAsFactors = FALSE
  )
}

#' The layers of a vector dataset
#'
#' Lists the layers of a GeoPackage, GeoJSON, Shapefile, FlatGeobuf,
#' GeoParquet or other vector file that the Terrio engine reads. For
#' GeoPackage the names are listed without reading the features; with
#' `detailed = TRUE` the requested layers are read fully and reported with
#' feature counts, geometry types, CRS and fields.
#'
#' @param dsn Dataset path.
#' @param detailed Report counts, types, CRS and fields (a full read of the
#'   requested layers) rather than only the names? Default `FALSE`.
#' @param layer With `detailed = TRUE`, only these layer names; the default
#'   reads all.
#' @return A `data.frame`: `layer` (and with `detailed = TRUE`:
#'   `n_features`, `geometry_type`, `crs`, `fields` as `name/type` entries).
#'
#' @examples
#' \dontrun{
#' terrio_layers("countries.gpkg")
#' terrio_layers("countries.gpkg", detailed = TRUE)
#' }
#' @export
terrio_layers <- function(dsn, detailed = FALSE, layer = NULL) {
  stopifnot(is.character(dsn), length(dsn) == 1L)
  if (!detailed) {
    return(vec_list_layers(dsn))
  }
  vec_layer_summaries(dsn, layer)
}

#' Read a vector layer with the Terrio engine
#'
#' Reads one layer of a supported vector file (GeoPackage, GeoJSON, Shapefile,
#' FlatGeobuf, GeoParquet) into a standalone data
#' representation, a `data.frame` of class `terrio_layer`. Attribute columns
#' keep their values without coercions, the `geometry` column holds raw WKB
#' (null/empty geometries are refused), and CRS metadata stays on the
#' object; no 'sf' classes and no GDAL are involved.
#'
#' Value policy: 64-bit integers become R `integer` when they fit a 32-bit R
#' integer, otherwise R `double` (exact up to 2^53; beyond it the read fails
#' rather than losing values). Dates and datetimes stay ISO-8601 `character`;
#' booleans become `logical`; blobs `raw`. The field types that were read stay
#' in the `terrio_field_types` attribute so [write_sf()] can write them back.
#'
#' @param dsn Dataset path with a recognized supported-format extension.
#' @param layer The layer name; the default reads the first layer.
#' @param bbox A rectangle `c(min_x, min_y, max_x, max_y)` in the layer's CRS:
#'   only features whose geometry envelopes intersect it are returned (drivers that
#'   index their features use it to skip features early).
#' @param quiet Reserved for message control; messages are not emitted yet.
#' @return A `data.frame` of class `terrio_layer`: attribute columns, a
#'   `geometry` list column of raw WKB, and metadata attributes (`crs`,
#'   `crs_wkt`, `crs_epsg`, `driver`, `layer_name`, `geometry_type`, `bbox`,
#'   `terrio_field_types`, `n_features`). See [as_sf()] to convert to 'sf'.
#'
#' @seealso [terrio_layers()], [as_sf()], [write_sf()]
#'
#' @examples
#' \dontrun{
#' nc <- read_sf("nc.gpkg")
#' nc_sf <- as_sf(nc)
#' }
#' @export
read_sf <- function(dsn, layer = NULL, bbox = NULL, quiet = TRUE) {
  stopifnot(is.character(dsn), length(dsn) == 1L)
  if (!is.null(bbox)) {
    if (!is.numeric(bbox) || length(bbox) != 4L || any(!is.finite(bbox)) ||
        bbox[1] > bbox[3] || bbox[2] > bbox[4]) {
      stop("bbox must contain four finite numbers with min_x <= max_x and min_y <= max_y", call. = FALSE)
    }
    bbox <- as.double(bbox)
  }
  if (is.null(layer)) {
    layer <- ""
  }
  .assemble_layer(vec_read(dsn, layer, bbox))
}

#' @rdname read_sf
#' @export
terrio_read <- read_sf
