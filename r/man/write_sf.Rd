\name{write_sf}
\alias{write_sf}
\title{Write a vector layer with the Terrio engine}
\usage{
write_sf(x, dsn, layer = NULL, driver = NULL, overwrite = FALSE)
}
\arguments{
\item{overwrite}{Replace the entire existing dataset, including all layers? Default FALSE.}
\item{x}{A \code{terrio_layer} or \pkg{sf} object.}
\item{dsn}{Output path.}
\item{layer}{The layer name; the default is the object's recorded layer name,
or \code{"layer"}.}
\item{driver}{The output format's short name, overriding the extension (for
example \code{"GPKG"}, \code{"GeoJSON"}, \code{"ESRI Shapefile"},
\code{"FlatGeobuf"}, \code{"GeoParquet"}).}
}
\value{
\code{TRUE}, invisibly.
}
\description{
Writes one layer to GeoPackage, GeoJSON, Shapefile, FlatGeobuf, GeoParquet and GeoJSON text sequences. The format comes from the file
extension unless \code{driver} is given. Unsupported or unguessable output
formats fail with an explicit error.
}
\details{
Native I/O rejects null/empty geometries and empty components. GeoJSON requires explicit EPSG CRS; Shapefile output requires a lowercase .shp extension, nonempty XY geometry, Integer/Text fields, ASCII field identifiers up to 10 bytes and text values up to 254 UTF-8 bytes without trailing spaces, NUL or an all-asterisk missing-value marker. GeoJSONSeq requires EPSG:4326; zero-feature GeoJSON/Seq and known Text beginning YYYY-MM-DD are refused to avoid implicit reprojection or schema loss. Unsupported combinations are rejected before writing.
The field types recorded in \code{terrio_field_types} decide how values are
written back (dates and datetimes stay ISO-8601 strings; Integer columns held
as R \code{double} are written as 64-bit integers). Integer values beyond 2^53
cannot be represented exactly in R and fail. Existing files are refused by default. Explicit overwrite replaces the entire dataset, including all layers. Append and individual-layer replacement are unsupported.
}
\seealso{
\code{\link[=read_sf]{read_sf()}}, \code{\link[=as_terrio]{as_terrio()}}
}
