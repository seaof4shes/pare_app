# P.A.R.E. revision and verification notes

## Latest UI revision: app 1.0.6+7

- Branded splash remains visible for approximately 1.1 seconds while protected preferences load, then routes to onboarding or login. It does not add a delay after MPIN entry.
- History shows recorded actions and explicit Unknown severity when old records lack evidence. Opening Messages is not represented as confirmed blocking. Clearing history only clears this account's app records on this phone.
- Update cards separate application, Message protection, and Voice checks; version numbers are available under collapsed Version details. Missing update metadata is shown as unavailable, not up to date.
- A native Wi-Fi status stream triggers throttled update checks while the main app is open. Defense distribution is by APK, so installation still requires opening the installer and approving Android's prompt; no silent installation or automatic download is promised.
- All 47 unit/widget tests passed and static analysis reported no issues for this revision. Live published-package installation and the configured Firebase test account remain acceptance checks.
- The connected Samsung device passed both integration checks: native Wi-Fi status delivery and headless SMS classification/encrypted history storage. These checks do not establish automatic APK installation or accuracy across all real messages.

## Implemented in app 1.0.3+4

- SMS model v4 bundles its vocabulary and preprocessing metadata. Legacy v1-v3 downloaded SMS models no longer override this bundle.
- Training normalizes and deduplicates messages before splitting, removes 83 conflicting normalized groups, and fits vocabulary on training data only. Twelve authored routine-service examples supplement training; they are not independent evaluation evidence.
- The classifier uses normalized TF-IDF features and logistic regression exported as an int32 `[1,200]` TensorFlow Lite graph. Long messages are truncated to 200 tokens for the model; contextual rules inspect the entire message.
- High risk requires harmful-request evidence. Model-only warnings become Medium, avoiding the previous rule that silently returned Low for every unrecognized scam pattern. Low does not authenticate a sender.
- History saves the original explanation, raw model indicator and model version. Older history remains unchanged and explicitly lacks a breakdown. SMS severity replaces the misleading adjusted confidence percentage.
- SMS update packages require a model, matching vocabulary, and manifest with hashes, version, preprocessing and threshold. Validation and a sample inference occur before a single active-package pointer is committed. Failure retains the previous working package. Other service instances reload on the next prediction.
- Voice updates validate tensor shape/type and inference before activation; missing/corrupt downloaded models fall back to bundled v4. Silence uses waveform RMS, and analysis no longer deletes the caller's source WAV file.
- SMS multipart bodies remain joined. Missing contacts permission no longer breaks receipt. An encrypted Android queue retains up to 100 pending messages when the Flutter listener is absent; saved delivery IDs prevent repeated history entries. Queued messages are associated with the signed-in owner, and disabled protection does not collect new messages.
- App and model versioning remain independent. Application update opens the administrator's HTTPS installer URL rather than presenting a permanently disabled button.
- Verified returning accounts unlock with MPIN; fresh installations and explicit logout require OTP. Android now schedules a headless SMS worker so analysis does not depend on the Home screen. See SECURITY_REVIEW.md for encrypted storage, background limits and security verification.

## Reproducible local evidence

Run from the workspace root:

```
python sms_model_files/train_release.py
python sms_model_files/evaluate_release.py
```

The trainer writes a candidate under `sms_model_files/release_v4`; it does not publish it. The approved candidate must be copied together with its vocabulary and manifest into app assets. The Python evaluator requires TensorFlow; Windows cannot currently allocate the voice model's Flex operation and records that limitation.

From `pare_app`:

```
flutter test test
flutter analyze --no-pub
flutter test integration_test/model_smoke_test.dart -d DEVICE_ID
flutter build apk --debug
```

The release evaluation test uses the adjacent `sms_model_files/release_v4` evaluation files. Keep both workspace folders together when reproducing the results. Device integration tests temporarily replace the app UI; restore the regular app afterward.

On 1,836 development evaluation messages, the final hybrid system flagged 471 of 576 positive-labeled messages and 39 of 1,260 negative-labeled messages. It missed 105 positive-labeled messages. Accuracy: 92.16%; precision: 92.35%; recall: 81.77%; F1: 86.74%. Medium and High both count as flagged. The source mixes spam/promotions and scams, so these figures must not be presented as independently measured real-world scam accuracy. Model design was iterated during development; use a new independently reviewed set for final acceptance.

The exact Toyota survey produces a model indicator of approximately 0.2755 and Low risk. The appointment reminder produces approximately 0.2826 and Low risk. A request to send an OTP is High because of contextual evidence despite a low model indicator. Numerical output is not a calibrated fraud probability.

## Publishing update metadata

No cloud files or Firestore documents were changed by this revision.

For a future SMS version N, upload these three matching files:

- `updates/models/sms_scam_model_vN.tflite`
- `updates/models/sms_scam_model_vN_vocab.json`
- `updates/models/sms_scam_model_vN_manifest.json`

The manifest must contain `version`, `sequenceLength: 200`, `preprocessing: ascii_url_number_v1`, `cautionThreshold`, `modelSha256` and `vocabSha256`. Publish the matching version in `app_updates/latest` only after device testing. Do not advertise unchanged binaries as improved models. Old standalone model downloads will be rejected by the new package contract.

Application metadata uses `appVersion`, `appVersionCode`, and `appDownloadUrl` (HTTPS). SMS uses `smsModelVersion`; voice uses `voiceModelVersion`. Voice updates must preserve `[1,40,157,2]` float input and `[1,1]` float output, with the same feature extraction and label meaning. Tensor checks cannot prove training/preprocessing equivalence.

## Required physical-phone acceptance checks

Completed locally: 38 unit/widget tests across the regression and background-policy suites; Flutter analyzer with no issues; successful debug APK build; Samsung SM A055F tests covering SMS inference, Android voice Flex loading/inference, encrypted history/profile migration, and a headless SMS job with the activity backgrounded. These checks do not replace real incoming-message, OTP and update-failure acceptance tests below.

1. Install over the previous app without clearing data. Confirm old history remains and new records contain explanations and SMS model v4.
2. Send the exact Toyota SMS, an appointment reminder and an OTP notice: Low, with no warning notification. Send OTP-sharing and prize-payment requests: High, with a warning. Send an unfamiliar model-positive promotional message: potentially Medium, not a claim of confirmed fraud.
3. Check that a long multipart message appears once, in full. Reopen the app and confirm queued/replayed events do not add duplicate history.
4. Disable alerts: risky messages are logged without a notification. Disable message detection/protection: new SMS messages are not analyzed or queued.
5. Test with contacts permission denied, notification permission denied, offline mode, app backgrounded, and app restarted. No crash or fabricated Safe result should occur on analysis failure.
6. Sign in and enable SMS protection. Background or swipe away the app, send a risky SMS, then check for an alert and an encrypted history entry. An Android scheduled job now starts a headless Flutter engine to process queued SMS without opening Home. Test this on each supported device: battery restrictions can delay jobs and Android force-stop prevents normal receipt until the app is reopened. Do not promise uninterrupted immediate alerts.
7. Try a missing, corrupt, mismatched-vocabulary and wrong-shape model update; the previous model should still detect messages. Test a valid newer package and restart to confirm its version persists.
8. Test voice with silence, human recordings, synthetic recordings, noisy audio and unsupported files. Human/synthetic classification does not establish whether a caller is a scammer. Evaluate speaker/source-disjoint recordings before claiming voice accuracy.

## Remaining release gates

- A new independently labeled local SMS evaluation set and adviser-approved false-alarm/missed-scam targets.
- Android voice accuracy evaluation; the device smoke test only validates loading and inference, not discrimination accuracy.
- End-to-end SMS delivery, permission and update failure checks above.
- A real release-signing key and distribution process. The current Android release configuration still uses a debug signing key and must not be treated as a production release.
- Publish approved app/model artifacts and correct backend metadata. This requires actual release destinations and credentials, not fabricated links.

The debug APK is for testing and demonstration, not a declaration of deployment readiness.

## Login and background acceptance for app 1.0.3+4

Use a separate test device for fresh-install testing so existing records are not erased. A fresh install requires OTP; reopening a verified account should show MPIN unlock. Explicit logout should disable SMS collection and require OTP at the next login. Enable protection and notification permission, press Home, and send benign and risky SMS from another phone. Check the alert and history, then repeat with the screen locked, the app swiped away, and after a reboot. Force-stop is a separate Android restriction: reopen the app before expecting receipt again. Check that a backgrounded app returning after two minutes asks for MPIN while queued SMS remain assigned to the same account.
