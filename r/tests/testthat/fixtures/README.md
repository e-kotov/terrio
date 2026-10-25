# Synthetic engine regression fixtures

Generated using published Terrio 0.5.0. Each has one feature, id=1L and CRS EPSG:4326; no external data.

- engine-empty-linestring.fgb: input LINESTRING Z EMPTY. The engine lost its
  declared dimension. The current wrapper must reject its empty geometry.
- engine-null-geometry.parquet: input LINESTRING EMPTY. The engine wrote a
  null geometry. The current wrapper conservatively rejects nulls because
  null and an erased empty geometry are indistinguishable here.

Original generation (using the wrapper before these guards):
sf::st_sf(id=1L, geometry=sf::st_as_sfc(WKT, crs=4326)), followed by
terrio::write_sf(x, path). Files are test evidence of the engine limitation,
not examples of valid lossless output. They are covered by this package's MIT
license.

## Unsigned integer overflow

uint64-max.fgb and uint64-max.parquet contain one Point(1,2), EPSG:4326
and id=18446744073709551615 encoded as an unsigned 64-bit source field.
Published Terrio 0.5.0 returned id=-1 through the old wrapper; the final
wrapper must reject these source schemas before conversion.

generate-overflow-fixtures.py documents generation. It changes the type and
eight-byte value of a one-feature signed-Long FGB written by Terrio; the
Parquet fixture is written independently with PyArrow 26.0.0 and GeoParquet
metadata. PyArrow/Python are fixture-development tools only; package install,
runtime and tests do not require them.
