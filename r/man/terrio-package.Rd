\name{terrio-package}
\alias{terrio}
\alias{terrio-package}
\docType{package}
\title{
Native Rust vector I/O for R without GDAL (prototype)
}
\description{
Native R bindings for the Terrio geospatial library, a pure-Rust engine
without GDAL or other C dependencies. Reads GeoPackage, GeoJSON, Shapefile,
FlatGeobuf and GeoParquet layers into a standalone data representation that
keeps attributes, WKB geometries and CRS metadata; lists layers; converts to
and from \pkg{sf}; and writes vectors. The bindings are thin: format drivers,
CRS handling and algorithms stay in the Terrio Rust library, pinned to its
published crates.io release (see \code{src/rust/Cargo.toml}).
}
\seealso{
Useful links:
\itemize{
  \item \url{https://github.com/e-kotov/terrio}
  \item Report bugs at \url{https://github.com/e-kotov/terrio/issues}
}
}
\keyword{package}
