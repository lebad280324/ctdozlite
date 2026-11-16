//! Zalo account settings from the shipped desktop request functions.
//! Evidence and numeric values: re-notes/47_native_ba_settings.md.

use crate::session::Session;
use anyhow::{anyhow, ensure, Result};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::BTreeMap;

#[derive(Clone, Deserialize, Serialize)]
#[serde(tag = "command", rename_all = "snake_case")]
pub(super) enum SettingsCommand {
    GetAccountSettings,
    SetAccountSetting {
        key: String,
        value: i64,
    },
    SetTwoFactor {
        enabled: bool,
        #[serde(default)]
        otp: Option<String>,
    },
}
impl SettingsCommand {
    pub(super) fn name(&self) -> &'static str {
        match self {
            Self::GetAccountSettings => "get_account_settings",
            Self::SetAccountSetting { .. } => "set_account_setting",
            Self::SetTwoFactor { .. } => "set_two_factor",
        }
    }
}
pub(super) fn commands() -> &'static [&'static str] {
    &[
        "get_account_settings",
        "set_account_setting",
        "set_two_factor",
    ]
}
const BOOLEAN_KEYS: &[&str] = &[
    "show_online_status",
    "show_seen",
    "display_seen_status",
    "add_friend_via_phone",
    "add_friend_via_qr",
    "add_friend_via_group",
    "add_friend_via_contact",
    "display_on_recommend_friend",
    "quick_message_status",
];
fn allowed(key: &str, value: i64) -> bool {
    if BOOLEAN_KEYS.contains(&key) {
        return matches!(value, 0 | 1);
    }
    match key {
        "view_birthday" => (0..=2).contains(&value),
        "receive_message" => matches!(value, 1 | 2),
        "accept_stranger_call" => matches!(value, 2..=4),
        _ => false,
    }
}
fn public_settings(response: &Value) -> BTreeMap<String, i64> {
    let mut result = BTreeMap::new();
    if let Some(data) = response.get("data").and_then(Value::as_object) {
        for (key, value) in data {
            let numeric = value.as_i64().or_else(|| value.as_bool().map(i64::from));
            if let Some(value) = numeric {
                if allowed(key, value) || (key == "setting_2FA_status" && matches!(value, 0 | 1)) {
                    result.insert(key.clone(), value);
                }
            }
        }
    }
    result
}
fn check(response: &Value) -> Result<()> {
    let code = response
        .get("error_code")
        .and_then(Value::as_i64)
        .ok_or_else(|| anyhow!(super::UserError("Không đọc được phản hồi cài đặt.")))?;
    if code != 0 {
        return Err(crate::session::SessionError::new(code, "Account setting rejected").into());
    }
    Ok(())
}
async fn fetch(session: &Session) -> Result<BTreeMap<String, i64>> {
    let url = format!(
        "{}/api/setting/me?{}",
        crate::endpoints::AUTH,
        session.common_params()
    );
    let response = session.get(&url).await?;
    let response = session
        .maybe_decrypt(response, session.session_key_bytes())
        .await;
    check(&response)?;
    Ok(public_settings(&response))
}
#[derive(Default)]
pub(super) struct SettingsState {
    demo_values: BTreeMap<String, i64>,
}
impl SettingsState {
    pub(super) fn reset(&mut self) {
        self.demo_values.clear();
    }
    pub(super) async fn execute(
        &mut self,
        command: &SettingsCommand,
        session: &Session,
        demo: bool,
    ) -> Result<Value> {
        let expected = match command {
            SettingsCommand::GetAccountSettings => None,
            SettingsCommand::SetAccountSetting { key, value } => {
                ensure!(
                    allowed(key, *value),
                    super::UserError("Giá trị cài đặt không được hỗ trợ.")
                );
                if !demo {
                    let mut body = serde_json::Map::new();
                    body.insert(key.clone(), json!(value));
                    let params = session.encoded_params(&Value::Object(body))?;
                    let url = format!(
                        "{}/api/setting/update?{}&params={params}",
                        crate::endpoints::AUTH,
                        session.common_params()
                    );
                    let response = session.get(&url).await?;
                    check(
                        &session
                            .maybe_decrypt(response, session.session_key_bytes())
                            .await,
                    )?;
                }
                Some((key.clone(), *value))
            }
            SettingsCommand::SetTwoFactor { enabled, otp } => {
                if let Some(otp) = otp {
                    ensure!(
                        (4..=12).contains(&otp.len()) && otp.bytes().all(|b| b.is_ascii_digit()),
                        super::UserError("Mã OTP phải gồm 4 đến 12 chữ số.")
                    );
                }
                if !demo {
                    let mut body = json!({"updateType":if *enabled {1}else{2},"submitOTP":if otp.is_some(){1}else{0},"imei":session.imei});
                    if let Some(otp) = otp {
                        body["otp"] = json!(otp);
                    }
                    let params = session.encoded_params(&body)?;
                    let url = format!(
                        "{}/api/update/setting/2FA?{}&params={params}",
                        crate::endpoints::AUTH,
                        session.common_params()
                    );
                    let response = session.get(&url).await?;
                    check(
                        &session
                            .maybe_decrypt(response, session.session_key_bytes())
                            .await,
                    )?;
                }
                Some(("setting_2FA_status".into(), i64::from(*enabled)))
            }
        };
        let settings = if demo {
            if self.demo_values.is_empty() {
                for key in BOOLEAN_KEYS {
                    self.demo_values.insert((*key).into(), 1);
                }
                self.demo_values.extend([
                    ("view_birthday".into(), 2),
                    ("receive_message".into(), 2),
                    ("accept_stranger_call".into(), 2),
                    ("setting_2FA_status".into(), 0),
                ]);
            }
            if let Some((key, value)) = &expected {
                self.demo_values.insert(key.clone(), *value);
            }
            self.demo_values.clone()
        } else {
            fetch(session).await?
        };
        if let Some((key, value)) = &expected {
            ensure!(settings.get(key)==Some(value),super::UserError("Đã gửi yêu cầu nhưng chưa xác nhận được giá trị mới. Hãy làm mới cài đặt trước khi thử lại."));
        }
        Ok(json!({"settings":settings,"scope":if demo {"demo"}else{"account"}}))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn settings_allow_only_observed_keys_and_values() {
        assert!(allowed("accept_stranger_call", 4));
        assert!(!allowed("accept_stranger_call", 1));
        assert!(!allowed("setting_2FA_status", 1));
        assert!(!allowed("unknown", 1));
        assert!(allowed("view_birthday", 2));
        assert!(!allowed("view_birthday", 3));
    }
    #[test]
    fn snapshots_cannot_expose_raw_server_credentials_or_phone() {
        let settings = public_settings(
            &json!({"data":{"view_birthday":2,"show_online_status":true,"zpw_sek":"secret","phone":"private","setting_2FA_status":1}}),
        );
        assert_eq!(settings.len(), 3);
        assert!(!serde_json::to_string(&settings).unwrap().contains("secret"));
    }
    #[tokio::test]
    async fn two_factor_demo_and_otp_validation_never_contact_server() {
        let session = Session::new(false, false, false).unwrap();
        let mut state = SettingsState::default();
        assert!(state
            .execute(
                &SettingsCommand::SetTwoFactor {
                    enabled: true,
                    otp: Some("not-an-otp".into())
                },
                &session,
                true
            )
            .await
            .is_err());
        let value = state
            .execute(
                &SettingsCommand::SetTwoFactor {
                    enabled: true,
                    otp: Some("123456".into()),
                },
                &session,
                true,
            )
            .await
            .unwrap();
        assert_eq!(value["settings"]["setting_2FA_status"], 1);
        assert_eq!(value["scope"], "demo");
        state.reset();
        assert_eq!(
            state
                .execute(&SettingsCommand::GetAccountSettings, &session, true)
                .await
                .unwrap()["settings"]["setting_2FA_status"],
            0
        );
    }
}
