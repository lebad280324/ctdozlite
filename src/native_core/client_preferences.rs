//! Device-scoped privacy guard preferences, distinct from Zalo account privacy.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::path::Path;

/// Effective outbound-state guards for this local client only.
#[derive(Clone, Copy, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct PrivacyGuard {
    pub block_typing: bool,
    pub block_delivered: bool,
    pub block_seen: bool,
}

#[derive(Default)]
pub(super) struct ClientPreferences {
    guard: PrivacyGuard,
}

impl ClientPreferences {
    pub(super) fn reset(&mut self) {
        self.guard = PrivacyGuard::default();
        self.apply();
    }

    fn apply(&self) {
        crate::session::set_privacy_blocker(
            self.guard.block_typing,
            self.guard.block_delivered,
            self.guard.block_seen,
        );
    }

    pub(super) fn snapshot(&self) -> Value {
        json!({"block_typing":self.guard.block_typing,"block_delivered":self.guard.block_delivered,
            "block_seen":self.guard.block_seen,"scope":"device"})
    }

    pub(super) async fn load(&mut self, db_path: &str, demo: bool) -> Result<Value> {
        if !demo && !db_path.is_empty() {
            let path = Path::new(db_path).with_file_name("native_privacy.json");
            self.guard = tokio::task::spawn_blocking(move || -> Result<_> {
                match std::fs::read(path) {
                    Ok(bytes) => Ok(serde_json::from_slice(&bytes)?),
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                        Ok(PrivacyGuard::default())
                    }
                    Err(error) => Err(error.into()),
                }
            })
            .await??;
        }
        if !demo {
            self.apply();
        }
        Ok(self.snapshot())
    }

    pub(super) async fn save(
        &mut self,
        guard: PrivacyGuard,
        db_path: &str,
        demo: bool,
    ) -> Result<Value> {
        if !demo {
            anyhow::ensure!(!db_path.is_empty(), "missing account storage");
            let path = Path::new(db_path).with_file_name("native_privacy.json");
            let bytes = serde_json::to_vec(&guard)?;
            tokio::task::spawn_blocking(move || {
                crate::data_dir::write_private_atomic(&path, &bytes)
            })
            .await??;
        }
        self.guard = guard;
        if !demo {
            self.apply();
        }
        Ok(self.snapshot())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn demo_privacy_guards_are_local_and_never_open_storage() {
        let mut state = ClientPreferences::default();
        let value = state
            .save(
                PrivacyGuard {
                    block_seen: true,
                    ..Default::default()
                },
                "/no-such-account/private.db",
                true,
            )
            .await
            .unwrap();
        assert_eq!(value["scope"], "device");
        assert_eq!(state.load("", true).await.unwrap()["block_seen"], true);
        state.guard = PrivacyGuard::default();
        assert_eq!(state.snapshot()["block_seen"], false);
    }
    #[test]
    fn incomplete_guard_updates_cannot_silently_disable_other_guards() {
        assert!(serde_json::from_str::<PrivacyGuard>(r#"{"block_seen":true}"#).is_err());
    }
}
