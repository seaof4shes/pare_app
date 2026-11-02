# Security and UX revision — 31 October 2026

This is a tested development revision, not a security certification or production-release approval.

## Stored data

- History stores sender, message, result, explanation, scores and timestamps together in an authenticated AES-GCM payload. Ordinary history columns contain placeholders. Account lookup uses a keyed digest. IDs, record counts and delivery deduplication identifiers remain visible to someone who can read the database.
- Local usernames, phone numbers, Firebase IDs and MPIN hashes are encrypted. Profile identifiers move from ordinary preferences into platform secure storage. Operational switches and version numbers remain in preferences.
- Encryption uses a random nonce for each write and the existing platform-protected key. Altered ciphertext raises an error instead of appearing as a safe record. Losing the key can make existing records unrecoverable; the app does not silently erase them.
- Database migrations preserve existing rows and use SQLite secure deletion. This does not promise forensic erasure from flash storage, old device backups or external copies.
- MPINs use salted PBKDF2-HMAC-SHA256 with 600,000 iterations. Legacy hashes upgrade after successful verification. The app serializes attempts and retains the three-attempt/five-minute lockout. A six-digit PIN remains low entropy; this is not a replacement for device security.
- Phone verification must match the account. PIN replacement requires recent Firebase authentication. Logout signs out of Firebase, removes the active private profile, disables protection and clears pending notifications/SMS. Saved history stays encrypted for the account's next login.
- Firestore disk caching is disabled; the previous cache is cleared once. Offline profile access uses the protected local database.
- App-generated microphone and converted audio files are removed after analysis. Picker inputs are deleted only if inside the app cache; user-owned source audio is preserved. Process termination during recording can still leave a temporary cache file.
- Android backups and cleartext network traffic are disabled. Android screenshots/recent-app previews are protected with FLAG_SECURE. This also prevents ordinary screenshots for demonstrations. The app requests an MPIN again after two minutes in the background.

## Logic and UX

- Existing SMS explanations and Low/Medium/High policy are preserved. The model output is an indicator, not a measured probability that a sender is fraudulent.
- History keeps sender left and risk right on one line. Verdicts, explanations, expandable message/technical sections and actionable warnings remain in place.
- Medium voice classifications no longer accidentally match the High AI label. Unclassifiable audio is undetermined, not human/safe.
- History distinguishes loading, empty history and unavailable protected data. Notification-denied results are logged without falsely claiming an alert was shown.
- Protection requests permissions for enabled features; contacts and notifications are not mandatory for SMS analysis. SMS processing now uses an Android scheduled job and a headless Flutter engine. The UI explains battery/force-stop limitations and that voice checks require the app to be open.
- Shared theme defaults align colors, input shape, button size and notification styling. Automated widget coverage checks the history details; a complete accessibility/usability study has not been performed.

## Cloud rules — prepared and tested, not deployed

`firestore.rules` restricts profiles to the authenticated owner, validates profile fields and matching phone claims, denies user enumeration and denies client writes to update metadata. `storage.rules` restricts update downloads to authenticated users and denies client uploads. Server/admin SDK access is governed separately by IAM.

The demo emulators passed 14 access-control assertions, including other-account reads, anonymous reads, extra MPIN fields, update-metadata writes and file uploads. These results do not establish the currently deployed project's rules. Audit existing cloud profile fields and administrator publishing access before deploying these files. Firebase download-token URLs, if distributed, must be reviewed separately because they provide bearer-link access.

Test command (Java 21 and Firebase CLI required):

```
firebase emulators:exec --project demo-pare-security --config firebase.security-test.json --only firestore,storage "node tools/security_rules/test.mjs"
```

Install the test dependencies with `npm ci --prefix tools/security_rules` first.

## Verification

- Flutter analyzer: no issues.
- Unit/widget tests: 42 passed across the regression suite, background-policy checks, account-restoration, OTP-resend and Settings/history UI checks, including encryption authentication, random nonces, legacy decryption, private-preference migration, salted MPIN verification, SMS policy, login policy, background account boundaries and history UI.
- Android isolated database migration tests: 2 passed on Samsung SM A055F, covering account boundaries, absent-owner rejection, ciphertext tampering and legacy profile migration.
- Android model/storage smoke test passed, including actual model loading and encrypted existing history/profile rows.
- Android headless SMS integration test passed, including a rerun with the activity moved to the background: Android launched a separate Flutter engine, classified a queued OTP-sharing request as High, stored authenticated ciphertext, honored disabled alerts and deduplicated a replay. Test records were removed and original account preferences restored. This does not replace real carrier SMS, process-death, reboot and OEM battery-restriction acceptance tests.
- Rules tests: 14 passed in demo emulators; no live Firebase rules or documents changed.

## Before implementation/release

Deploy and verify the reviewed backend rules, configure a private release-signing key instead of the current debug signing configuration, and test real OTP/login/logout, permissions, incoming multipart SMS, notifications and failed updates. Validate SMS and voice performance against new independently reviewed samples. Rooted/compromised devices, instrumentation and debug-build access are outside the protection these local controls can guarantee. See DEFENSE_READINESS.md for the detection evidence and remaining acceptance checklist.

## Returning-device and background behavior

- A fresh install or missing local account requires Firebase phone verification. A matching locally cached account and Firebase session uses MPIN only, including after closing/reopening the app. Explicit logout, mismatched Firebase identity and account recovery require OTP again.
- Verified returning users see an MPIN unlock screen with an option to use another account. Screen locking does not sign out or turn off SMS protection.
- The native receiver keeps SMS in an encrypted queue and schedules a persisted Android job. The job starts a headless Flutter engine, runs the same SMS policy as the UI, stores encrypted history and acknowledges saved messages. No SMS content is placed in scheduler extras.
- Both engines reload settings and private account state before processing, before saving and before alerting. Duplicate delivery IDs prevent duplicate history if foreground and background processing overlap. A failure before acknowledgment retains the queued item for retry.
- Android controls scheduling. Delays are possible under battery restrictions, Doze or resource pressure. Force-stop prevents normal background delivery until the user opens the app again. This is not a guarantee of immediate alerts on every Android device.
- Background voice recording is not enabled. The worker does not request OTP, open screens or access the microphone.
- Debug-only integration hooks can queue fixtures; they reject calls in non-debuggable builds.

## App 1.0.4+5 follow-up

Restoration now uses the phone number belonging to the verified Firebase UID rather than a potentially stale or differently formatted Firestore profile field. The reported phone-verification guard failure has a regression test; live configured test-account login still needs user confirmation. OTP cooldown starts only after a successful user-requested resend, and failed resends remain retryable. Voice Detection now persists, immediately updates Home and disables manual voice controls when off. Home reports SMS notification permission and in-app audio results instead of unconditional alerts. History places the message before its explanation and keeps the action label/value on one line. See PANEL_REVISION_STATUS.md for the three panel comments and remaining defense evidence.

## App 1.0.5+6 performance follow-up

Signup no longer hashes/saves the MPIN twice. Android derives PBKDF2-HMAC-SHA256 on a native worker thread with the same 600,000 iterations, salt size and output format; existing hashes remain compatible. An independent known-answer vector and correct/wrong PIN checks passed on Samsung SM A055F. The measured derivation was 5,019 ms in the debug device test, so this is not an instant-login claim and no before/after total-login benchmark was recorded. The portable Dart implementation remains a fallback for missing native bridges. Successful login combines attempt-reset and timestamp writes and avoids rereading the lockout row.

Overlapping update checks share one request. Reading the installed voice version no longer loads and runs the full voice model; runtime loading still validates the model. Voice feature extraction runs in an isolate to keep the UI responsive; a device test passed for silence and a generated audio signal (runtime behavior, not voice classification accuracy). Silence is explicitly unclassified rather than marked safe. Call-stop events no longer release the analysis lock while an analysis is still executing.

The empty splash source was restored with immediate first-launch/onboarding vs returning-login routing, without an artificial timer. Onboarding claims now match actual detection limitations. Firebase OTP delivery and network calls are still subject to network/backend latency.

Final verification for 1.0.5+6: 43 unit/widget tests passed, analyzer reported no issues, two Android MPIN/model tests passed, and the background SMS test passed. The normal app was restored and launched after integration testing. Configured Firebase OTP credentials and carrier SMS still require end-to-end acceptance; the voice checks establish runtime operation, not human/deepfake discrimination accuracy.
