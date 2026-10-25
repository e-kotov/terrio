//! Check integer lexemes before the engine can convert unsigned overflow to
//! Null. Scan outside JSON strings; the engine still validates JSON syntax.
use terrio::Error;

// A conservative boundary for the pinned reader's shape-based Date/DateTime
// inference. A known Text field with this prefix cannot be promised Text on
// a subsequent read; require a schema-preserving format instead.
pub fn date_like_text(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() >= 10 && b[4] == b'-' && b[7] == b'-' && b[..10].iter().enumerate().all(|(i, c)| i == 4 || i == 7 || c.is_ascii_digit())
}

pub fn check_integers(path: &str) -> Result<(), Error> {
    let bytes = std::fs::read(path)?;
    let mut at = 0;
    let mut quoted = false;
    while at < bytes.len() {
        let b = bytes[at];
        if quoted {
            match b {
                b'\\' => at += 1,
                b'"' => quoted = false,
                _ => (),
            }
        } else if b == b'"' {
            quoted = true;
        } else if b == b'-' || b.is_ascii_digit() {
            let start = at;
            while at < bytes.len() && matches!(bytes[at], b'0'..=b'9' | b'-' | b'+' | b'.' | b'e' | b'E') {
                at += 1;
            }
            let number = &bytes[start..at];
            if !number.iter().any(|b| matches!(b, b'.' | b'e' | b'E')) {
                let digits = number.strip_prefix(b"-").unwrap_or(number);
                let digits = digits.iter().position(|b| *b != b'0').map_or(&digits[digits.len()..], |i| &digits[i..]);
                if digits.len() > 16 || (digits.len() == 16 && digits > b"9007199254740992".as_slice()) {
                    return Err(Error::InvalidArgument(
                        "GeoJSON integer lexeme beyond 2^53 cannot be represented exactly in R".to_string(),
                    ));
                }
            }
            continue;
        }
        at += 1;
    }
    Ok(())
}
