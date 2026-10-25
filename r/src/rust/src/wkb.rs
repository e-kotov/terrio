//! Validate lengths/types at the R boundary before passing WKB to the engine.
//! This scans structure, not coordinate values or geometry topology.
use terrio::Error;
fn invalid(msg: &str) -> Error {
    Error::InvalidArgument(msg.to_string())
}
struct Scanner<'a> {
    bytes: &'a [u8],
    at: usize,
}
impl Scanner<'_> {
    fn take(&mut self, n: usize) -> Result<&[u8], Error> {
        let end = self.at.checked_add(n).ok_or_else(|| invalid("invalid WKB length"))?;
        let data = self.bytes.get(self.at..end).ok_or_else(|| invalid("truncated WKB payload"))?;
        self.at = end;
        Ok(data)
    }
    fn uint(&mut self, le: bool) -> Result<u32, Error> {
        let a: [u8; 4] = self.take(4)?.try_into().unwrap();
        Ok(if le { u32::from_le_bytes(a) } else { u32::from_be_bytes(a) })
    }
    fn coords(&mut self, le: bool, stride: usize) -> Result<(), Error> {
        let n = self.uint(le)? as usize;
        let bytes = n.checked_mul(stride).ok_or_else(|| invalid("invalid WKB length"))?;
        self.take(bytes)?;
        Ok(())
    }
    fn geom(&mut self, depth: u32) -> Result<u32, Error> {
        if depth > 64 {
            return Err(invalid("WKB nesting exceeds supported depth"));
        }
        let order = self.take(1)?[0];
        if order > 1 {
            return Err(invalid("invalid WKB byte order"));
        }
        let le = order == 1;
        let code = self.uint(le)?;
        if code & 0xffff_0000 != 0 {
            return Err(invalid("EWKB flags are unsupported; supply ISO WKB and CRS metadata separately"));
        }
        if code >= 2000 {
            return Err(invalid("M/XYZM geometries are unsupported by the pinned engine's WKB serializer"));
        }
        let (base, stride) = if code >= 1000 { (code - 1000, 24) } else { (code, 16) };
        match base {
            1 => {
                self.take(stride)?;
            }
            2 => self.coords(le, stride)?,
            3 => {
                let n = self.uint(le)? as usize;
                if n > (self.bytes.len() - self.at) / 4 {
                    return Err(invalid("invalid WKB ring count"));
                }
                for _ in 0..n {
                    self.coords(le, stride)?;
                }
            }
            4..=7 => {
                let n = self.uint(le)? as usize;
                if n > (self.bytes.len() - self.at) / 5 {
                    return Err(invalid("invalid WKB geometry count"));
                }
                for _ in 0..n {
                    let child = self.geom(depth + 1)?;
                    if base != 7 && child != base - 3 {
                        return Err(invalid("invalid WKB collection child type"));
                    }
                }
            }
            _ => return Err(invalid("unsupported WKB geometry type")),
        }
        Ok(base)
    }
}
pub fn validate(bytes: &[u8]) -> Result<(), Error> {
    let mut s = Scanner { bytes, at: 0 };
    s.geom(0)?;
    if s.at != bytes.len() {
        return Err(invalid("invalid WKB length: trailing bytes"));
    }
    Ok(())
}
