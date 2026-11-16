//! Manual read-only export verification, using an isolated private staging store.
use anyhow::{Context,Result};
use std::path::PathBuf;
struct Scratch(PathBuf);
impl Drop for Scratch{fn drop(&mut self){let _=std::fs::remove_dir_all(&self.0);}}
fn main()->Result<()>{
 let args:Vec<String>=std::env::args().collect();let source=args.get(1).context("Expected export path")?;let session_path=args.get(2).context("Expected native session path")?;
 let compare=args.get(3).is_some_and(|v|v=="--compare");
 if args.get(3).is_some_and(|v|v=="--media-plan"){let mut session=zalo_rust::session::Session::new(false,false,false)?;session.load_from_file(session_path)?;let login=session.login.context("Session unavailable")?;
  let r=zalo_rust::zalo_backup::media::plan_zalo_media(std::path::Path::new(source),&login.dkey,&login.uin,std::path::Path::new("/nonexistent-plan"))?;
  println!("{{\"files\":{},\"bytes\":{},\"linked\":{},\"unmatched\":{}}}",r.files_written+r.files_already_present+0,r.bytes_written,r.messages_linked,r.files_unmatched);return Ok(());}
 if args.get(3).is_some_and(|v|v=="--shapes"){let mut session=zalo_rust::session::Session::new(false,false,false)?;session.load_from_file(session_path)?;let login=session.login.context("Session unavailable")?;
  println!("{}",serde_json::to_string_pretty(&zalo_rust::zalo_backup::survey_message_shapes(std::path::Path::new(source),&login.dkey,&login.uin,args.get(4).map(String::as_str))?)?);return Ok(());}
 if args.get(3).is_some_and(|v|v=="--inspect"){let mut session=zalo_rust::session::Session::new(false,false,false)?;session.load_from_file(session_path)?;let login=session.login.context("Session unavailable")?;
  println!("{}",serde_json::to_string_pretty(&zalo_rust::zalo_backup::inspect_export(std::path::Path::new(source),&login.dkey,&login.uin)?)?);return Ok(());}
 let mut session=zalo_rust::session::Session::new(false,false,false)?;session.load_from_file(session_path)?;let login=session.login.context("Session unavailable")?;
 let scratch=if compare{let p=std::env::temp_dir().join(format!("ctdo-backup-verify-{}-{}",std::process::id(),std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_nanos()));
 #[cfg(unix)]{use std::os::unix::fs::DirBuilderExt;std::fs::DirBuilder::new().mode(0o700).create(&p)?;}
 #[cfg(not(unix))] std::fs::create_dir(&p)?;
 Some(Scratch(p))}else{None};
 let database=scratch.as_ref().map(|s|s.0.join("source.sqlite"));let database=database.as_ref().map(|p|p.to_string_lossy().into_owned()).unwrap_or_else(||":memory:".into());
 let report=zalo_rust::zalo_backup::import_zalo_export(std::path::Path::new(source),&login.dkey,&login.uin,&database,|_,_|{})?;
 let mut result=serde_json::json!({"threads":report.threads_imported,"messages_imported":report.messages_imported,"messages_seen":report.messages_seen,"skipped_rows":report.lines_skipped,"database_files":report.database_files,"cancelled":report.cancelled});
 if compare{
  let live=std::path::Path::new(session_path).parent().context("Session directory unavailable")?.join("accounts").join(&login.uin).join("native_history.db");
  let conn=rusqlite::Connection::open(&database)?;
  let uri=format!("file:{}?mode=ro",live.to_string_lossy());conn.execute("ATTACH DATABASE ?1 AS restored",[uri])?;
  for (name,sql) in [
   ("missing_messages","SELECT count(*) FROM main.messages s LEFT JOIN restored.messages r ON r.msg_id=s.msg_id WHERE r.msg_id IS NULL"),
   ("different_thread","SELECT count(*) FROM main.messages s JOIN restored.messages r ON r.msg_id=s.msg_id WHERE r.thread_id<>s.thread_id"),
   ("different_text","SELECT count(*) FROM main.messages s JOIN restored.messages r ON r.msg_id=s.msg_id WHERE r.text<>s.text"),
   ("different_timestamp","SELECT count(*) FROM main.messages s JOIN restored.messages r ON r.msg_id=s.msg_id WHERE r.ts<>s.ts"),
   ("different_direction","SELECT count(*) FROM main.messages s JOIN restored.messages r ON r.msg_id=s.msg_id WHERE r.is_outgoing<>s.is_outgoing"),
   ("missing_threads","SELECT count(*) FROM main.threads s LEFT JOIN restored.threads r ON r.thread_id=s.thread_id WHERE r.thread_id IS NULL")
  ]{let n:i64=conn.query_row(sql,[],|r|r.get(0))?;result[name]=serde_json::json!(n);}
 }
 println!("{result}");Ok(())
}
