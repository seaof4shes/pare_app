# APK distribution for respondents and evaluators

Logo repair 1.0.13+2014: the current supplied `assets/icon/PARE.png` is the sole full-color artwork for splash, launcher generation and notification large icons. The broken old JPEG splash reference is removed. Adaptive foreground padding is now configured directly as 26% in pubspec.yaml (launcher-icons 0.14.x), so direct regeneration cannot bypass it. The former post-generation XML wrapper is removed. Android's monochrome small notification icon remains a shield/audio mark; full-color notification artwork is decoded once at 128px, and branding failures cannot suppress an alert. Authentication screens stay logo-free.

Branding revision 1.0.12+2013: display name is PARE. The supplied JPEG is stored unchanged at `assets/icon/pare_logo.jpg`, used on the splash and to generate launcher icons. Regenerate icons with `tools/generate_brand_icons.ps1` to preserve the adaptive foreground inset. Android notifications use a separate transparent monochrome vector kept explicitly during resource shrinking. Android application ID, signing identity and account storage keys are unchanged. Login, Signup, Forgot MPIN and OTP remain free of decorative app logos.

This branding build is 87,174,564 bytes (87.17 MB). All 54 tests passed, static analysis is clean, and the universal APK installed and launched on the connected Samsung. Packaged label is PARE; notification/adaptive icon resources survive release shrinking. All three architectures and minimum SDK 26 are retained.

Authentication icon revision 1.0.11+2012: Login, Signup, Forgot MPIN and OTP share outlined 20-pixel functional icons, contrast-aware colors, leading field icons and consistent trailing show/hide MPIN buttons with 48-pixel minimum tap targets and accessible labels. Forgot MPIN's remaining standalone branding is removed. All 54 regression tests passed and static analysis is clean.

UI/explanation revision 1.0.10+2011: removed the standalone branding/shield artwork from Login, Signup and OTP. New SMS records save an evidence-specific headline and a readable breakdown of matched requests, their risks and next steps. The headline appears in History and alerts. Legacy saved explanations remain unchanged. Voice explanations describe model classification and its limits without inventing acoustic evidence. Risk thresholds and scoring are unchanged. All 54 unit/widget tests passed and static analysis reported no issues.

UI revision 1.0.9+2010: the three main navigation screens use the P.A.R.E. header; the deactivated protection card uses the same full-width centered icon/text layout as the activated card. Packaging and detection models are unchanged from 1.0.8.

The primary download is the compressed universal `app-release.apk`. It includes ARM64, 32-bit ARM and x86-64 libraries so users do not have to choose a processor architecture. The current minimum remains API 26 (Android 8.0); this does not guarantee every Android 8.0+ device supports every feature. Test real SMS receipt, background behavior, permissions and audio on representative phones. 32-bit x86 is not included.

Measured 2 November 2026 (decimal MB):

| APK | Download size | Reduction versus previous 345.59 MB universal APK |
| --- | ---: | ---: |
| Universal 1.0.8 (primary download) | 86.50 MB | 75.0% |

Verification: all 48 unit/widget tests passed. The final app-update screen passed its three focused tests, including model-only update suppression and offline version display. Android integration tests passed for native MPIN, real SMS and voice model inference, silence handling, and encrypted storage. Archive inspection confirmed all three architectures, required assets, and no Flex library. See tools/VOICE_BUILTIN_VALIDATION.md for numerical parity evidence. Other device architectures still require physical-device acceptance testing.

Native libraries now use Android Gradle's `jniLibs.useLegacyPackaging = true`. They are compressed inside the APK and extracted by Android during installation. This reduces direct GitHub download size; it does not reduce installed storage by the same amount and may increase total installed storage compared with loading libraries directly from an uncompressed APK. No model or native library was removed for this compression step. See https://docs.flutter.dev/platform-integration/legacy-ffi-plugin#android-apk-size-shared-object-compression.

Build from the project directory:

```powershell
.\tools\build_release_apks.ps1
```

This builds the universal APK with native-library compression. For optional smaller downloads as well, run:

```powershell
.\tools\build_release_apks.ps1 -IncludeArchitectureApks
```

Use the universal APK as the primary GitHub Release asset. Optional architecture-specific APKs require a matching device ABI; users install only one APK:

- `app-arm64-v8a-release.apk`: Android devices supporting ARM64 apps.
- `app-armeabi-v7a-release.apk`: Android devices requiring 32-bit ARM apps.
- `app-x86_64-release.apk`: Android devices/emulators supporting x86-64 apps.

Outputs are in `build/app/outputs/flutter-apk`. The script always rebuilds `app-release.apk`; architecture-specific files are rebuilt only with `-IncludeArchitectureApks`.

## Included features

All three APKs retain the same SMS, voice, authentication, storage, and notification functionality. Splitting changes the packaged native processor libraries, not feature selection. Each APK remains a complete installation, not an Android split-install fragment.

The unused legacy voice models and runtime duplicate of `app_icon.png` are excluded from Flutter's bundled assets. Their source files are retained; the icon source is still used by the launcher-icon generator. The active `voice_model_v6.tflite`, SMS model, vocabulary, manifest, generated Android launcher icons and FFmpeg remain included. V6 re-exports the V4 trained weights with built-in operators, removing the need to ship TensorFlow Lite Flex. Detection remains on-device.

The user update page shows only application information and a Download APK action. Users approve installation through Android. Detection improvements are bundled into future app releases; model versions remain technical metadata rather than separate user update controls. App-only updates drive the Home badge.

Tests, training files, documentation and build caches are not APK contents. Deleting them would not reduce the download size.

## Distribution checks

The current Gradle release configuration uses the debug signing key. These are defense/testing builds, not a completed production signing setup. Configure and securely preserve a release signing key before public distribution; future updates must use a compatible signing identity and a higher version code.

The universal release is now 1.0.8+2009 and can replace the preceding universal build and earlier ARM64 build (internal version code 2007) without uninstalling. Flutter assigns architecture-specific version-code offsets: before moving a user from a per-ABI APK to a universal APK, ensure the universal code exceeds the installed code. Prefer keeping respondents on the universal distribution channel. Old optional APKs must be rebuilt for each release rather than uploaded alongside a newer universal APK as if their versions match.

Package inspection confirms minimum SDK 26 and all three advertised architectures. Other device architectures and Android versions have not been physically tested in this session; a startup check is not an end-to-end SMS/voice test.

Final universal artifact: 86,502,666 bytes (86.50 decimal MB, 82.50 MiB), app 1.0.8+2009. It installed successfully over the integration-test build and cold-launched on the connected Samsung. Final static analysis reported no issues.

Smoke-test the matching APK on the defense device: login, incoming SMS with the app open and backgrounded, voice recording/upload, history and updates. Passing widget tests and successful packaging do not replace these release-device checks. No APK is uploaded automatically by the build script.
