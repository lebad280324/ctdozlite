//! Read only the account-matched PC sync-state credential needed for an export.
//! No cookies, message databases or unrelated local-storage values leave this module.
use serde_json::Value;
use std::{fs, path::Path};
const LIMIT: usize = 32 * 1024 * 1024;
fn varint(b: &[u8], p: &mut usize) -> Option<u64> {
    let mut n = 0;
    for shift in (0..64).step_by(7) {
        let v = *b.get(*p)?;
        *p += 1;
        n |= u64::from(v & 127) << shift;
        if v < 128 {
            return Some(n);
        }
    }
    None
}
fn span<'a>(b: &'a [u8], p: &mut usize, n: usize) -> Option<&'a [u8]> {
    let end = p.checked_add(n)?;
    let v = b.get(*p..end)?;
    *p = end;
    Some(v)
}
fn sized<'a>(b: &'a [u8], p: &mut usize) -> Option<&'a [u8]> {
    let n = usize::try_from(varint(b, p)?).ok()?;
    span(b, p, n)
}
fn snappy(b: &[u8]) -> Option<Vec<u8>> {
    let mut p = 0;
    let size = usize::try_from(varint(b, &mut p)?).ok()?;
    if size > LIMIT {
        return None;
    }
    let mut out = Vec::with_capacity(size);
    while p < b.len() {
        let tag = *span(b, &mut p, 1)?.first()?;
        let kind = tag & 3;
        if kind == 0 {
            let code = usize::from(tag >> 2);
            let n = if code < 60 {
                code + 1
            } else {
                let extra = span(b, &mut p, code - 59)?;
                let mut n = 0usize;
                for (i, v) in extra.iter().enumerate() {
                    n |= usize::from(*v) << (8 * i)
                }
                n.checked_add(1)?
            };
            if out.len().checked_add(n)? > size {
                return None;
            }
            out.extend_from_slice(span(b, &mut p, n)?)
        } else {
            let (n, offset) = if kind == 1 {
                (
                    4 + usize::from((tag >> 2) & 7),
                    (usize::from(tag & 224) << 3) | usize::from(span(b, &mut p, 1)?[0]),
                )
            } else {
                let k = if kind == 2 { 2 } else { 4 };
                let raw = span(b, &mut p, k)?;
                let mut off = 0;
                for (i, v) in raw.iter().enumerate() {
                    off |= usize::from(*v) << (8 * i)
                }
                (1 + usize::from(tag >> 2), off)
            };
            if offset == 0 || offset > out.len() || out.len().checked_add(n)? > size {
                return None;
            }
            for _ in 0..n {
                out.push(out[out.len() - offset]);
            }
        }
    }
    (out.len() == size).then_some(out)
}
fn entries(b: &[u8]) -> Option<Vec<(Vec<u8>, Vec<u8>)>> {
    let count = u32::from_le_bytes(b.get(b.len().checked_sub(4)?..)?.try_into().ok()?) as usize;
    let end = b
        .len()
        .checked_sub(4usize.checked_add(4usize.checked_mul(count)?)?)?;
    let mut p = 0;
    let mut key = Vec::new();
    let mut rows = Vec::new();
    while p < end {
        let shared = usize::try_from(varint(b, &mut p)?).ok()?;
        let n = usize::try_from(varint(b, &mut p)?).ok()?;
        let v = usize::try_from(varint(b, &mut p)?).ok()?;
        if shared > key.len() {
            return None;
        }
        key.truncate(shared);
        key.extend_from_slice(span(b, &mut p, n)?);
        let value = span(b, &mut p, v)?;
        if p > end {
            return None;
        }
        if rows.len() >= 100000 {
            return None;
        }
        rows.push((key.clone(), value.to_vec()));
    }
    Some(rows)
}
fn block(b: &[u8], off: usize, n: usize) -> Option<Vec<u8>> {
    let end = off.checked_add(n)?;
    let raw = b.get(off..end)?;
    match b.get(end)? {
        0 => Some(raw.to_vec()),
        1 => snappy(raw),
        _ => None,
    }
}
fn table(b: &[u8]) -> Option<Vec<(Vec<u8>, Vec<u8>)>> {
    if b.len() < 48 || b[b.len() - 8..] != [0x57, 0xfb, 0x80, 0x8b, 0x24, 0x75, 0x47, 0xdb] {
        return None;
    }
    let footer = &b[b.len() - 48..];
    let mut p = 0;
    varint(footer, &mut p)?;
    varint(footer, &mut p)?;
    let off = usize::try_from(varint(footer, &mut p)?).ok()?;
    let n = usize::try_from(varint(footer, &mut p)?).ok()?;
    let mut rows = Vec::new();
    for (_, handle) in entries(&block(b, off, n)?)? {
        let mut p = 0;
        let off = usize::try_from(varint(&handle, &mut p)?).ok()?;
        let n = usize::try_from(varint(&handle, &mut p)?).ok()?;
        let part = entries(&block(b, off, n)?)?;
        let total = rows
            .iter()
            .map(|(k, v): &(Vec<u8>, Vec<u8>)| k.len() + v.len())
            .sum::<usize>()
            + part.iter().map(|(k, v)| k.len() + v.len()).sum::<usize>();
        if total > LIMIT {
            return None;
        }
        rows.extend(part);
    }
    Some(rows)
}
fn log_rows(b: &[u8]) -> Vec<(Vec<u8>, Vec<u8>)> {
    let mut rows = Vec::new();
    let mut pending = Vec::new();
    let mut p = 0;
    while p + 7 <= b.len() {
        let remain = 32768 - p % 32768;
        if remain < 7 {
            p += remain;
            continue;
        }
        let n = usize::from(u16::from_le_bytes([b[p + 4], b[p + 5]]));
        let kind = b[p + 6];
        if n + 7 > remain || p + 7 + n > b.len() {
            break;
        }
        let chunk = &b[p + 7..p + 7 + n];
        p += 7 + n;
        match kind {
            1 => {
                pending.clear();
                pending.extend_from_slice(chunk)
            }
            2 => {
                pending.clear();
                pending.extend_from_slice(chunk);
                continue;
            }
            3 | 4 => {
                if pending.len() + chunk.len() > LIMIT {
                    pending.clear();
                    continue;
                }
                pending.extend_from_slice(chunk);
                if kind == 3 {
                    continue;
                }
            }
            _ => continue,
        }
        if pending.len() < 12 {
            continue;
        }
        let count = u32::from_le_bytes(pending[8..12].try_into().unwrap_or_default());
        let mut pos = 12;
        for _ in 0..count.min(100000) {
            let Some(tag) = span(&pending, &mut pos, 1) else {
                break;
            };
            let tag = tag[0];
            let Some(key) = sized(&pending, &mut pos) else {
                break;
            };
            if tag == 1 {
                let Some(value) = sized(&pending, &mut pos) else {
                    break;
                };
                rows.push((key.to_vec(), value.to_vec()));
            } else if tag != 0 {
                break;
            }
        }
        pending.clear();
    }
    rows
}
fn credential(key: &[u8], value: &[u8], account: &str) -> Option<String> {
    if !key
        .windows(b"_sync_cross_state_backup".len())
        .any(|w| w == b"_sync_cross_state_backup")
    {
        return None;
    }
    let (&encoding, bytes) = value.split_first()?;
    let text = if encoding == 0 {
        if bytes.len() % 2 != 0 {
            return None;
        }
        String::from_utf16(
            &bytes
                .chunks_exact(2)
                .map(|v| u16::from_le_bytes([v[0], v[1]]))
                .collect::<Vec<_>>(),
        )
        .ok()?
    } else if encoding == 1 {
        bytes.iter().map(|b| char::from(*b)).collect()
    } else {
        return None;
    };
    let data: Value = serde_json::from_str(&text).ok()?;
    let state = data.get("value")?;
    let uid = state.get("userId")?;
    let uid = uid
        .as_str()
        .map(str::to_owned)
        .or_else(|| uid.as_u64().map(|v| v.to_string()))?;
    if uid != account {
        return None;
    }
    let key = state.get("uin")?.as_str()?;
    if !(13..=256).contains(&key.len()) {
        return None;
    }
    Some(key.to_owned())
}
/// Returns bounded account-matched candidates; callers must validate tar before use.
pub(super) fn candidates(directory: &Path, account: &str) -> Vec<String> {
    let Ok(files) = fs::read_dir(directory) else {
        return Vec::new();
    };
    let mut paths: Vec<_> = files
        .flatten()
        .map(|e| e.path())
        .filter(|p| matches!(p.extension().and_then(|e| e.to_str()), Some("ldb" | "log")))
        .collect();
    paths.sort();
    paths.reverse();
    let mut keys = Vec::new();
    for path in paths.into_iter().take(64) {
        let Ok(meta) = fs::symlink_metadata(&path) else {
            continue;
        };
        if !meta.is_file() || meta.file_type().is_symlink() || meta.len() > LIMIT as u64 {
            continue;
        }
        let Ok(b) = fs::read(&path) else { continue };
        let rows = if path.extension().is_some_and(|e| e == "ldb") {
            table(&b).unwrap_or_default()
        } else {
            log_rows(&b)
        };
        for (k, v) in rows {
            if let Some(key) = credential(&k, &v, account) {
                if !keys.contains(&key) {
                    keys.push(key);
                }
            }
        }
    }
    keys
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn key_metadata_requires_exact_account_and_known_record() {
        let value = br#"{"value":{"userId":"user-1","uin":"fake-key-000000000000000000000000"}}"#;
        let mut encoded = vec![1];
        encoded.extend_from_slice(value);
        assert!(credential(b"_file://0_sync_cross_state_backup", &encoded, "user-1").is_some());
        assert!(credential(b"_file://0_sync_cross_state_backup", &encoded, "user-2").is_none());
        assert!(credential(b"other-private-state", &encoded, "user-1").is_none());
    }
    #[test]
    fn snappy_literals_and_overlapping_copies_decode() {
        assert_eq!(snappy(&[3, 8, b'a', b'b', b'c']).unwrap(), b"abc");
        assert_eq!(
            snappy(&[6, 8, b'a', b'b', b'c', 10, 3, 0]).unwrap(),
            b"abcabc"
        );
    }
    #[test]
    fn malformed_compressed_blocks_are_rejected() {
        assert!(snappy(&[100, 1, 0]).is_none());
        assert!(entries(&[0, 0, 0]).is_none());
        assert!(table(&[0; 48]).is_none());
    }
}
