\name{as_sf}
\alias{as_sf}
\title{Convert to an sf object}
\usage{
as_sf(x, ...)
}
\arguments{
\item{x}{A \code{terrio_layer} object.}
\item{...}{Unused.}
}
\value{
An \pkg{sf} object with the layer's attributes and geometry.
}
\description{
Converts a \code{terrio_layer} to an \pkg{sf} object, through its WKB
geometries. Needs the \pkg{sf} package (Suggests); the core package reads
without it.
}
\details{
The CRS comes from WKT or EPSG metadata. NULL geometry becomes an empty geometry collection, collapsing the null/empty distinction in sf. Typed zero-row attribute columns are retained.
}
\seealso{
\code{\link[=as_terrio]{as_terrio()}}, \code{\link[=read_sf]{read_sf()}}
}
