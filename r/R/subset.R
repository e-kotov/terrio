# Retain CRS and schema for ordinary two-dimensional data.frame subsetting.
# Removing WKB returns an ordinary data.frame; stale geometry metadata must
# never follow a table which no longer has its geometry column.
`[.terrio_layer` <- function(x, i, j, drop = FALSE) {
  y <- NextMethod("[")
  if (!is.data.frame(y)) return(y)
  if (!"geometry" %in% names(y)) {
    class(y) <- "data.frame"
    return(y)
  }
  meta <- attributes(x)
  for (nm in setdiff(names(meta), c("names", "row.names", "class", "geometry", "bbox", "n_features", "terrio_field_types"))) {
    attr(y, nm) <- meta[[nm]]
  }
  fields <- .terrio_fields(x)
  wanted <- setdiff(names(y), "geometry")
  attr(y, "terrio_field_types") <- paste0(fields$name[match(wanted, fields$name)], "/", fields$type[match(wanted, fields$name)])
  attr(y, "bbox") <- NULL
  attr(y, "n_features") <- nrow(y)
  class(y) <- c("terrio_layer", "data.frame")
  y
}
