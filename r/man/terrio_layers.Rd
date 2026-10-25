\name{terrio_layers}
\alias{terrio_layers}
\title{The layers of a vector dataset}
\usage{
terrio_layers(dsn, detailed = FALSE, layer = NULL)
}
\arguments{
\item{dsn}{Dataset path.}
\item{detailed}{Report counts, types, CRS and fields (a full read of the
requested layers) rather than only the names? Default \code{FALSE}.}
\item{layer}{With \code{detailed = TRUE}, only these layer names; the default
reads all.}
}
\value{
A \code{data.frame}: \code{layer} (and with \code{detailed = TRUE}:
\code{n_features}, \code{geometry_type}, \code{crs}, \code{fields} as
\code{name/type} entries).
}
\description{
Lists the layers of a GeoPackage, GeoJSON, Shapefile, FlatGeobuf, GeoParquet
or other vector file that the Terrio engine reads. For GeoPackage the names
are listed without reading the features; with \code{detailed = TRUE} the
requested layers are read fully and reported with feature counts, geometry
types, CRS and fields.
}
\examples{
\dontrun{
terrio_layers("countries.gpkg")
terrio_layers("countries.gpkg", detailed = TRUE)
}
}
