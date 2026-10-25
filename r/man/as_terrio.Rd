\name{as_terrio}
\alias{as_terrio}
\title{Convert to a terrio layer}
\usage{
as_terrio(x, layer = NULL)
}
\arguments{
\item{x}{An \pkg{sf} object, an \code{sfc} geometry column, or a
\code{terrio_layer} (returned as-is).}
\item{layer}{The layer name; the default is \code{"layer"} for \pkg{sf}
input.}
}
\value{
A \code{data.frame} of class \code{terrio_layer}.
}
\description{
Converts \pkg{sf} data or an \pkg{sf} geometry column into the standalone
data representation: a \code{data.frame} of class \code{terrio_layer} with
WKB geometries and CRS metadata. \pkg{sf} is needed for the conversion; the
resulting object is standalone.
}
\details{
R \code{Date} and \code{POSIXct} columns are formatted to ISO-8601
\code{character} (dates keep \code{"\%Y-\%m-\%d"}, datetimes keep their
offset); factors become text; integer columns keep R \code{integer} (64-bit
integers from other sources are R \code{double}); logical columns keep
booleans; lists of raw values become blobs. Unsupported column types fail
with an explicit error. The field types are recorded in
\code{terrio_field_types} so \code{\link[=write_sf]{write_sf()}} writes them back.
}
\seealso{
\code{\link[=as_sf]{as_sf()}}, \code{\link[=write_sf]{write_sf()}}
}
