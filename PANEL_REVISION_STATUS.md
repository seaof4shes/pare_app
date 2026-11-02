# Initial-defense comments: implementation and acceptance status

Updated 2 November 2026 for app 1.0.8+2009. Implementation is not the same as completing independent validation.

| Panel comment | Implemented | Evidence and remaining acceptance |
| --- | --- | --- |
| Show SMS detection breakdown and summary; reduce Toyota-survey false alarms | Verdict and severity summary, original message, explanation, rule evidence, model indicator and version. Original explanation saved with each new record. Message now precedes explanation. | Exact provided Toyota survey is Low with bundled SMS model v4; harmful OTP-sharing and prize-payment variants remain flagged in regression tests. Demonstrate real incoming messages and collect a new independently labeled evaluation set. |
| Separate app version/update from SMS and voice models | App and model versions remain independent internally and detection records retain their model metadata. The user update page now displays only the application version, app-update status and Download APK action. Model-only updates do not light the Home badge. Detection changes are shipped in application releases. | Android still requires installation confirmation; there is no silent self-installation. Publishing a correctly signed universal APK and matching cloud version/download metadata remains a release task. Confirm the panel’s intended meaning during the defense rather than claiming they explicitly required this UI. |
| Explain severity: how does a message become High? Is it percentage based? | Low/Medium/High labels, explanations and separate technical model/rule indicators. High is based on harmful-request rules, not a claim that a message is a particular percent fraudulent. | Demonstrate the cases below and document the actual decision policy. Model indicators are not calibrated fraud probabilities. Validate false alarms and missed scams separately. |

## Current SMS decision policy

- High: asking the user to disclose an OTP/password/PIN; credential entry combined with a link, account action or threat; a prize combined with payment; or rule evidence of at least 8 points together with a model indicator of at least 0.5.
- Medium, if no High condition applies: at least 3 rule-evidence points, or a model indicator meeting the installed manifest's caution threshold (approximately 0.60 for bundled v4).
- Low: neither condition applies. Low does not verify the sender or guarantee safety.

Rule evidence is a weighted score, capped at 20 for Medium/High: credential requests add 6; account verification with a link adds 4; account threats with an action/link add 4; urgency accompanying a risky request adds 2; a prize with payment/personal data adds 6; personal/financial information requests add 3; payment with a link adds 3. Overlapping rules can add points. These are not percentages, distinct-word counts or a standalone calibrated confidence measure.

## Final-defense demo sequence

1. Use the configured Firebase test phone and its configured OTP. The MPIN is the app's locally established PIN, not a Firebase console test-code setting. Verify restoration, then reopening with MPIN only. The legacy profile-phone mismatch is covered by a regression test; the live configured test account still needs a user retest.
2. Receive the exact Toyota survey. Open history: Low summary, message before explanation, action on the right, technical details collapsed.
3. Receive an OTP-sharing request and a prize-payment request. Explain the High evidence and show a notification if permission/alerts are enabled.
4. Disable alerts and receive a new risky SMS: save history as Logged Only. Disable Message Detection: no analysis of new SMS. Disable Voice Detection: record/upload controls disable and the setting survives reopening.
5. Show the app-only Updates page: installed application version, available version when published, and Download APK. Explain that the download opens outside the app and Android requires confirmation. Explain model-version separation using detection technical details and implementation records, not user-facing model installation controls.
6. Background the app and repeat the SMS test. Android scheduling/battery restrictions and force-stop remain limitations; the headless-worker test does not replace carrier/device acceptance testing.

## Additional release gates

History records actions rather than inferring them from risk: Logged Only, Alert Shown after a notification is posted, or Messages opened after the Android conversation opens successfully. Opening Messages does not confirm that the sender was blocked. Legacy unverified blocking labels are explicitly marked unverified; missing severity remains Unknown. The message appears before the explanation, and the high-risk button reads “Open Messages to block.” Startup shows the branded splash briefly before onboarding or login.

Live cloud-rule deployment, production signing, independently reviewed SMS/voice evaluation, real OTP and message-delivery checks remain. Development evaluation figures and remaining limitations are in DEFENSE_READINESS.md and SECURITY_REVIEW.md. Do not describe the app as fully validated or production-ready until those gates are complete.
