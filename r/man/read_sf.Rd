\name{read_sf}
\alias{read_sf}
\alias{terrio_read}
\title{Read a vector layer with the Terrio engine}
\usage{
read_sf(dsn, layer = NULL, bbox = NULL, quiet = TRUE)

terrio_read(dsn, layer = NULL, bbox = NULL, quiet = TRUE)
}
\arguments{
\item{dsn}{Dataset path.}
\item{layer}{The layer name; the default reads the first layer.}
\item{bbox}{A rectangle \code{c(min_x, min_y, max_x, max_y)} in the layer's
CRS: only features whose geometry envelopes intersect it are returned (drivers that
index their features use it to skip features early).}
\item{quiet}{Reserved for message control; messages are not emitted yet.}
}
\value{
A \code{data.frame} of class \code{terrio_layer}: attribute columns, a
\code{geometry} list column of raw WKB (\code{NULL} for features without a
geometry), and metadata attributes (\code{crs}, \code{crs_wkt},
\code{crs_epsg}, \code{driver}, \code{layer_name}, \code{geometry_type},
\code{bbox}, \code{terrio_field_types}, \code{n_features}). See
\code{\link[=as_sf]{as_sf()}} to convert to \pkg{sf}.
}
\description{
Reads one layer of a supported vector file (GeoPackage, GeoJSON, Shapefile,
FlatGeobuf, GeoParquet, CSV, KML, GPX and more) into a standalone data
representation, a \code{data.frame} of class \code{terrio_layer}. Attribute
columns keep their values without coercions, the \code{geometry} column holds
raw WKB, and CRS metadata stays on the object; no \pkg{sf} classes and no
GDAL are involved.
}
\details{
Value policy: 64-bit integers become R \code{integer} when they fit a 32-bit
R integer, otherwise R \code{double} (exact up to 2^53; beyond it the read
fails). Dates and datetimes stay ISO-8601 \code{character}; booleans
\code{logical}; blobs \code{raw}. Missing values are \code{NA}. The field
types recorded in \code{terrio_field_types} let \code{\link[=write_sf]{write_sf()}}
write values back unchanged. Null and empty geometries stay distinct in the
representation (\code{NULL} vs the WKB of an empty geometry); Null/empty geometries and empty components are refused for all native I/O because the pinned engine cannot preserve their state or declared dimension consistently. A recognized supported-format extension is required.
}
\seealso{
\code{\link[=terrio_layers]{terrio_layers()}}, \code{\link[=as_sf]{as_sf()}},
\code{\link[=write_sf]{write_sf()}}
}
\examples{
\dontrun{
nc <- read_sf("nc.gpkg")
nc_sf <- as_sf(nc)
}
}
