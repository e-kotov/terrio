//! Inspect source integer representations before the engine can wrap an
//! unsigned integer or turn a DBF parse overflow into a missing value.
use parquet::basic::{ConvertedType, LogicalType};
use parquet::file::reader::{FileReader, SerializedFileReader};
use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use terrio::Error;

fn bad(msg: impl std::fmt::Display) -> Error {
    Error::InvalidArgument(msg.to_string())
}

pub fn flatgeobuf(path: &str) -> Result<(), Error> {
    let reader = ::flatgeobuf::FgbReader::open(BufReader::new(File::open(path)?)).map_err(bad)?;
    if reader.header().columns().is_some_and(|cs| cs.iter().any(|c| c.type_() == ::flatgeobuf::ColumnType::ULong)) {
        return Err(bad("unsigned 64-bit FlatGeobuf columns are unsupported; the pinned engine may wrap them"));
    }
    Ok(())
}

pub fn parquet(path: &str) -> Result<(), Error> {
    let reader = SerializedFileReader::new(File::open(path)?).map_err(bad)?;
    for c in reader.metadata().file_metadata().schema_descr().columns() {
        if c.converted_type() == ConvertedType::UINT_64
            || matches!(c.logical_type_ref(), Some(LogicalType::Integer { bit_width: 64, is_signed: false }))
        {
            return Err(bad("unsigned 64-bit Parquet columns are unsupported; the pinned engine may wrap them"));
        }
    }
    Ok(())
}

pub fn shapefile(path: &str) -> Result<(), Error> {
    let path = Path::new(path);
    let stem = path.file_stem().unwrap_or_default().to_string_lossy();
    let dir = path.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or_else(|| Path::new("."));
    let dbf = std::fs::read_dir(dir)?.filter_map(Result::ok).map(|e| e.path()).find(|p| {
        p.file_stem().is_some_and(|s| s.to_string_lossy().eq_ignore_ascii_case(&stem))
            && p.extension().is_some_and(|e| e.to_string_lossy().eq_ignore_ascii_case("dbf"))
    });
    let Some(dbf) = dbf else {
        return Ok(());
    };
    let data = std::fs::read(dbf)?;
    if data.len() < 32 {
        return Err(bad("truncated DBF header"));
    }
    let n = u32::from_le_bytes(data[4..8].try_into().unwrap()) as usize;
    let header = u16::from_le_bytes(data[8..10].try_into().unwrap()) as usize;
    let record = u16::from_le_bytes(data[10..12].try_into().unwrap()) as usize;
    if header < 33 || header > data.len() || record == 0 {
        return Err(bad("invalid DBF layout"));
    }
    let mut offset = 1usize;
    let mut fields = Vec::new();
    let mut at = 32;
    while at + 32 <= header && data[at] != 0x0d {
        let width = data[at + 16] as usize;
        if data[at + 11] == b'N' && data[at + 17] == 0 {
            fields.push((offset, width));
        }
        offset += width;
        at += 32;
    }
    if offset > record {
        return Err(bad("invalid DBF record width"));
    }
    for i in 0..n {
        let start =
            header.checked_add(i.checked_mul(record).ok_or_else(|| bad("DBF size overflow"))?).ok_or_else(|| bad("DBF size overflow"))?;
        let row = data.get(start..start + record).ok_or_else(|| bad("truncated DBF record"))?;
        if row[0] == b'*' {
            continue;
        }
        for &(off, width) in &fields {
            let raw = &row[off..off + width];
            let text = std::str::from_utf8(raw).map_err(bad)?.trim_matches([' ', '\0']);
            if text.is_empty() || text.bytes().all(|b| b == b'*') {
                continue;
            }
            let value = text.parse::<i64>().map_err(|_| bad("DBF integer is unsupported or beyond 2^53"))?;
            if !(-crate::MAX_EXACT..=crate::MAX_EXACT).contains(&value) {
                return Err(bad("DBF integer beyond 2^53 cannot be represented exactly in R"));
            }
        }
    }
    Ok(())
}
