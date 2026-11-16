//! Media import from a Zalo PC export: photos, videos and files under `ZaloDownloads/`.
//!
//! The export keeps attachments next to the message database (re-notes/64):
//! `<uid>/ZaloDownloads/resource/<conversation>/{picture,video}/<cliMsgId>_<conv>_<sender>_<hash>.<ext>`
//! (`.../file/<cliMsgId>_...` for documents, without an extension). A few rows carry `localPath`;
//! the rest are matched by conversation, kind and the send time in the file name. Bodies are copied as they
//! are (photos are JPEG XL, which macOS decodes); nothing is uploaded or re-encoded.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read};
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::Ordering;

use anyhow::{bail, Context, Result};

use super::{
    conversation_identity, database_table, derive_key_iv, message_from_row, next_entry,
    resolve_export_key, text_of, BackupError, CbcReader, ContainerVersion, Table, IMPORT_CANCEL,
    MAX_FILL, MAX_LINE_BYTES, TAR_BLOCK,
};
use crate::store::MessageStore;

/// Largest single attachment copied out of an export.
const MAX_MEDIA_FILE: u64 = 4 * 1024 * 1024 * 1024;
/// How far a message's server time may trail the client time in a photo's file name.
const MATCH_BEFORE_MS: i64 = 5_000;
const MATCH_AFTER_MS: i64 = 180_000;

/// Outcome of one media import. Counts only, never content or names.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct MediaReport {
    pub files_written: usize,
    pub files_already_present: usize,
    pub bytes_written: u64,
    pub messages_linked: usize,
    pub files_unmatched: usize,
    pub cancelled: bool,
}

#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
enum Kind {
    Photo,
    Video,
    File,
}

struct MediaRow {
    msg_id: String,
    thread_id: String,
    ts: i64,
    kind: Option<Kind>,
    local_path: Option<String>,
    file_name: Option<String>,
}

struct Extracted {
    relative: String,
    absolute: PathBuf,
}

/// The part of an export path below `ZaloDownloads/`, when it is an attachment worth copying.
fn attachment_path(path: &str) -> Option<String> {
    let (_, below) = path.split_once("ZaloDownloads/")?;
    // `file/<hash>` holds second copies of the files in `resource/<conversation>/file/` (same sizes,
    // 442 of 442 in a real export), so only `resource/` is copied.
    if !below.starts_with("resource/") {
        return None;
    }
    let name = below.rsplit('/').next()?;
    if name.is_empty() || name.starts_with('.') {
        return None;
    }
    Some(below.to_owned())
}

/// Rejects anything that could leave the media folder.
fn safe_relative(relative: &str) -> Option<PathBuf> {
    let path = Path::new(relative);
    if relative.len() > 1024 || path.is_absolute() {
        return None;
    }
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Normal(part) if !part.is_empty() => out.push(part),
            _ => return None,
        }
    }
    (!out.as_os_str().is_empty()).then_some(out)
}

fn kind_of(code: i64, msg_type: &str) -> Option<Kind> {
    match (code, msg_type) {
        (2, _) | (_, "chat.photo") => Some(Kind::Photo),
        (18, _) | (_, "chat.video") => Some(Kind::Video),
        (19, _) | (_, "chat.file") => Some(Kind::File),
        _ => None,
    }
}

fn file_name_of(text: &str, raw_json: &str) -> Option<String> {
    let meta: serde_json::Value = serde_json::from_str(raw_json).unwrap_or(serde_json::Value::Null);
    let candidate = meta
        .get("link_title")
        .and_then(serde_json::Value::as_str)
        .map(str::to_owned)
        .unwrap_or_else(|| text.trim_start_matches("[Tập tin]").trim().to_owned());
    let candidate = candidate.trim().to_owned();
    (!candidate.is_empty() && !candidate.contains('/')).then_some(candidate)
}

fn row_from(row: &serde_json::Value, own_uid: &str) -> Option<MediaRow> {
    let local = text_of(row.get("localPath"));
    let local_path = local.split_once("ZaloDownloads/").map(|(_, below)| below.to_owned());
    let message = message_from_row(row, own_uid)?;
    let code = match row.get("msgType") {
        Some(serde_json::Value::Number(number)) => number.as_i64().unwrap_or(0),
        Some(serde_json::Value::String(text)) => text.parse().unwrap_or(0),
        _ => 0,
    };
    let kind = kind_of(code, &message.msg_type);
    if kind.is_none() && local_path.is_none() {
        return None;
    }
    Some(MediaRow {
        file_name: if kind == Some(Kind::File) { file_name_of(&message.text, &message.raw_json) } else { None },
        msg_id: message.msg_id,
        thread_id: message.thread_id,
        ts: message.ts,
        kind,
        local_path,
    })
}

/// `resource/<conversation>/<picture|video>/<clientMs>_...` → (thread, kind, client time).
fn resource_hint(relative: &str) -> Option<(String, Kind, i64)> {
    let mut parts = relative.split('/');
    if parts.next()? != "resource" {
        return None;
    }
    let conversation = parts.next()?;
    let kind = match parts.next()? {
        "picture" | "photo" | "image" => Kind::Photo,
        "video" => Kind::Video,
        "file" => Kind::File,
        _ => return None,
    };
    let name = parts.next()?;
    let sent: i64 = name.split('_').next()?.parse().ok()?;
    let (thread_id, _) = conversation_identity(conversation);
    Some((thread_id, kind, sent))
}

/// Copies attachments out of `source` into `media_root` and links them to stored messages.
///
/// # Errors
/// Fails for a wrong account key, an unreadable export, or a full disk.
pub fn import_zalo_media(
    source: &Path,
    data_key: &str,
    own_uid: &str,
    db_path: &str,
    media_root: &Path,
    progress: impl FnMut(f64, usize),
) -> Result<MediaReport> {
    run(source, data_key, own_uid, db_path, media_root, true, progress)
}

/// Counts what an import would copy and link, without writing files or the database.
///
/// # Errors
/// As [`import_zalo_media`].
pub fn plan_zalo_media(source: &Path, data_key: &str, own_uid: &str, media_root: &Path) -> Result<MediaReport> {
    run(source, data_key, own_uid, "", media_root, false, |_, _| {})
}

fn run(
    source: &Path,
    data_key: &str,
    own_uid: &str,
    db_path: &str,
    media_root: &Path,
    write: bool,
    mut progress: impl FnMut(f64, usize),
) -> Result<MediaReport> {
    let version = ContainerVersion::from_path(source)
        .context(BackupError("Hãy chọn tệp .zl.zip do Zalo xuất ra."))?;
    let key_source = resolve_export_key(source, data_key, own_uid)?;
    let (key, iv) = derive_key_iv(&key_source, version)?;
    let mut reader = CbcReader::open(source, key, iv)?;
    let total = reader.cipher_len.max(1);
    if write {
        std::fs::create_dir_all(media_root)?;
    }
    let mut report = MediaReport::default();
    let mut rows: Vec<MediaRow> = Vec::new();
    let mut extracted: Vec<Extracted> = Vec::new();
    let mut renamed: HashMap<PathBuf, HashMap<String, (PathBuf, u64)>> = HashMap::new();
    let mut first = true;
    let mut line = Vec::new();
    while let Some(entry) = next_entry(&mut reader, first)? {
        first = false;
        let padding = entry.size.div_ceil(TAR_BLOCK) * TAR_BLOCK - entry.size;
        let regular = matches!(entry.kind, b'0' | 0);
        if regular && matches!(database_table(&entry.path), Some(Table::Message)) {
            let mut lines = BufReader::with_capacity(MAX_FILL, (&mut reader).take(entry.size));
            loop {
                line.clear();
                if (&mut lines).take(MAX_LINE_BYTES as u64 + 1).read_until(b'\n', &mut line)? == 0 {
                    break;
                }
                if let Ok(row) = serde_json::from_slice::<serde_json::Value>(line.strip_suffix(b"\n").unwrap_or(&line)) {
                    if let Some(media) = row_from(&row, own_uid) {
                        rows.push(media);
                    }
                }
            }
            let unread = lines.get_ref().limit();
            drop(lines);
            reader.skip(unread + padding)?;
        } else if let Some(relative) = attachment_path(&entry.path).filter(|_| regular && entry.size > 0 && entry.size <= MAX_MEDIA_FILE) {
            let Some(safe) = safe_relative(&relative) else {
                reader.skip(entry.size + padding)?;
                continue;
            };
            let mut destination = media_root.join(&safe);
            if write && destination.extension().is_none() {
                // A document copied earlier got its extension back; reuse that copy.
                if let Some(existing) = renamed_copy(&destination, entry.size, &mut renamed) {
                    destination = existing;
                }
            }
            if !write {
                report.bytes_written += entry.size;
                reader.skip(entry.size + padding)?;
            } else if std::fs::metadata(&destination).is_ok_and(|meta| meta.len() == entry.size) {
                report.files_already_present += 1;
                reader.skip(entry.size + padding)?;
            } else {
                if let Some(parent) = destination.parent() {
                    std::fs::create_dir_all(parent)?;
                }
                let partial = destination.with_extension("partial-import");
                let mut file = std::fs::File::create(&partial)?;
                let copied = std::io::copy(&mut (&mut reader).take(entry.size), &mut file)?;
                drop(file);
                if copied != entry.size {
                    let _ = std::fs::remove_file(&partial);
                    bail!(BackupError("Tệp sao lưu bị cắt ngang."));
                }
                std::fs::rename(&partial, &destination)?;
                report.files_written += 1;
                report.bytes_written += entry.size;
                reader.skip(padding)?;
            }
            extracted.push(Extracted { relative, absolute: destination });
        } else {
            reader.skip(entry.size + padding)?;
        }
        progress(reader.position() as f64 / total as f64, extracted.len());
        if IMPORT_CANCEL.load(Ordering::Relaxed) {
            report.cancelled = true;
            break;
        }
    }
    if first {
        bail!(BackupError("Tệp sao lưu trống."));
    }
    let mut links = match_files(&rows, &extracted);
    if write {
        restore_extensions(&rows, &mut links);
    }
    report.files_unmatched = extracted.len().saturating_sub(links.len());
    report.messages_linked = if write { write_links(db_path, &links)? } else { links.len() };
    Ok(report)
}

/// An earlier copy of `destination` saved as `<name>.<ext>` with the same size, if any. Directory
/// listings are read once per folder.
fn renamed_copy(
    destination: &Path,
    size: u64,
    cache: &mut HashMap<PathBuf, HashMap<String, (PathBuf, u64)>>,
) -> Option<PathBuf> {
    let parent = destination.parent()?;
    let name = destination.file_name()?.to_str()?;
    let listing = cache.entry(parent.to_path_buf()).or_insert_with(|| {
        let mut found = HashMap::new();
        for entry in std::fs::read_dir(parent).into_iter().flatten().flatten() {
            let path = entry.path();
            if let (Some(stem), Some(_), Ok(meta)) = (path.file_stem().and_then(|s| s.to_str()), path.extension(), entry.metadata()) {
                found.insert(stem.to_owned(), (path.clone(), meta.len()));
            }
        }
        found
    });
    listing.get(name).filter(|(_, length)| *length == size).map(|(path, _)| path.clone())
}

/// Message ID → absolute file path.
fn match_files(rows: &[MediaRow], extracted: &[Extracted]) -> HashMap<String, String> {
    let mut links: HashMap<String, String> = HashMap::new();
    let mut used = vec![false; extracted.len()];
    let by_relative: HashMap<&str, usize> = extracted.iter().enumerate().map(|(i, e)| (e.relative.as_str(), i)).collect();
    // 1. Rows that name their file.
    for row in rows {
        let Some(local) = row.local_path.as_deref() else { continue };
        let found = by_relative.get(local).copied().or_else(|| {
            extracted.iter().position(|e| e.relative.starts_with(local) && e.relative.len() <= local.len() + 8)
        });
        if let Some(index) = found.filter(|index| !used[*index]) {
            used[index] = true;
            links.insert(row.msg_id.clone(), extracted[index].absolute.to_string_lossy().into_owned());
        }
    }
    // 2. Photos and videos by conversation, kind and the nearest send time.
    let mut candidates: HashMap<(String, Kind), Vec<usize>> = HashMap::new();
    for (index, row) in rows.iter().enumerate() {
        if let Some(kind) = row.kind {
            if !links.contains_key(&row.msg_id) {
                candidates.entry((row.thread_id.clone(), kind)).or_default().push(index);
            }
        }
    }
    for (index, file) in extracted.iter().enumerate() {
        if used[index] {
            continue;
        }
        let Some((thread_id, kind, sent)) = resource_hint(&file.relative) else { continue };
        let Some(pool) = candidates.get(&(thread_id, kind)) else { continue };
        let best = pool
            .iter()
            .filter(|row| !links.contains_key(&rows[**row].msg_id))
            .filter(|row| (-MATCH_BEFORE_MS..=MATCH_AFTER_MS).contains(&(rows[**row].ts - sent)))
            .min_by_key(|row| (rows[**row].ts - sent).abs());
        if let Some(row) = best {
            used[index] = true;
            links.insert(rows[*row].msg_id.clone(), file.absolute.to_string_lossy().into_owned());
        }
    }
    links
}

/// Zalo stores some files without an extension; take it from the file name in the message so the
/// copy opens in the right application.
fn restore_extensions(rows: &[MediaRow], links: &mut HashMap<String, String>) {
    let names: HashMap<&str, &str> = rows
        .iter()
        .filter_map(|row| row.file_name.as_deref().map(|name| (row.msg_id.as_str(), name)))
        .collect();
    for (msg_id, path) in links.iter_mut() {
        let current = PathBuf::from(&*path);
        if current.extension().is_some() {
            continue;
        }
        let Some(extension) = names
            .get(msg_id.as_str())
            .and_then(|name| Path::new(name).extension())
            .and_then(|ext| ext.to_str())
            .filter(|ext| !ext.is_empty() && ext.len() <= 10 && ext.chars().all(|c| c.is_ascii_alphanumeric()))
        else {
            continue;
        };
        let renamed = current.with_extension(extension);
        if std::fs::rename(&current, &renamed).is_ok() || renamed.exists() {
            *path = renamed.to_string_lossy().into_owned();
        }
    }
}

/// Adds `local_path` to each linked message's stored metadata.
fn write_links(db_path: &str, links: &HashMap<String, String>) -> Result<usize> {
    if links.is_empty() {
        return Ok(0);
    }
    let store = MessageStore::open(db_path)?;
    store.conn.execute_batch("BEGIN")?;
    let outcome = (|| -> Result<usize> {
        let mut read = store.conn.prepare("SELECT raw_json FROM messages WHERE msg_id = ?1")?;
        let mut write = store.conn.prepare("UPDATE messages SET raw_json = ?2 WHERE msg_id = ?1")?;
        let mut linked = 0;
        for (msg_id, path) in links {
            let raw: Option<String> = read.query_row([msg_id], |row| row.get(0)).ok();
            let Some(raw) = raw else { continue };
            let mut meta = serde_json::from_str::<serde_json::Map<String, serde_json::Value>>(&raw).unwrap_or_default();
            meta.insert("local_path".into(), serde_json::Value::String(path.clone()));
            write.execute(rusqlite::params![msg_id, serde_json::Value::Object(meta).to_string()])?;
            linked += 1;
        }
        Ok(linked)
    })();
    store.conn.execute_batch(if outcome.is_ok() { "COMMIT" } else { "ROLLBACK" })?;
    outcome
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(id: &str, thread: &str, ts: i64, kind: Kind, local: Option<&str>, name: Option<&str>) -> MediaRow {
        MediaRow {
            msg_id: id.into(),
            thread_id: thread.into(),
            ts,
            kind: Some(kind),
            local_path: local.map(str::to_owned),
            file_name: name.map(str::to_owned),
        }
    }
    fn file(relative: &str) -> Extracted {
        Extracted { relative: relative.into(), absolute: PathBuf::from("/m").join(relative) }
    }

    #[test]
    fn attachments_are_matched_by_path_time_and_name() {
        let rows = vec![
            row("p1", "1080", 1_790_764_514_850, Kind::Photo, None, None),
            row("p2", "1080", 1_790_764_600_000, Kind::Photo, None, None),
            row("v1", "g9", 1_792_979_003_900, Kind::Video, Some("resource/g9/video/1792979003285_68_g9"), None),
            row("f1", "55", 1_700_000_001_000, Kind::File, None, Some("Bao_cao.docx")),
        ];
        let files = vec![
            file("resource/1080/picture/1790764513726_1080_1080_abc.jxl"),
            file("resource/g9/video/1792979003285_68_g9.mp4"),
            file("resource/55/file/1700000000500_77_55"),
            file("resource/1080/picture/1700000000000_1080_1080_old.jxl"),
        ];
        let links = match_files(&rows, &files);
        assert_eq!(links.get("p1").map(String::as_str), Some("/m/resource/1080/picture/1790764513726_1080_1080_abc.jxl"));
        assert_eq!(links.get("v1").map(String::as_str), Some("/m/resource/g9/video/1792979003285_68_g9.mp4"));
        assert_eq!(links.get("f1").map(String::as_str), Some("/m/resource/55/file/1700000000500_77_55"));
        // Too far from any photo message: left unlinked rather than guessed.
        assert!(!links.contains_key("p2"));
        assert_eq!(links.len(), 3);
    }

    #[test]
    fn only_attachment_folders_inside_the_export_are_copied() {
        assert_eq!(attachment_path("1/ZaloDownloads/resource/2/file/17_3_2").as_deref(), Some("resource/2/file/17_3_2"));
        // The `file/` folder only repeats files already under `resource/`.
        assert!(attachment_path("1/ZaloDownloads/file/a.pdf").is_none());
        assert!(attachment_path("1/ZaloDownloads/database/1_zmessage.zdb").is_none());
        assert!(attachment_path("1/ZaloDownloads/resource/2/picture/.rescache").is_none());
        assert!(safe_relative("file/../../etc/passwd").is_none());
        assert!(safe_relative("/abs/x").is_none());
        assert!(safe_relative("resource/2/picture/x.jxl").is_some());
    }
}
