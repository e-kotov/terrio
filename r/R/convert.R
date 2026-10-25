# Conversions between the standalone representation and 'sf'. 'sf' is
# optional: the core package loads and reads without it.

.require_sf <- function() {
  if (!requireNamespace("sf", quietly = TRUE)) {
    stop("converting to or from 'sf' needs the 'sf' package; install it with install.packages('sf')",
      call. = FALSE
    )
  }
  sf <- asNamespace("sf")
  # 'sf' classes without a GDAL-linked load are fine; the namespace load is
  # all the conversion needs.
  sf
}

# The CRS of a `terrio_layer`: 'sf' takes WKT (or an EPSG code when the WKT is
# unknown). Returns a 'sf' crs object, or NA_crs_ when the layer has none.
.terrio_sf_crs <- function(x) {
  sf <- .require_sf()
  wkt <- attr(x, "crs_wkt")
  epsg <- attr(x, "crs_epsg")
  if (!is.null(wkt)) {
    sf::st_crs(wkt)
  } else if (!is.null(epsg)) {
    sf::st_crs(as.integer(epsg))
  } else {
    sf::st_crs(NA)
  }
}

#' Convert to an 'sf' object
#'
#' Converts a `terrio_layer` to an 'sf' object, through its WKB geometries.
#' Needs the 'sf' package (Suggests); the core package reads without it.
#'
#' The CRS comes from the layer's WKT (or EPSG code). Features without a
#' geometry keep their attributes with an empty geometry collection; empty geometries
#' keep their WKB. sf conversion collapses the null/empty distinction.
#'
#' @param x A `terrio_layer` object.
#' @param ... Unused.
#' @return An 'sf' object with the layer's attributes and geometry.
#'
#' @seealso [as_terrio()], [read_sf()]
#' @export
as_sf <- function(x, ...) {
  UseMethod("as_sf")
}

#' @export
as_sf.terrio_layer <- function(x, ...) {
  sf <- .require_sf()
  # The geometry column of a read object, or the attribute of a manually
  # built one.
  geom <- x[["geometry"]]
  if (is.null(geom)) {
    geom <- attr(x, "geometry", exact = TRUE)
  }
  attrs <- x[, setdiff(names(x), "geometry"), drop = FALSE]
  class(attrs) <- "data.frame"
  if (is.null(geom)) {
    stop("the object has no geometry column", call. = FALSE)
  }
  # WKB raw vectors; NULL elements (features without a geometry) become NA
  # geometries, matching 'sf's representation of missing geometry.
  # Decode the whole WKB vector in one native call. NULL has no sf
  # equivalent: explicitly map it to an empty geometry collection.
  geom <- unclass(geom)
  missing <- vapply(geom, is.null, logical(1))
  geom[missing] <- rep(list(sf::st_as_binary(sf::st_geometrycollection())), sum(missing))
  sfc <- sf::st_as_sfc(structure(geom, class = "WKB"), crs = .terrio_sf_crs(x))
  sf::st_sf(attrs, geometry = sfc)
}

#' @export
as_sf.default <- function(x, ...) {
  stop("as_sf() expects a terrio_layer object; got class '", paste(class(x), collapse = ", "), "'",
    call. = FALSE
  )
}

# The terrio field type of an R column, for `as_terrio` from 'sf'. R Date and
# POSIXct columns are formatted to the ISO-8601 strings the engine stores
# (dates keep "%Y-%m-%d", datetimes keep their offset); the returned function
# formats the column.
.sf_column_type <- function(col) {
  if (!is.null(dim(col)) || inherits(col, "integer64")) {
    stop("matrix/array and integer64 columns are unsupported; convert explicitly without losing precision", call. = FALSE)
  }
  if (is.factor(col)) {
    return(list(type = "Text", convert = as.character))
  }
  if (inherits(col, "POSIXct") || inherits(col, "POSIXt")) {
    return(list(
      type = "DateTime",
      convert = function(x) {
        if (any(!is.na(x) & as.numeric(x) %% 1 != 0)) {
          stop("fractional POSIXct seconds are unsupported; supply ISO-8601 text explicitly", call. = FALSE)
        }
        format(x, "%Y-%m-%dT%H:%M:%S%z")
      }
    ))
  }
  if (inherits(col, "Date")) {
    return(list(type = "Date", convert = function(x) format(x, "%Y-%m-%d")))
  }
  if (is.logical(col)) {
    return(list(type = "Boolean", convert = NULL))
  }
  if (is.integer(col)) {
    return(list(type = "Integer", convert = NULL))
  }
  if (is.numeric(col) && !is.object(col)) {
    return(list(type = "Float", convert = NULL))
  }
  if (is.character(col)) {
    return(list(type = "Text", convert = NULL))
  }
  if (is.list(col) && all(vapply(col, function(e) is.null(e) || is.raw(e), logical(1)))) {
    return(list(type = "Blob", convert = NULL))
  }
  list(type = NULL, convert = NULL)
}

#' Convert to a `terrio_layer`
#'
#' Converts 'sf' data or an 'sf' geometry column into the standalone data
#' representation: a `data.frame` of class `terrio_layer` with WKB geometries
#' and CRS metadata. 'sf' is needed for the conversion; the resulting object
#' is standalone.
#'
#' R Date and POSIXct columns are formatted to ISO-8601 `character` (the field
#' types are recorded in `terrio_field_types` so [write_sf()] writes them
#' back); factors become text; integer columns keep R `integer` (64-bit
#' integers from other sources are R `double`); unsupported column types fail
#' with an explicit error.
#'
#' @param x An 'sf' object, an 'sfc' geometry column, or a `terrio_layer`
#'   (returned as-is).
#' @param layer The layer name; the default is `"layer"` for 'sf' input.
#' @return A `data.frame` of class `terrio_layer`.
#'
#' @seealso [as_sf()], [write_sf()]
#' @export
as_terrio <- function(x, layer = NULL) {
  UseMethod("as_terrio")
}

#' @export
as_terrio.terrio_layer <- function(x, layer = NULL) {
  if (!is.null(layer)) {
    attr(x, "layer_name") <- layer
  }
  x
}

#' @export
as_terrio.sf <- function(x, layer = NULL) {
  geom <- sf::st_geometry(x)
  attrs <- sf::st_drop_geometry(x)
  out <- .as_terrio_from_parts(attrs, geom, layer %||% "layer")
  # Preserve the original attribute names (st_sf renames the geometry column).
  out
}

#' @export
as_terrio.sfc <- function(x, layer = NULL) {
  .as_terrio_from_parts(NULL, x, layer %||% "layer")
}

#' @export
as_terrio.default <- function(x, layer = NULL) {
  stop("as_terrio() expects an 'sf' object, an 'sfc' column or a terrio_layer; got class '",
    paste(class(x), collapse = ", "), "'",
    call. = FALSE
  )
}

.as_terrio_from_parts <- function(attrs, geom, layer_name) {
  sf <- .require_sf()
  n <- length(geom)
  # WKB raw vectors; missing geometries (NA) become NULL elements.
  geometry <- lapply(geom, function(g) if (length(g) == 1L && is.na(g)) NULL else sf::st_as_binary(g))
  geometry <- lapply(geometry, function(e) if (is.null(e) || (length(e) == 1L && is.na(e))) NULL else e)
  columns <- list()
  types <- character()
  if (!is.null(attrs) && ncol(attrs) > 0L) {
    if (anyDuplicated(names(attrs)) || "geometry" %in% names(attrs)) {
      stop("attribute names must be unique; 'geometry' is reserved for WKB", call. = FALSE)
    }
    if (nrow(attrs) != n) {
      stop("attributes have ", nrow(attrs), " rows but the geometry column has ", n, " features",
        call. = FALSE
      )
    }
    for (nm in names(attrs)) {
      spec <- .sf_column_type(attrs[[nm]])
      if (is.null(spec$type)) {
        stop("column '", nm, "': unsupported R type '", paste(class(attrs[[nm]]), collapse = ","),
          "'; supported: logical, integer, numeric, character, Date, POSIXct, factor, raw lists",
          call. = FALSE
        )
      }
      col <- attrs[[nm]]
      if (!is.null(spec$convert)) {
        col <- spec$convert(col)
      }
      columns[[nm]] <- col
      types <- c(types, paste0(nm, "/", spec$type))
    }
  }
  # A named list, even when empty; the geometry list is a column, like in the
  # read path.
  columns <- as.list(columns)
  columns$geometry <- geometry
  names(columns) <- c(vapply(types, function(t) sub("/[^/]*$", "", t), character(1)), "geometry")
  crs <- sf::st_crs(geom)
  if (is.null(crs) || is.na(crs)) {
    crs_wkt <- NULL
    crs_epsg <- NULL
    crs_str <- NULL
  } else {
    crs_wkt <- crs$wkt
    crs_epsg <- if (is.na(crs$epsg)) NULL else crs$epsg
    # The same string the read path reports: EPSG code when known, else WKT.
    crs_str <- if (!is.null(crs_epsg)) paste0("EPSG:", crs_epsg) else crs$wkt
  }
  l <- list(
    layer_name = layer_name,
    driver = "sf",
    geometry_type = "Unknown",
    crs = if (is.null(crs_wkt) && is.null(crs_epsg)) NULL else (crs_epsg %||% crs_wkt),
    crs_epsg = crs_epsg,
    crs_wkt = crs_wkt,
    fields = types,
    columns = columns,
    geometry = geometry,
    n_features = n
  )
  cols <- lapply(l$columns, function(c) if (is.list(c)) I(c) else c)
  df <- as.data.frame(cols, stringsAsFactors = FALSE, optional = TRUE)
  attr(df, "row.names") <- .set_row_names(n)
  class(df) <- c("terrio_layer", "data.frame")
  attr(df, "terrio_field_types") <- l$fields
  attr(df, "crs") <- crs_str
  attr(df, "crs_wkt") <- crs_wkt
  attr(df, "crs_epsg") <- crs_epsg
  attr(df, "driver") <- l$driver
  attr(df, "layer_name") <- l$layer_name
  attr(df, "geometry_type") <- l$geometry_type
  attr(df, "bbox") <- NULL
  attr(df, "n_features") <- n
  df
}
