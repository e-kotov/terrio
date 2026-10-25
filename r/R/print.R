# Printing a `terrio_layer`.

#' Print a `terrio_layer`
#'
#' Shows the layer metadata and the first rows of the attribute columns. The
#' `geometry` column (a list of raw WKB) is summarized, not printed.
#'
#' @param x A `terrio_layer` object.
#' @param ... Passed to the data.frame print of the attribute columns.
#' @export
print.terrio_layer <- function(x, ...) {
  n <- attr(x, "n_features", exact = TRUE) %||% nrow(x)
  cat(
    sprintf(
      "<terrio layer '%s' %d features, %s crs=%s>\n",
      attr(x, "layer_name", exact = TRUE) %||% "layer",
      n,
      attr(x, "geometry_type", exact = TRUE) %||% "Unknown",
      attr(x, "crs", exact = TRUE) %||% "unknown"
    )
  )
  attrs <- x[, setdiff(names(x), "geometry"), drop = FALSE]
  class(attrs) <- "data.frame"
  print(head(attrs), ...)
  if (n > nrow(attrs)) {
    cat(sprintf("[%d more features]\n", n - nrow(head(attrs))))
  }
  geom <- x[["geometry"]]
  if (!is.null(geom)) {
    nulls <- sum(vapply(geom, is.null, logical(1)))
    cat(sprintf("geometry: list of %d raw WKB (%d null)\n", length(geom), nulls))
  }
  invisible(x)
}
