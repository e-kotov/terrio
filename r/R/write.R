# Writing vector data, and the parts extraction the write shares with the
# 'sf' conversions.

# The attribute value of one row, validated against the documented policies.
# A `double` value in an Integer column is an int64 above 2^31 (the read side
# represents it that way); `character` values carry ISO-8601 dates/datetimes;
# `NULL`/`NA` become field nulls.
.terrio_validate_column <- function(col, type, name, n) {
  if (is.object(col) && !is.list(col)) {
    stop("field '", name, "': classed attribute columns require an explicit as_terrio() conversion", call. = FALSE)
  }
  if (length(col) != n) {
    stop("column '", name, "' has ", length(col), " values, expected ", n, call. = FALSE)
  }
  switch(type,
    Integer = {
      if (is.double(col)) {
        # int64 above 2^31, represented as double; check the exactness bound.
        if (any(is.nan(col) | (!is.na(col) & (!is.finite(col) | abs(col) > 2^53 | col != trunc(col))))) {
          stop("field '", name, "': Integer values must be whole finite numbers within 2^53 (or NA)",
            call. = FALSE
          )
        }
      } else if (!is.integer(col)) {
        stop("field '", name, "': Integer column must be R integer or double, not ", class(col)[1],
          call. = FALSE
        )
      }
    },
    Float = {
      if (!is.numeric(col)) stop("field '", name, "': Float column must be numeric", call. = FALSE)
      if (any(is.nan(col) | (!is.na(col) & !is.finite(col)))) {
        stop("field '", name, "': non-finite Float values other than NA are unsupported", call. = FALSE)
      }
    },
    Text = ,
    Date = ,
    DateTime = ,
    Json = if (!is.character(col)) {
      stop("field '", name, "': ", type, " column must be character, not ", class(col)[1], call. = FALSE)
    },
    Boolean = if (!is.logical(col)) {
      stop("field '", name, "': Boolean column must be logical, not ", class(col)[1], call. = FALSE)
    },
    Blob = if (!is.list(col) || any(vapply(col, function(e) !is.null(e) && !is.raw(e), logical(1)))) {
      stop("field '", name, "': Blob column must be a list of raw (or NULL) values", call. = FALSE)
    },
    stop("unknown field type '", type, "' for field '", name, "'", call. = FALSE)
  )
}

# Marshals a `terrio_layer` (or anything `.terrio_parts` accepted) into the
# arguments the Rust binding takes.
.terrio_write_parts <- function(x, layer_name) {
  meta_types <- attr(x, "terrio_field_types")
  if (is.null(meta_types)) {
    stop("the object carries no 'terrio_field_types' attribute; convert it with as_terrio() first",
      call. = FALSE
    )
  }
  fields <- .terrio_fields(x)
  # The geometry column of a read object, or the attribute of a manually
  # built one; only a real column reduces the attribute-column count.
  n_cols <- length(x)
  geometry_col <- x[["geometry"]]
  geometry <- attr(x, "geometry", exact = TRUE)
  if (!is.null(geometry_col)) {
    geometry <- geometry_col
    n_cols <- n_cols - 1L
  }
  if (is.null(geometry)) {
    # No geometry column at all (a write of attributes only).
    geometry <- rep_len(list(NULL), nrow(x))
  }
  attr_names <- setdiff(names(x), "geometry")
  if (anyDuplicated(names(x)) || !setequal(attr_names, fields$name)) {
    stop("attribute names differ from recorded field types; convert the modified data with as_terrio()", call. = FALSE)
  }
  columns <- lapply(fields$name, function(nm) x[[nm]])
  if (length(geometry) != nrow(x)) {
    stop("geometry length must equal the number of rows", call. = FALSE)
  }
  if (n_cols != nrow(fields)) {
    stop("the object has ", n_cols, " attribute columns but ", nrow(fields), " field types",
      call. = FALSE
    )
  }
  for (i in seq_len(n_cols)) {
    .terrio_validate_column(columns[[i]], fields$type[i], fields$name[i], nrow(x))
    if (fields$type[i] == "Float") columns[[i]] <- as.double(columns[[i]])
  }
  names(columns) <- fields$name
  crs_wkt <- attr(x, "crs_wkt")
  crs_epsg <- attr(x, "crs_epsg")
  list(
    name = layer_name %||% attr(x, "layer_name") %||% "layer",
    crs_epsg = if (is.null(crs_epsg)) NULL else as.integer(crs_epsg),
    crs_wkt = crs_wkt,
    field_types = meta_types,
    columns = columns,
    geometry = geometry
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a

#' Write a vector layer with the Terrio engine
#'
#' Writes one layer to GeoPackage, GeoJSON, Shapefile, FlatGeobuf, GeoParquet
#' and GeoJSON text sequences. The input is a `terrio_layer`
#' object ([read_sf()], [as_terrio()]) or an 'sf' object. The format comes
#' from the file extension unless `driver` is given (short names such as
#' `"GPKG"`, `"GeoJSON"`, `"ESRI Shapefile"`, `"FlatGeobuf"`, `"GeoParquet"`).
#'
#' The field types recorded in `terrio_field_types` decide how values are
#' written back (dates and datetimes stay ISO-8601 strings; Integer columns
#' held as R `double` are written as 64-bit integers). Existing files are
#' refused by default. Explicit replacement overwrites the whole dataset,
#' including every layer; append and layer replacement are unsupported. Unsupported or
#' unguessable output formats fail with an explicit error.
#'
#' @param x A `terrio_layer` or 'sf' object.
#' @param dsn Output path.
#' @param layer The layer name; the default is the object's recorded layer
#'   name, or `"layer"`.
#' @param driver The output format's short name, overriding the extension.
#' @param overwrite Replace the entire existing dataset? Default `FALSE`.
#' @return `TRUE`, invisibly.
#'
#' @seealso [read_sf()], [as_terrio()]
#' @export
write_sf <- function(x, dsn, layer = NULL, driver = NULL, overwrite = FALSE) {
  stopifnot(is.character(dsn), length(dsn) == 1L, !is.na(dsn),
    is.logical(overwrite), length(overwrite) == 1L, !is.na(overwrite))
  shp <- if (is.null(driver) || identical(driver, "")) {
    tolower(tools::file_ext(dsn)) == "shp"
  } else tolower(driver) %in% c("shp", "shapefile", "esri_shapefile", "esri shapefile")
  if (shp && tools::file_ext(dsn) != "shp") {
    stop("Shapefile output requires a lowercase .shp extension; driver/path mismatch is unsupported", call. = FALSE)
  }
  existing <- file.exists(dsn)
  if (shp) {
    base <- tools::file_path_sans_ext(dsn)
    actual <- paste0(basename(base), c(".shp", ".dbf", ".shx", ".cpg", ".prj"))
    existing <- existing || any(tolower(list.files(dirname(dsn), all.files = TRUE)) %in% tolower(actual))
  }
  if (existing && !overwrite) {
    stop("output already exists; overwrite=TRUE replaces the entire dataset, including other layers", call. = FALSE)
  }
  parts <- .terrio_write_parts(as_terrio(x, layer = layer), layer)
  if (is.null(parts$name)) {
    parts$name <- "layer"
  }
  invisible(vec_write(
    dsn, driver %||% "", parts$name, parts$crs_epsg, parts$crs_wkt,
    parts$field_types, parts$columns, parts$geometry
  ))
}
