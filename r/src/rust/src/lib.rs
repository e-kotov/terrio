//! Native R bindings for Terrio vector I/O.
//!
//! Thin bindings: format drivers, CRS handling and algorithms live in the
//! Terrio Rust library (`terrio` crate); this crate only marshals R data into
//! Terrio's data model and back.
#![allow(non_snake_case)]
mod geojson;
mod source;
mod wkb;

use extendr_api::prelude::*;
use extendr_api::Result;
use terrio::crs::SpatialRef;
use terrio::formats::VectorDriver;
use terrio::vector::{geometry_has_z, geometry_type_name, layer_extent};
use terrio::{
    list_layers as terrio_list_layers, open_vector, write_vector, Error, Feature, FieldDef, FieldType, FieldValue, Geometry, Layer,
    VectorOpenOptions, VectorWriteOptions,
};

/// Integers beyond 2^53 are not exactly representable as R doubles: fail
/// explicitly instead of losing them silently. See `r/README.md` for the
/// documented value policy.
const MAX_EXACT: i64 = 1 << 53;

fn to_binding_error(e: impl std::fmt::Display) -> extendr_api::Error {
    extendr_api::Error::Other(format!("{e}"))
}

/// Runs a Terrio fallible operation, mapping its error to an R error.
fn terrio_call<T>(r: std::result::Result<T, Error>) -> Result<T> {
    r.map_err(to_binding_error)
}

/// The CRS string of a layer: `"EPSG:xxxx"` (or `"ESRI:xxxx"`) when its code is
/// known, otherwise its WKT, otherwise `None`.
fn crs_string(layer: &Layer) -> Option<String> {
    let srs = SpatialRef::from_layer(layer);
    match srs.authority_code() {
        Some(code) if !code.is_empty() => Some(code),
        _ => layer.crs_wkt().map(|w| w.to_string()),
    }
}

/// Whether a geometry's bounding box intersects the rectangle
/// `(min_x, min_y, max_x, max_y)`.
fn bbox_intersects(g: &Geometry, bbox: &[f64]) -> bool {
    match g.bbox() {
        Some(b) => !(b.max_x < bbox[0] || b.min_x > bbox[2] || b.max_y < bbox[1] || b.min_y > bbox[3]),
        None => false,
    }
}

/// Builds one attribute column from a field's values, without silent
/// coercions:
///
/// - `Integer`: R `integer` when every non-null value fits a 32-bit R integer,
///   otherwise R `double` (exact up to 2^53; beyond it the call fails).
/// - `Float`: R `double`.
/// - `Text`, `Date`, `DateTime`, `Json`: R `character` (dates and datetimes
///   stay ISO-8601 strings; no coercion to R Date classes).
/// - `Boolean`: R `logical`.
/// - `Blob`: R `raw` values in a list.
/// - Missing values are `NA` (`NULL` for `Blob`).
fn attribute_column(field_type: FieldType, values: &[&FieldValue]) -> Result<Robj> {
    match field_type {
        FieldType::Integer => {
            if values.iter().any(|v| v.as_i64().is_some_and(|i| !(-MAX_EXACT..=MAX_EXACT).contains(&i))) {
                return Err(to_binding_error(Error::InvalidArgument(
                    "integer values beyond 2^53 cannot be represented exactly in R: values would be lost".to_string(),
                )));
            }
            // INT_MIN is R's NA_INTEGER sentinel, not a usable R integer.
            let fits_int32 = values.iter().all(|v| v.is_null() || v.as_i64().is_some_and(|i| i > i32::MIN as i64 && i <= i32::MAX as i64));
            if fits_int32 {
                let column: Vec<Option<i32>> = values.iter().map(|v| v.as_i64().map(|i| i as i32)).collect();
                Ok(column.into())
            } else {
                let column: Vec<Option<f64>> = values.iter().map(|v| v.as_i64().map(|i| i as f64)).collect();
                Ok(column.into())
            }
        }
        FieldType::Float => {
            let column: Vec<Option<f64>> = values.iter().map(|v| v.as_f64()).collect();
            Ok(column.into())
        }
        FieldType::Text | FieldType::Date | FieldType::DateTime | FieldType::Json => {
            let column: Vec<Option<&str>> = values.iter().map(|v| v.as_str()).collect();
            Ok(column.into())
        }
        FieldType::Boolean => {
            let column: Vec<Option<bool>> = values.iter().map(|v| v.as_bool()).collect();
            Ok(column.into())
        }
        FieldType::Blob => {
            let items: Vec<Robj> = values
                .iter()
                .map(|v| match v.as_blob() {
                    Some(bytes) => Raw::from_bytes(bytes).into(),
                    None => Robj::from(()),
                })
                .collect();
            Ok(items.into())
        }
    }
}

/// The WKB of a feature's geometry as a raw vector, or `NULL` when the feature
/// has no geometry (null and empty geometries stay distinct: an empty
/// geometry keeps its WKB).
fn geometry_wkb(f: &Feature) -> Robj {
    match &f.geometry {
        Some(g) => Raw::from_bytes(&g.to_wkb()).into(),
        None => Robj::from(()),
    }
}

// wbvector 0.1.6 parses M coordinates but its WKB serializer drops them.
// Reject measured geometries rather than silently reducing dimensionality.
fn has_m(g: &Geometry) -> bool {
    match g {
        Geometry::Point(c) => c.m.is_some(),
        Geometry::LineString(cs) | Geometry::MultiPoint(cs) => cs.iter().any(|c| c.m.is_some()),
        Geometry::Polygon { exterior, interiors } => {
            exterior.0.iter().chain(interiors.iter().flat_map(|r| r.0.iter())).any(|c| c.m.is_some())
        }
        Geometry::MultiLineString(ls) => ls.iter().flatten().any(|c| c.m.is_some()),
        Geometry::MultiPolygon(ps) => {
            ps.iter().flat_map(|(e, h)| e.0.iter().chain(h.iter().flat_map(|r| r.0.iter()))).any(|c| c.m.is_some())
        }
        Geometry::GeometryCollection(gs) => gs.iter().any(has_m),
    }
}

// Empty components and NaN Point EMPTY cannot be preserved consistently by
// this engine. Reject on both boundaries, including empty XYZ containers.
fn has_empty(g: &Geometry) -> bool {
    match g {
        Geometry::Point(c) => c.x.is_nan() && c.y.is_nan(),
        Geometry::LineString(cs) | Geometry::MultiPoint(cs) => cs.is_empty() || cs.iter().any(|c| c.x.is_nan() && c.y.is_nan()),
        Geometry::Polygon { exterior, interiors } => {
            exterior.0.is_empty()
                || interiors.iter().any(|r| r.0.is_empty())
                || exterior.0.iter().chain(interiors.iter().flat_map(|r| r.0.iter())).any(|c| c.x.is_nan() && c.y.is_nan())
        }
        Geometry::MultiLineString(ls) => {
            ls.is_empty() || ls.iter().any(|cs| cs.is_empty()) || ls.iter().flatten().any(|c| c.x.is_nan() && c.y.is_nan())
        }
        Geometry::MultiPolygon(ps) => {
            ps.is_empty()
                || ps.iter().any(|(e, h)| e.0.is_empty() || h.iter().any(|r| r.0.is_empty()))
                || ps.iter().flat_map(|(e, h)| e.0.iter().chain(h.iter().flat_map(|r| r.0.iter()))).any(|c| c.x.is_nan() && c.y.is_nan())
        }
        Geometry::GeometryCollection(gs) => gs.is_empty() || gs.iter().any(has_empty),
    }
}

/// Wraps a layer as the named list the R side assembles into a
/// `terrio_layer` object: metadata, typed attribute columns and a `geometry`
/// list of raw WKB.
fn layer_to_list(layer: Layer, driver: &str) -> Result<Robj> {
    if layer.features.iter().any(|f| f.geometry.as_ref().is_none_or(has_empty)) {
        return Err(to_binding_error(
            "null/empty geometries are unsupported: the pinned engine cannot preserve their state/dimension across formats",
        ));
    }
    if layer.features.iter().filter_map(|f| f.geometry.as_ref()).any(has_m) {
        return Err(to_binding_error("M/XYZM geometries are unsupported by the pinned engine's WKB serializer"));
    }
    let n_fields = layer.schema.fields().len();
    let mut names: Vec<String> = Vec::with_capacity(n_fields + 1);
    let mut columns: Vec<Robj> = Vec::with_capacity(n_fields + 1);
    for (i, field) in layer.schema.fields().iter().enumerate() {
        if field.name == "geometry" || names.contains(&field.name) {
            return Err(to_binding_error("attribute names must be unique; 'geometry' is reserved for WKB"));
        }
        let values: Vec<&FieldValue> = layer.features.iter().map(|f| f.attributes.get(i).unwrap_or(&FieldValue::Null)).collect();
        names.push(field.name.clone());
        columns.push(attribute_column(field.field_type, &values)?);
    }
    names.push("geometry".to_string());
    columns.push(Robj::from(layer.features.iter().map(geometry_wkb).collect::<Vec<Robj>>()));

    let column_names = Strings::from_values(&names);
    let mut columns = List::from_values(columns);
    columns.set_attrib("names", column_names)?;

    let fields: Vec<String> = layer.schema.fields().iter().map(|f| format!("{}/{}", f.name, f.field_type.as_str())).collect();
    let bbox = layer_extent(&layer);
    let bbox_robj = match bbox {
        Some(b) => Robj::from([b.0, b.1, b.2, b.3]),
        None => Robj::from(()),
    };
    let crs_robj = match crs_string(&layer) {
        Some(s) => Robj::from(s),
        None => Robj::from(()),
    };
    let epsg_robj = match layer.crs_epsg() {
        Some(e) => Robj::from(e as i32),
        None => Robj::from(()),
    };
    let wkt_robj = match layer.crs_wkt() {
        Some(w) => Robj::from(w),
        None => Robj::from(()),
    };
    let mut out = List::from_values(vec![
        Robj::from(layer.name.clone()),
        Robj::from(driver),
        Robj::from(geometry_type_name(&layer)),
        crs_robj,
        epsg_robj,
        wkt_robj,
        Robj::from(fields),
        columns.into(),
        bbox_robj,
        Robj::from(layer.features.len() as i32),
    ]);
    out.set_attrib(
        "names",
        Strings::from_values(&[
            "layer_name",
            "driver",
            "geometry_type",
            "crs",
            "crs_epsg",
            "crs_wkt",
            "fields",
            "columns",
            "bbox",
            "n_features",
        ]),
    )?;
    Ok(out.into())
}

/// The field type of a `name/type` spec: the same stable names
/// `attribute_column` writes.
fn parse_field_type(type_name: &str) -> std::result::Result<FieldType, Error> {
    Ok(match type_name {
        "Integer" => FieldType::Integer,
        "Float" => FieldType::Float,
        "Text" => FieldType::Text,
        "Date" => FieldType::Date,
        "DateTime" => FieldType::DateTime,
        "Boolean" => FieldType::Boolean,
        "Blob" => FieldType::Blob,
        "Json" => FieldType::Json,
        other => return Err(Error::InvalidArgument(format!("unknown field type '{other}'"))),
    })
}

/// One attribute value at row `i`, read back without coercions: an R `double`
/// in an `Integer` column is an int64 value above 2^31 (the documented
/// representation policy), and a `character` column's type comes from the
/// field spec (`Text`, `Date`, `DateTime` or `Json`). A missing value is `NA`
/// (`NULL` for `Blob`).
fn column_value(col: &Robj, i: usize, field_type: FieldType) -> std::result::Result<FieldValue, Error> {
    let missing = || Error::InvalidArgument(format!("row {i}: attribute value missing"));
    match field_type {
        FieldType::Integer => {
            if col.is_real() {
                let v = col.as_real_slice().ok_or_else(missing)?;
                match v.get(i).copied() {
                    Some(x) if x.is_na() => Ok(FieldValue::Null),
                    Some(x) if x.is_finite() && x.fract() == 0.0 && x.abs() <= MAX_EXACT as f64 => Ok(FieldValue::Integer(x as i64)),
                    Some(_) => Err(Error::InvalidArgument("Integer values must be whole finite numbers within 2^53 (or NA)".to_string())),
                    None => Err(missing()),
                }
            } else {
                let v = col.as_integers().ok_or_else(missing)?;
                let x = v.elt(i);
                if x.is_na() {
                    Ok(FieldValue::Null)
                } else {
                    Ok(FieldValue::Integer(i64::from(x.0)))
                }
            }
        }
        FieldType::Float => {
            let v = col.as_real_slice().ok_or_else(missing)?;
            match v.get(i).copied() {
                Some(x) if x.is_na() => Ok(FieldValue::Null),
                Some(x) => Ok(FieldValue::Float(x)),
                None => Err(missing()),
            }
        }
        FieldType::Text | FieldType::Date | FieldType::DateTime | FieldType::Json => {
            let v = Strings::try_from(col.clone()).map_err(|_| missing())?;
            if i >= v.len() {
                return Err(missing());
            }
            let s = v.elt(i);
            if s.is_na() {
                Ok(FieldValue::Null)
            } else {
                let s = s.to_string();
                Ok(match field_type {
                    FieldType::Date => FieldValue::Date(s),
                    FieldType::DateTime => FieldValue::DateTime(s),
                    _ => FieldValue::Text(s),
                })
            }
        }
        FieldType::Boolean => {
            let v = col.as_logical_slice().ok_or_else(missing)?;
            match v.get(i) {
                Some(b) if b.is_na() => Ok(FieldValue::Null),
                Some(b) => Ok(FieldValue::Boolean(b.0 != 0)),
                None => Err(missing()),
            }
        }
        FieldType::Blob => {
            let list = col.as_list().ok_or_else(missing)?;
            match list.elt(i) {
                Ok(raw) if raw.is_null() => Ok(FieldValue::Null),
                Ok(raw) => Ok(FieldValue::Blob(raw.as_raw().ok_or_else(missing)?.as_slice().to_vec())),
                Err(_) => Ok(FieldValue::Null),
            }
        }
    }
}

/// Builds a Terrio layer from the marshalled R representation: a named
/// `columns` list of attribute vectors, the field types (`name/type` strings,
/// in column order) and a `geometry` list of raw WKB (or `NULL` for features
/// without a geometry).
fn layer_from_parts(
    name: &str,
    crs_epsg: Option<i32>,
    crs_wkt: Option<&str>,
    field_types: &[String],
    columns: &List,
    geometry: &List,
) -> std::result::Result<Layer, Error> {
    let n = geometry.len();
    if columns.len() != field_types.len() {
        return Err(Error::InvalidArgument(format!("{} attribute columns but {} field types", columns.len(), field_types.len())));
    }
    let mut layer = Layer::new(name);
    if let Some(epsg) = crs_epsg {
        layer = layer.with_crs_epsg(epsg as u32);
    }
    if let Some(wkt) = crs_wkt {
        if !wkt.is_empty() {
            layer = layer.with_crs_wkt(wkt);
        }
    }
    for (_col, spec) in columns.iter().zip(field_types.iter()) {
        let (field_name, type_name) = spec
            .rsplit_once('/')
            .ok_or_else(|| Error::InvalidArgument(format!("field type '{spec}' is not 'name/type': a terrio_layer object is expected")))?;
        layer.schema.add_field(FieldDef::new(field_name, parse_field_type(type_name)?));
    }
    let fields = layer.schema.fields().to_vec();
    for i in 0..n {
        let geom = match geometry.elt(i) {
            Ok(wkb) if !wkb.is_null() => {
                let raw =
                    wkb.as_raw().ok_or_else(|| Error::InvalidArgument("geometry elements must be raw WKB vectors or NULL".to_string()))?;
                let bytes = raw.as_slice();
                wkb::validate(bytes)?;
                let g = Geometry::from_wkb(bytes)?;
                if has_m(&g) {
                    return Err(Error::InvalidArgument(
                        "M/XYZM geometries are unsupported by the pinned engine's WKB serializer".to_string(),
                    ));
                }
                Some(g)
            }
            _ => None,
        };
        if geom.as_ref().is_some_and(has_m) {
            return Err(Error::InvalidArgument("M/XYZM geometries are unsupported by the pinned engine's WKB serializer".to_string()));
        }
        if geom.as_ref().is_none_or(has_empty) {
            return Err(Error::InvalidArgument("null/empty geometries are unsupported by this prototype".to_string()));
        }
        let mut attrs: Vec<(&str, FieldValue)> = Vec::with_capacity(fields.len());
        for (j, field) in fields.iter().enumerate() {
            let col = columns.elt(j).map_err(|_| Error::InvalidArgument(format!("missing column for field '{}'", field.name)))?;
            attrs.push((field.name.as_str(), column_value(&col, i, field.field_type)?));
        }
        layer.add_feature(geom, &attrs)?;
    }
    Ok(layer)
}

/// The layers of a vector dataset as a one-column `data.frame` (`layer`),
/// without reading the features when the format allows it (GeoPackage).
///
/// @noRd
#[extendr]
fn vec_list_layers(path: &str) -> Result<Robj> {
    terrio_call(terrio_list_layers(path)).map(|names| data_frame!(layer = names))
}

/// Reads one layer of a vector dataset into the standalone R representation.
///
/// @noRd
#[extendr]
fn vec_read(path: &str, layer: &str, bbox: Robj) -> Result<Robj> {
    if !matches!(
        VectorDriver::for_extension(path),
        Some(
            VectorDriver::GPKG
                | VectorDriver::FlatGeobuf
                | VectorDriver::Shapefile
                | VectorDriver::Parquet
                | VectorDriver::GeoJSON
                | VectorDriver::GeoJSONSeq
        )
    ) {
        return Err(to_binding_error(
            "this prototype requires a recognized GeoPackage/GeoJSON/Shapefile/FlatGeobuf/GeoParquet filename extension",
        ));
    }

    match VectorDriver::for_extension(path) {
        Some(VectorDriver::GeoJSON | VectorDriver::GeoJSONSeq) => terrio_call(geojson::check_integers(path))?,
        Some(VectorDriver::FlatGeobuf) => terrio_call(source::flatgeobuf(path))?,
        Some(VectorDriver::Parquet) => terrio_call(source::parquet(path))?,
        Some(VectorDriver::Shapefile) => terrio_call(source::shapefile(path))?,
        _ => (),
    }
    let mut options = VectorOpenOptions::default();
    if layer.is_empty() && path.to_ascii_lowercase().ends_with(".gpkg") {
        if let Some(first) = terrio_call(terrio_list_layers(path))?.first() {
            options.layers.push(first.clone());
        }
    } else if !layer.is_empty() {
        options.layers.push(layer.to_string());
    }
    let filter: Option<Vec<f64>> = if bbox.is_null() || bbox.is_na() {
        None
    } else {
        let v = bbox
            .as_real_vector()
            .ok_or_else(|| to_binding_error("bbox must be a numeric vector of length 4: c(min_x, min_y, max_x, max_y)"))?;
        if v.len() != 4 {
            return Err(to_binding_error("bbox must be a numeric vector of length 4: c(min_x, min_y, max_x, max_y)"));
        }
        options.spatial_filter = Some((v[0], v[1], v[2], v[3]));
        Some(v)
    };
    terrio_call(open_vector(path, &options)).and_then(|mut ds| {
        if ds.layers.is_empty() {
            return Err(to_binding_error(Error::InvalidArgument(format!("layer '{layer}' not found in '{path}'"))));
        }
        let driver = ds.driver.name().to_string();
        let mut layer = ds.layers.remove(0);
        // Drivers that index their features may skip features outside the
        // spatial filter without testing their geometries; apply the
        // rectangle test here so the result matches the requested bbox.
        if let Some(f) = &filter {
            layer.features.retain(|feat| feat.geometry.as_ref().is_some_and(|g| bbox_intersects(g, f)));
        }
        layer_to_list(layer, &driver)
    })
}

/// Per-layer summaries of a vector dataset (a full read of the requested
/// layers). `fields` entries are `name/type`.
///
/// @noRd
#[extendr]
fn vec_layer_summaries(path: &str, names: Robj) -> Result<Robj> {
    let mut options = VectorOpenOptions::default();
    if !names.is_null() && !names.is_na() {
        let requested = names.as_str_vector().ok_or_else(|| to_binding_error("names must be a character vector or NULL"))?;
        options.layers = requested.iter().map(|s| s.to_string()).collect();
    }
    terrio_call(open_vector(path, &options)).map(|ds| {
        let mut layers: Vec<String> = Vec::new();
        let mut n_features: Vec<i32> = Vec::new();
        let mut geom_types: Vec<String> = Vec::new();
        let mut crs_labels: Vec<String> = Vec::new();
        let mut field_lists: Vec<String> = Vec::new();
        for layer in &ds.layers {
            layers.push(layer.name.clone());
            n_features.push(layer.features.len() as i32);
            geom_types.push(geometry_type_name(layer));
            crs_labels.push(crs_string(layer).unwrap_or_else(|| "unknown".to_string()));
            let fields: Vec<String> = layer.schema.fields().iter().map(|f| format!("{}/{}", f.name, f.field_type.as_str())).collect();
            field_lists.push(fields.join(", "));
        }
        data_frame!(layer = layers, n_features = n_features, geometry_type = geom_types, crs = crs_labels, fields = field_lists)
    })
}

/// Writes one layer, given the marshalled R representation. Unsupported
/// formats and writes fail with Terrio's own errors.
///
/// @noRd
#[extendr]
#[allow(clippy::too_many_arguments)]
fn vec_write(
    path: &str,
    driver: &str,
    name: &str,
    crs_epsg: Robj,
    crs_wkt: Robj,
    field_types: Robj,
    columns: Robj,
    geometry: Robj,
) -> Result<Robj> {
    let crs_epsg: Option<i32> = if crs_epsg.is_null() || crs_epsg.is_na() { None } else { crs_epsg.as_integer() };
    let crs_wkt: Option<String> = if crs_wkt.is_null() || crs_wkt.is_na() { None } else { crs_wkt.as_str().map(|s| s.to_string()) };
    let field_types: Vec<String> = field_types
        .as_str_vector()
        .ok_or_else(|| to_binding_error("field_types must be a character vector of 'name/type' entries"))?
        .iter()
        .map(|s| s.to_string())
        .collect();
    let columns = columns.as_list().ok_or_else(|| to_binding_error("columns must be a named list of attribute vectors"))?.clone();
    let geometry = geometry.as_list().ok_or_else(|| to_binding_error("geometry must be a list of raw WKB vectors"))?.clone();
    // Column names must match the field names of the specs, in order.
    for (i, spec) in field_types.iter().enumerate() {
        let (field_name, _) = spec
            .rsplit_once('/')
            .ok_or_else(|| to_binding_error(format!("field type '{spec}' is not 'name/type': a terrio_layer object is expected")))?;
        let col_name =
            columns.names().ok_or_else(|| to_binding_error("columns must have names"))?.nth(i).map(|s| s.to_string()).unwrap_or_default();
        if col_name != field_name {
            return Err(to_binding_error(Error::InvalidArgument(format!(
                "column {i} is '{col_name}' but the field spec says '{field_name}'"
            ))));
        }
    }
    let layer = terrio_call(layer_from_parts(name, crs_epsg, crs_wkt.as_deref(), &field_types, &columns, &geometry))?;
    let mut options = VectorWriteOptions::default();
    if !driver.is_empty() {
        let d = terrio_call(match VectorDriver::from_name(driver) {
            Some(d) => Ok(d),
            None => Err(Error::InvalidArgument(format!("unknown vector format '{driver}'"))),
        })?;
        options.driver = Some(d);
    }
    let target_driver = options.driver.or_else(|| VectorDriver::for_extension(path));
    if !matches!(
        target_driver,
        Some(
            VectorDriver::GPKG
                | VectorDriver::FlatGeobuf
                | VectorDriver::Shapefile
                | VectorDriver::Parquet
                | VectorDriver::GeoJSON
                | VectorDriver::GeoJSONSeq
        )
    ) {
        return Err(to_binding_error("output format is outside this vector prototype's supported scope"));
    }
    if target_driver == Some(VectorDriver::Shapefile) {
        if layer.features.iter().filter_map(|f| f.geometry.as_ref()).any(geometry_has_z) {
            return Err(to_binding_error("XYZ Shapefile writes are unsupported: the pinned engine manufactures an M ordinate"));
        }
        let mut seen = Vec::new();
        for (i, field) in layer.schema.fields().iter().enumerate() {
            let name = &field.name;
            if name.is_empty()
                || name.len() > 10
                || !name.bytes().enumerate().all(|(i, b)| b == b'_' || b.is_ascii_alphabetic() || (i > 0 && b.is_ascii_digit()))
                || seen.contains(&name.to_ascii_lowercase())
            {
                return Err(to_binding_error("Shapefile field names must be unique ASCII identifiers of at most 10 bytes"));
            }
            seen.push(name.to_ascii_lowercase());
            if !matches!(field.field_type, FieldType::Integer | FieldType::Text) {
                return Err(to_binding_error(
                    "Shapefile writes support Integer and Text fields only; other types cannot be guaranteed lossless",
                ));
            }
            for f in &layer.features {
                if let Some(FieldValue::Text(s)) = f.attributes.get(i) {
                    if s.len() > 254
                        || s.is_empty()
                        || s.ends_with(' ')
                        || s.contains('\0')
                        || s.trim_matches(' ').bytes().all(|b| b == b'*')
                    {
                        return Err(to_binding_error("Shapefile text must be 1..254 UTF-8 bytes, without trailing spaces, NUL or an all-asterisk missing-value marker"));
                    }
                }
            }
        }
    }
    if matches!(target_driver, Some(VectorDriver::GeoJSON | VectorDriver::GeoJSONSeq)) && layer.crs_epsg().is_none() {
        return Err(to_binding_error(
            "GeoJSON output requires an explicit EPSG CRS; custom/missing CRS cannot be preserved by the pinned engine",
        ));
    }
    if matches!(target_driver, Some(VectorDriver::GeoJSON | VectorDriver::GeoJSONSeq)) {
        if target_driver == Some(VectorDriver::GeoJSONSeq) && layer.crs_epsg() != Some(4326) {
            return Err(to_binding_error("GeoJSONSeq output requires EPSG:4326; the pinned engine otherwise reprojects implicitly"));
        }
        if layer.features.is_empty() {
            return Err(to_binding_error(
                "zero-feature GeoJSON/GeoJSONSeq output is unsupported because the engine cannot preserve attribute schema",
            ));
        }
        for (i, field) in layer.schema.fields().iter().enumerate() {
            if field.field_type == FieldType::Blob {
                return Err(to_binding_error("GeoJSON Blob writes are unsupported: the engine converts bytes to text"));
            }
            if !layer.features.is_empty()
                && field.field_type != FieldType::Text
                && layer.features.iter().all(|f| f.attributes.get(i).is_none_or(FieldValue::is_null))
            {
                return Err(to_binding_error("GeoJSON cannot preserve the type of an all-null non-Text field"));
            }
            if field.field_type == FieldType::Text
                && layer.features.iter().any(|f| f.attributes.get(i).and_then(FieldValue::as_str).is_some_and(geojson::date_like_text))
            {
                return Err(to_binding_error(
                    "GeoJSON Text values beginning YYYY-MM-DD are unsupported because the reader infers Date/DateTime",
                ));
            }
        }
    }
    terrio_call(write_vector(&[layer], path, &options))?;
    Ok(Robj::from(true))
}

/// The version of the pinned Terrio Rust engine.
///
/// @noRd
#[extendr]
fn engine_version() -> &'static str {
    terrio::VERSION
}

extendr_module! {
    mod terrioR;
    fn vec_list_layers;
    fn vec_read;
    fn vec_layer_summaries;
    fn vec_write;
    fn engine_version;
}
