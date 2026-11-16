# Native BA account settings: shipped-request evidence

Date: 2026-11-10. Source: installed Zalo.app static app.asar JavaScript only.
No session, cookies, user database or live traffic was accessed for this work.

Source file: `default-login-main-startup-shared-worker-znotification.4bb5e1e2c2e9bab4f7b3.js`; SHA-256 `32090ad21922a614ad11a12bff9709d269bff273667faa9314d237712abca38e`.

Observed request functions around byte 12404323:
- getSettings: authenticated GET auth `/api/setting/me`, common client params, command 12113.
- setSettings: GET auth `/api/setting/update`, AES session-encoded JSON `params`, command 12033.
- updateTFASettings: GET auth `/api/update/setting/2FA`, getEncodedParams adds IMEI, command 12066.
- getEncodedParams around byte 12395479 serializes JSON, AES-encodes and URL-encodes it.
- TFA manager around byte 5705900 uses updateType=1 to enable, 2 to disable,
  submitOTP=0 initially or 1 plus otp when supplied. OTP must not be logged or persisted.

Privacy config around byte 15822151 whitelists snake_case keys. Settings UI
around byte 7188829 maps birthday 0=hidden,1=full,2=day/month; receive_message
1=everyone,2=friends; accept_stranger_call 2=friends,4=contacted strangers and
friends,3=everyone. Boolean settings use integer 0/1. `setting_2FA_status` is
read-only through the generic setter; it is changed only via the TFA endpoint.

Implementation re-reads effective server settings after mutations. Unknown or
missing settings stay absent, never guessed. Native device privacy guards are
separate from account settings. Validation and DTO filtering are fixture-tested;
no live account-setting or 2FA mutation has been performed by the assistant.
