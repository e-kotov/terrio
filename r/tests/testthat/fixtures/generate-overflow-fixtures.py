"""Generate tiny unsigned-overflow fixtures; requires pyarrow for Parquet.
Create BASE using the R package (signed Long metadata, id held as a double):
x <- terrio::as_terrio(sf::st_sf(id=1L, geometry=sf::st_sfc(sf::st_point(c(1,2)), crs=4326)))
x$id <- 2^40
terrio::write_sf(x, BASE)
Usage: python generate-overflow-fixtures.py BASE OUTPUT_DIRECTORY
"""
import json
from pathlib import Path
import struct
import sys
import pyarrow as pa
import pyarrow.parquet as pq

base, output = Path(sys.argv[1]), Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
data = bytearray(base.read_bytes())
u32 = lambda at: struct.unpack_from("<I", data, at)[0]

def field(table, slot):
    vtable = table - struct.unpack_from("<i", data, table)[0]
    size = struct.unpack_from("<H", data, vtable)[0]
    offset = struct.unpack_from("<H", data, vtable + slot)[0] if slot < size else 0
    return table + offset if offset else None

header_size = u32(8)
header = 12 + u32(12)
columns_ptr = field(header, 18)
vector = columns_ptr + u32(columns_ptr)
assert u32(vector) == 1
column_ptr = vector + 4
column = column_ptr + u32(column_ptr)
kind = field(column, 6)
assert data[kind] == 7  # ColumnType.Long
data[kind] = 8         # ColumnType.ULong, same eight-byte representation
count_ptr = field(header, 20)
assert struct.unpack_from("<Q", data, count_ptr)[0] == 1
# The library always includes a root level: one feature has two 40-byte nodes.
index_ptr = field(header, 22)
node_size = struct.unpack_from("<H", data, index_ptr)[0] if index_ptr else 16
feature_start = 12 + header_size + (80 if node_size else 0)
feature = feature_start + 4 + u32(feature_start + 4)
props_ptr = field(feature, 6)
props = props_ptr + u32(props_ptr)
assert u32(props) == 10  # u16 field id + u64 payload
assert struct.unpack_from("<H", data, props + 4)[0] == 0
struct.pack_into("<Q", data, props + 6, 2**64 - 1)
(output / "uint64-max.fgb").write_bytes(data)

wkb = struct.pack("<BI2d", 1, 1, 1.0, 2.0)
table = pa.table({"id": pa.array([2**64 - 1], type=pa.uint64()),
                  "geometry": pa.array([wkb], type=pa.binary())})
geo = {"version": "1.1.0", "primary_column": "geometry",
       "columns": {"geometry": {"encoding": "WKB", "geometry_types": ["Point"]}}}
table = table.replace_schema_metadata({b"geo": json.dumps(geo).encode()})
pq.write_table(table, output / "uint64-max.parquet", compression="NONE")
