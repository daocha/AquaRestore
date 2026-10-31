<img src="AquaRestore-banner.png" >

**English** | [繁體中文](README.zh_TW.md)

# AquaRestore

AquaRestore restores the colors of underwater videos and photos with native Android and iOS apps. All image processing happens on the device.

- **[Android](#android-version):** Kotlin, Jetpack Compose, Media3 and OpenGL ES; Android 10 (API 29) or later.
- **[iOS](#ios-version):** SwiftUI, AVFoundation and Metal; iOS 16 or later.

Android release builds use the network only to check for app updates and download an update when requested. Android debug builds have no network permission unless LAN updates are configured.

## How it works

1. Choose a video or photo from the in-app Recent or Albums library. Android asks for media access when you open the library; on supported versions, you can grant access to selected photos and videos.
2. The app analyzes the colors and recommends red recovery, white balance, exposure, dehaze, clarity and shadow settings.
3. Fine-tune with the **Restore intensity** slider. It scales every advanced setting together: 0% is the original and 100% is the full recommended correction. Hold **Hold to compare** to see the original; release to return. The ⛶ button on the preview opens a full-screen viewer (the same player, so playback continues) with compare still available; tap it again to return. Android also supports the Back button; on iOS, use the on-screen buttons to leave full screen or the editor.
4. The preview stays at the top while the controls scroll independently. For videos:
   - **Video speed:** 0.5×, 1×, 2× or 4×. On iOS, Speed is the only option in the player's settings menu.
   - **Trim:** a filmstrip of graded frames covers the whole clip, with footage outside the selection dimmed and the playhead shown. Dragging a handle pauses the preview on that frame. Tap or drag inside the selection to move the cursor and play from there; **Set start / Set end** above the cursor cut exactly at that frame. Playback loops within the trim, and export and the size estimate use only the trimmed part.
   - **Audio:** set the original sound's volume (0% mutes it) and add background music. The music bar shows the whole song's loudness, with a window as long as the video's output; drag it to choose which part of the song plays, and release to hear it from the trim start. The original sound and music have separate volumes (up to 200%), so you can keep both or play only the music. A song shorter than the video repeats. On iOS, untouched AAC is passed through; speed, volume or music edits, and other source audio formats, are encoded as AAC for MP4 compatibility.
   - **Advanced adjustments:** auto levels, red recovery, protect cool water, warmth, green/magenta tint, exposure, dehaze, clarity, contrast, saturation and shadows.
5. Top bar: **✕** on the left closes the edit and returns to the home screen (after confirming); on the right are change media, export and settings. Export as Recommended, Original or Custom, with preparing / encoding / saving progress and cancellation.
6. In settings, switch between 中文 / English and Light / Dark. Both follow the system by default, and your choice is remembered.

## Smart recommendations and smooth preview

Recommendations come from on-device color statistics, not a cloud-based generative model. For videos, 6 frames spread across 5%–95% of the clip are analyzed together, and one set of parameters is used for the whole video, so the white balance does not pump from frame to frame. The analysis tells deep blue or green water, washed-out hazy water and dim footage apart and recommends settings for each. Low-confidence footage shows a notice and starts at a lower intensity; everything can still be adjusted by hand.

After analysis, videos normally play from the original, with live GPU grading. Exports **always use the original URI**, never a preview copy.

- **Android:** 4K60 can play directly when the device can decode it smoothly. The app makes a 1080p, up to 30fps preview copy when it needs to convert HDR for preview, cannot play the original smoothly, or the video's long edge exceeds 3840px. When the copy is needed for playback, a graded, seekable frame and progress are shown until it is ready.
- **iOS:** there is no preview copy. Heavy footage (such as 4K60) is played directly; smoothness on target devices still needs testing.

Photo previews have a 720px long edge and are graded in the background; each finished preview immediately picks up the latest slider values, so continuous dragging never keeps cancelling work until you let go. Photos and videos use the same grading formula. On compatible devices, HDR video is processed and exported as HDR; otherwise it is tone-mapped and exported as SDR. Devices, encoders and color management may cause slight display differences.

## Export

| Option | Video | Photo |
| --- | --- | --- |
| Recommended | Keeps source dimensions and frame rate when already within the suggested limits; otherwise caps video at 1080p and 30fps with a balanced bitrate | Keeps smaller photos at full size; reduces larger ones. PNG sources stay PNG; other sources become JPEG |
| Original | Keeps the source dimensions, frame timestamps / variable frame rate and codec; uses the source video bitrate (adjusted for speed), estimating it only when unavailable; no silent encoder downgrade | Full size, full-quality JPEG or lossless PNG after correction |
| Custom size | Original, or long edge 3840 / 2560 / 1920 / 1280 / 960 / 640; keeps the aspect ratio, never upscales | Same |
| Custom fps | Original / 24 / 25 / 30 / 50 / 60 (nothing above the source), lowering the average frame rate by dropping frames | Not applicable |
| Quality | Target bitrate, 10–100% | JPEG 10–100%, or lossless PNG |
| Output | MP4; Custom uses H.264 for SDR and 10-bit HEVC for HDR; compatible audio is kept as is | JPEG / PNG |

Color correction requires re-encoding the video, so **Original does not mean bit-for-bit lossless**, and colors that the water absorbed completely cannot be fully recovered. Original keeps frame timestamps; Custom fps is an average close to the target, without motion interpolation or guaranteed fixed frame intervals. If the device's encoder does not support the source codec or size, the export fails clearly; choose Custom H.264 with a smaller size instead.

For Original video, Android keeps the source codec; iOS keeps AVC or HEVC codec families, so choose Custom H.264/HEVC for other codecs. Both platforms derive Original frame timing from the source track.

### Saving and background export

- **Android:** output is saved to `Movies/AquaRestore` or `Pictures/AquaRestore`. It is written to a temporary file first and then published with MediaStore's pending mechanism; failed or cancelled exports clean up their partial files, and the source is never overwritten. Export continues in the background with a notification, using a foreground service and a wake lock. Work does not resume automatically if the system kills the app or the device restarts, and Android's limits on long-running background services still apply.
- **iOS:** output is saved to the Photos library with add-only access; the app never reads your library. This iOS 16+ build pauses export while it is not in the foreground and keeps the screen awake while it runs. iOS 26+ can support continued GPU processing on eligible devices with a Background GPU Access entitlement; that capability is not configured for this build.

### Batch restore photos

Choose **Batch restore photos** on the home screen to restore photos without opening the editor; videos are not accepted. Choose Recommended, Original or Custom export settings once, and each photo receives its own default intelligent restoration automatically. Recommended adapts to each photo's dimensions and format. Batches show an estimated total size, from each photo's resolution, format and quality, and process one photo at a time to limit memory use on midrange phones. Progress and cancellation are available; completed photos are kept if cancelled, and unreadable photos are reported while the remaining photos continue.

- **Android:** up to 100 photos per batch. Hold a photo and drag across others to select or deselect a range; holding near the top or bottom scrolls through more photos. Export continues in the background.
- **iOS:** up to 30 photos per batch, selected in the system picker without hold-and-drag selection. Keep AquaRestore open and do not switch apps or lock the screen, as the batch dialog and progress remind you. Leaving the app pauses the batch until you return.

### Batch restore videos

**Batch restore videos** is experimental and available only with the hidden [developer tools](#developer-tools) turned on. Its button then appears on the home screen below the photo batch. Each video is restored automatically and exported whole with its own audio (no trim, speed or music), one video at a time. Recommended caps output at 1080p and 30 fps. Before starting, the dialog shows the total length, the estimated size and the free space needed. Before each video the export checks free space, and between videos it waits while the phone is severely hot.

- **Android:** up to 20 videos per batch, with background export. A video that this phone can analyze only after decoding it in software is reported as failed; open it in the editor instead.
- **iOS:** up to 5 videos per batch, selected in the system picker. Keep AquaRestore open and do not switch apps or lock the screen, as the batch dialog and progress remind you. Leaving the app pauses the batch until you return.

## Developer tools

On both platforms, tap the version number in Settings ten times to unlock the developer tools: the log viewer, Save logs, Save analysis frames and batch video restoration. They stay on until the next app update, or until switched off in Settings.

- **Android:** saved files go to `Download/AquaRestore-analysis`.
- **iOS:** saved files go to the Files app under On My iPhone › AquaRestore, in `logs` and `frames`.

## Building

The tuned color grading (scene analysis, grading formula and GPU shaders) lives in a private repository, mounted at `core/` as a git submodule. With access, clone with `git clone --recurse-submodules`, or run `git submodule update --init` in an existing clone. Without access, run `scripts/use-core-stub.sh` once: it fills `core/` with the basic grading in `core-stub/`, so the app builds and runs, though its results are noticeably weaker than the released app.

| | Android | iOS |
| --- | --- | --- |
| UI | Jetpack Compose, Material3 1.4, Material Icons, Media3 player controls | SwiftUI, rebuilt to the same specs: the same Material icons (generated from their sources), Material3 1.4 buttons, chips, slider, progress bars, dialogs and type scale, and Media3's styled player controller |
| Font | Roboto | SF Pro; sizes, weights and line heights follow the Material type scale |
| Live preview | ExoPlayer + a GLSL shader | AVPlayer + a Metal compute shader in a custom `AVVideoCompositing` (the same grade as the photo path, to within one level) |
| Export | Media3 Transformer | `AVAssetReader` → the same Metal compositor → `AVAssetWriter` (H.264 / HEVC, bitrate from the same plan as the size estimate) |
| Photos | Decoded with `ImageDecoder`, graded on the CPU | Decoded with ImageIO, graded on the CPU |
| Import | In-app Recent / Albums library with media permission | Photos picker for media, Files for music |
| Output | `Movies/AquaRestore`, `Pictures/AquaRestore` | Photos library (add-only access; the app never reads your library) |

### Android version

The native Android app lives in `android/`.

#### One-step build and release

```bash
./scripts/build-android-debug.sh
```

This produces `dist/AquaRestore-debug.apk` and runs the tests and lint by default. The debug build has its own package name (`com.aquarestore.app.debug`) and is called **AquaRestore Dev**, so it installs next to the release app instead of over it.

The release APK checks the latest published GitHub release quietly on app open (at most once every six hours). When a newer version is available, Settings shows a red dot and an **Update now** button. The downloaded APK is checked against its published SHA-256 and Android asks you to approve installation. Debug builds can check for updates over a configured LAN; without that configuration, they have no updater. A separate `playRelease` variant uses Google Play's in-app updates and has no APK-install permission; see the [release guide](docs/RELEASING.md).

To release:

```bash
./scripts/release-github.sh --version 1.0.0
```

The first release offers to create AquaRestore's own signing key at `~/.aquarestore-signing/aquarestore-release.jks` (alias `release`); back it up with its password right away. Use a key separate from your other apps. To use an existing key instead, set `AQUARESTORE_KEYSTORE` and `AQUARESTORE_KEY_ALIAS`. To let phones running an older build (by default, debug builds) update in place, run `./scripts/rotate-signing-key.sh` once; releases then carry the key-rotation lineage automatically.

Passwords are prompted without echo. The script verifies the signature, commits the version, tags and pushes, and creates a GitHub Release with the APK and SHA256SUMS. The working tree must be clean; `--dry-run` only builds and verifies locally. See the [Android release guide](docs/RELEASING.md) for full setup and options. This release flow covers Android only.

To remove the tools these scripts install on macOS, run `./scripts/uninstall-build-env.sh`; it asks before removing each item.

#### Manual build

Open `android/` in Android Studio with Android SDK 36 and JDK 17. From the command line, set `ANDROID_HOME` or `sdk.dir` in `android/local.properties`, then:

```sh
cd android
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

APK: `android/app/build/outputs/apk/debug/app-debug.apk`. The Gradle Wrapper, pinned dependency versions and a GitHub Actions build are included.

#### Code layout

- `core/android/main`: `AutoGrade.kt` (frame color statistics, scene detection and automatic recommendations), `Grade.kt` (grading formula and intensity scaling) and `GradeShader.kt` (the GPU shader).
- `ExportPlan.kt`: resolution and bitrate policy.
- `UnderwaterEffect.kt`: the single-pass GPU effect and thread-safe parameter snapshots.
- `FrameCadence.kt` / `FrameRateCap.kt`: timeline frame dropping that keeps the target average fps and source timestamps.
- `MediaIO.kt`: media info, sampling, photo decoding, filmstrip and the Media3 Transformer wrapper.
- `Soundtrack.kt`: background music sections, volume processing (up to 200%, clipping rather than wrapping) and the loudness envelope.
- `EditorModel.kt`: import, preview copies when needed, preview and preference state.
- `ExportService.kt`: background export, progress, cancel and MediaStore saving.
- `MainActivity.kt` / `Strings.kt`: Compose UI, Traditional Chinese / English and themes.

### iOS version

`ios/` is a native iOS port that follows the Android app screen for screen: the same home screen, preview with hold-to-compare and full-screen viewer, speed, trim filmstrip, audio and music bar, Restore intensity and advanced sliders, export dialog, settings, strings (中文 / English) and light / dark colors. The grading formula, the automatic recommendations, the export size and bitrate policy and the music window rules are the same code, ported line by line and covered by the same unit tests (`ios/Tests`).

#### Build

Build (needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen); the Xcode project is generated from `ios/project.yml`):

```bash
./scripts/build-ios-debug.sh              # tests + simulator build -> dist/AquaRestore-debug.app
./scripts/build-ios-debug.sh --run        # also installs and launches on the simulator
DEVELOPMENT_TEAM=<team id> ./scripts/build-ios-debug.sh --device
```

As on Android, the debug build has its own bundle id (`com.aquarestore.app.debug`) and is called **AquaRestore Dev**. To work in Xcode, run `cd ios && xcodegen generate` and open `AquaRestore.xcodeproj`. The platform-independent logic builds and tests on its own with `cd ios && swift test`.

#### Code layout

App code lives in `ios/AquaRestore`.

- `Core/`: `ExportPlan.swift` (export sizing and bitrate), `FrameCadence.swift`, `MusicMath.swift`, `Strings.swift`, and `Tuning/` (a link to `core/ios/Core`: `Grade.swift` with the grading formula and intensity, and `AutoGrade.swift`). No UI or AVFoundation, so these are unit-testable anywhere.
- `App/GradeRenderer.swift`: the `AVVideoCompositing` classes and the video composition shared by preview and export; the Metal shader itself is `core/ios/App/GradeShader.swift`.
- `App/MediaIO.swift`, `Soundtrack.swift`, `PlayerController.swift`, `EditorModel.swift`, `Exporter.swift`: the counterparts of the Android files of the same names.
- `App/EditorView.swift`, `PreviewView.swift`, `Panels.swift`, `Timeline.swift`, `Dialogs.swift`: the screens, mirroring `MainActivity.kt`.
- `App/Theme.swift`, `MaterialIcons.swift`, `PlayerControls.swift`, `Logo.swift`: Material3 components, the Material icons (regenerate with `ios/scripts/make-material-icons.py`), the Media3-style player view and the logo art.

See the [validation log](docs/VALIDATION.md#ios) for what has been verified on iOS and what still needs a device.

## Scope and limitations

- SDR, plus HDR10 / PQ and HLG on compatible devices. On Android, keeping HDR needs Android 13+ and a 10-bit HDR encoder that Media3 accepts. On devices without a suitable HDR encoder, HDR video is tone-mapped and exported as SDR. When the device supports HDR export, both Original and Custom preserve it.
- `onFallbackApplied` intercepts Media3's automatic tone-mapping and blocks silent codec / size downgrades. HDR preview brightness depends on the physical display; an emulator cannot replace testing on a real HDR device.
- **HDR10+ metadata:** Android rejects recognizable HDR10+ profiles because dynamic metadata is not preserved; HDR10+ is not always detectable from the track format when the container does not label the dynamic profile. The iOS importer does not currently detect HDR10+ metadata, so an HDR10+ export may lose it. This version does not promise to keep dynamic metadata. Static HDR mastering / content light metadata is not re-measured after grading.
- **Dolby Vision:** Android rejects it at import. On iOS, the compatible profiles that iPhones record are graded from their HLG base layer and exported as plain HLG; profile 5 is rejected. HDR10 / PQ and HLG are graded on the HLG curve exactly as on Android.
- Dehaze is a bounded black-point / contrast correction and clarity a small luma unsharp mask, not depth estimation, spatial descattering or machine-learning denoising.
- Recommendations are based on samples from the whole clip; for clips that combine several scenes, very dark footage or strong colored lights, check the result with the intensity slider. Sampling uses keyframes, so very short clips may sample the same frame more than once.
- Temporary files need extra storage. High-resolution photos are limited by memory; an out-of-memory export reports an error instead of silently downscaling.
- Photo EXIF / GPS / container metadata is not kept; an Original PNG can be much larger than the source JPEG. Source audio is subject to MP4 container compatibility.
- Smoothness depends on the device; dropped frames cannot be ruled out on every older phone. Test on your target phones with `docs/DEVICE_TESTS.md`.

What has been verified so far, and what still needs testing on real devices, is in the [validation log](docs/VALIDATION.md).

HDR capabilities follow [Media3 supported formats](https://developer.android.com/media/media3/transformer/supported-formats). Exact behavior follows the Media3 1.9.3 sources this project pins, and validation on target devices.

## Intensity and video speed

The advanced sliders show the values applied at the current intensity and move with it; manual edits are converted back to base values at the current intensity. The Restore intensity slider ranges from 0% (original colors) to 100% (full recommended correction). Photos and videos follow the same intensity setting.

Videos can play at 0.5×, 1×, 2× or 4×, in both preview and export, with audio keeping its pitch. Importing new media resets to 1×. Speeding up keeps the source frame rate by dropping frames evenly: 60fps at 4× still exports at 60fps (not 240fps). Slow motion cannot invent frames, so 60fps at 0.5× exports at about 30fps. The export dialog's fps, the Custom fps choices and the size estimate follow the same rule. Custom fps drops frames after the speed change and never interpolates. Changing speed re-encodes the audio.

The video export dialog shows an estimated size in MB / GB for the current resolution, fps, quality and speed. The estimate includes audio and a little container overhead; the actual size varies with the encoder and the footage, and it is not a hard limit. Original no longer takes the larger of the source bitrate and the high-quality formula, avoiding needless inflation; the same bitrate still does not make re-encoding lossless.

## License

AquaRestore is licensed under the [PolyForm Strict License 1.0.0](LICENSE). In short:

- **Allowed:** reading the code, and building and using the app for your own personal, non-commercial purposes. Non-commercial organizations (such as charities, schools and public research or government bodies) may also use it.
- **Not allowed:** publishing or distributing the app or its code in any form, including free apps on Google Play, the App Store or any other store, sharing APKs, or any commercial use.
- **Not allowed:** making modified versions or new works based on the code.

The full license text in [LICENSE](LICENSE) is what applies; this summary is for convenience only. For any other use, such as publishing or a commercial agreement, contact [daocha on GitHub](https://github.com/daocha).

**Contributions are not accepted.** Pull requests will be closed without merging. Bug reports and suggestions are welcome as issues.

Third-party libraries used by the app (such as AndroidX Media3 and Jetpack Compose) remain under their own licenses.
