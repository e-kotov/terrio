# terrio: native R vector I/O prototype

This package wraps Terrio's Rust engine through extendr. It reads and writes
GeoPackage, GeoJSON, Shapefile, FlatGeobuf and GeoParquet, lists layers, and
offers optional conversion to/from sf. It does not expose spatial analysis,
reprojection, raster, point-cloud or remote I/O.

```sh
R CMD INSTALL r/
# Or build and install a self-contained source package:
R CMD build r/
R CMD INSTALL terrio_0.1.0.tar.gz
```

Source builds need R >= 4.2, Rust/Cargo >= 1.90 and a C toolchain for R's
native entry point and compiled dependencies. Cargo downloads the locked Rust
dependency graph. Binary distribution and CRAN submission are future work.

```r
x <- terrio::read_sf("countries.gpkg")  # attributes + raw WKB + CRS
terrio::terrio_layers("countries.gpkg")
sf_x <- terrio::as_sf(x)               # requires sf
back <- terrio::as_terrio(sf_x)
terrio::write_sf(back, "out.fgb")       # refuses existing outputs
```

The standalone package does not require sf, GDAL, PROJ or GEOS at runtime.
The adapter requires sf and therefore its existing dependencies. Converting
to sf does not make an sf installation GDAL-free.

## Data contract

`read_sf()` / `terrio_read()` returns a `terrio_layer` data.frame.
The reserved `geometry` column contains raw ISO WKB. Native I/O is limited
to non-null, nonempty geometries. Zero-feature GPKG/FGB/GeoParquet are
allowed; zero-feature GeoJSON/GeoJSONSeq writes are refused because the
engine cannot retain their attribute schema. Metadata includes CRS WKT/EPSG, field types, layer name, driver
and geometry type. Base row/column subsetting retains CRS/schema while WKB
is present; dropping WKB returns a regular data.frame. Renaming attributes
without rebuilding the recorded schema is rejected on write. Input files
must use a recognized extension for one of the supported formats.

- Integers use R integer where representable, excluding R's NA sentinel
  -2147483648; larger values use exact doubles through +/-2^53. Values beyond
  that interval are rejected. Unsigned 64-bit FGB/Parquet columns are
  refused before engine conversion; DBF Integer source overflow is checked.
  GeoJSON integer lexemes (including unsigned
  overflow and integer coordinates) are checked before engine conversion.
  Decimal/exponent numbers use the usual IEEE double representation. Integer
  fields reject fractions, NaN and Inf.
- Text, dates and datetimes use character columns; logical fields use logical
  and blobs use lists of raw vectors/NULL. Literal "NA" differs from NA.
  Float fields accept finite numeric values and NA. Formats have different
  schema capabilities: e.g. FGB Date becomes DateTime metadata while its ISO
  text values remain unchanged. GeoJSON Blob and all-null non-Text field
  writes are refused because their value/type cannot be recovered. Known
  Text beginning YYYY-MM-DD is also refused in GeoJSON/Seq, whose reader
  otherwise infers a date type.
- sf Date/whole-second POSIXct input becomes ISO text. Fractional POSIXct,
  integer64, unknown numeric classes and unsupported columns are rejected;
  explicit ISO timestamp strings are available for fractional timestamps in
  some formats. GeoParquet currently truncates submillisecond timestamps and
  loses timezone metadata; it is not a lossless workaround there.
- The pinned engine drops M ordinates when serializing WKB, so measured
  geometries are rejected on reads/writes. Nonempty XY/XYZ are supported,
  with XYZ Shapefile writes explicitly refused because the engine adds M=0.
  WKB supplied for writing must be canonical ISO WKB; SRID-bearing EWKB,
  trailing data and unsupported encodings are rejected.
- Null/empty geometries and empty components are rejected on every native
  read/write path. The pinned engine can collapse empty to null (GPKG,
  GeoParquet, GeoJSON) or drop an empty geometry's declared Z dimension.
  This includes canonical POINT EMPTY with NaN coordinates and XYZ empties.
  There is no lossless-empty alternative exposed by this prototype. The
  sf adapter can convert manually constructed NULL geometry to an empty
  collection, explicitly collapsing that distinction; this does not enable
  native I/O for such objects.
- An attribute named `geometry` is rejected; rename it in the source.
  Slash-containing attribute names are supported.
- `bbox=c(xmin,ymin,xmax,ymax)` is a finite ordered envelope-overlap filter
  in the input CRS. It excludes nulls. Envelope overlap can return polygons
  whose holes contain the query rectangle; it is not an exact intersection.
  Spatial indexes may return a different feature order.
- Writes refuse existing datasets, including known Shapefile sidecars.
  `overwrite=TRUE` explicitly replaces the **entire dataset**, including all
  GeoPackage layers. Append and individual-layer replacement are unsupported.
  Shapefile writes require a lowercase .shp extension even with a driver
  override; uppercase/existing sidecars are detected. Shapefile output is
  limited to Integer/Text fields and unique ASCII identifiers <=10 bytes.
  Text must be 1..254 UTF-8 bytes with no trailing spaces, NUL or all-asterisk
  missing-value marker. Unsupported types/names/values are refused.
- GeoJSON/GeoJSONSeq writes require explicit EPSG metadata. Missing and
  custom non-EPSG CRS are rejected because the engine otherwise omits CRS.
  GeoJSONSeq additionally requires EPSG:4326, avoiding its implicit
  reprojection. Accepted writes preserve coordinates; no transformation API
  is exposed.

These checks do not establish full format conformance. In particular, the
pinned engine's DBF encoding heuristic can differ from GDAL on ambiguous text;
text decoding may therefore differ between readers. EWKB inside externally supplied
containers and arbitrary mixed schemas require further engine conformance
work. Do not treat a successful read as validation of arbitrary input.

## Engine dependency

The binding pins published crates.io `terrio` 0.5.0 and includes Cargo.lock.
Source tarballs can be installed outside the repository. The package uses
that published release rather than the Rust core in this checkout.
`engine_version()` reports the engine version.

Features: `default-features=false`, with `sqlite`, `flatgeobuf` and
`parquet`. Algorithms and drivers remain in Terrio; the R crate marshals
values and enforces the R data contract.

## Tests

Run `Rscript -e 'testthat::test_local("r")'` for the regression suite.
Tests use sf's North Carolina SIDS fixture, independent sf/GDAL inputs
and synthetic boundary cases. The R bindings workflow checks source
packages on Linux, macOS and Windows, plus a Linux runtime without GDAL
or sf.
