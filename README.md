<img src="AquaRestore-banner.png" >

**English** | [繁體中文](README.zh_TW.md)

# AquaRestore

A native Android app that restores the colors of underwater videos and photos. Kotlin, Jetpack Compose, Media3 and OpenGL ES; Android 10 (API 29) or later. All image processing happens on the device. Release builds use the network only to check for app updates and download an update when requested; debug builds have no network permission.

An iOS version with the same screens, controls and color pipeline lives in [`ios/`](#ios-version): SwiftUI, AVFoundation and Metal; iOS 16 or later.

## How it works

1. Import a video or photo through the system file picker (no access to your whole gallery is needed).
2. The app analyzes the colors and recommends red recovery, white balance, exposure, dehaze, clarity and shadow settings.
3. Fine-tune with the **Restore intensity** slider. It scales every advanced setting together (red recovery, warmth, dehaze, auto levels and so on): 0% is the original, 100% the recommended correction, up to 200%. Hold **Hold to compare** to see the original; release to return. The ⛶ button on the preview opens a full-screen viewer (the same player, so playback continues) with compare still available; tap it again or press Back to return.
4. The preview stays at the top while the controls scroll independently. For videos:
   - **Video speed:** 0.5×, 1×, 2× or 4×.
   - **Trim:** a filmstrip of graded frames covers the whole clip, with footage outside the selection dimmed and the playhead shown. Dragging a handle pauses the preview on that frame. Tap or drag inside the selection to move the cursor and play from there; **Set start / Set end** above the cursor cut exactly at that frame. Playback loops within the trim, and export and the size estimate use only the trimmed part.
   - **Audio:** set the original sound's volume (0% mutes it) and add background music. The music bar shows the whole song's loudness, with a window as long as the video's output; drag it to choose which part of the song plays, and release to hear it from the trim start. The original sound and music have separate volumes (up to 200%), so you can keep both or play only the music. A song shorter than the video repeats.
   - **Advanced adjustments:** auto levels, red recovery, protect cool water, warmth, green/magenta tint, exposure, dehaze, clarity, contrast, saturation and shadows.
5. Top bar: **✕** on the left closes the edit and returns to the home screen (after confirming); on the right are change media, export and settings. Export as Original or Custom, with preparing / encoding / saving progress, cancel, background export and a notification.
6. In settings, switch between 中文 / English and Light / Dark. Both follow the system by default, and your choice is remembered.

## Smart recommendations and smooth preview

Recommendations come from on-device color statistics, not a cloud-based generative model. For videos, 6 frames spread across 5%–95% of the clip are sampled, each scaled to about 192px. Very dark and clipped pixels are excluded; the app measures RGB means, luma and per-channel percentiles, chroma, the share of water-colored pixels, red loss and blue/green cast, and takes the median across frames. It then decides the scene type:

- **Washed-out, hazy water** (low contrast, low chroma and mostly water-colored): an auto levels stretch with one shared white point separates the colors. When the brightest surfaces read warm (sand under an over-warm camera white balance), the black points are set so those surfaces turn neutral; a green reference such as yellow coral is left alone. A measured cool-down and green correction neutralize what remains while keeping the water blue. Dehaze applies in full, exposure is not raised (it would lift the veil again), clarity restores fine detail, and red recovery and shadow lift (which would add red twice) are turned off.
- **Bright water with a strong blue or green cast and lifted shadows:** auto levels can also engage when a usable bright reference and substantial red loss are present. This avoids treating the water's color cast as evidence that the scene already has enough contrast. Deep water without bright detail remains protected.
- **Deep blue or deep green water:** red recovery and white balance as usual. When green outweighs blue, the green is removed instead of warming the scene, which would turn sand yellow.
- **Deep, low-light water:** a stronger shadow lift.

For SDR, the remaining parameters are computed from the result after levels. HDR avoids SDR channel endpoints; flat, milky water or bright cast-heavy water with lifted shadows can instead receive a hue-preserving luminance curve. The recommended water protection softly limits excess red in strongly cool, saturated pixels while leaving muted and warm subjects alone. One set of parameters is used for the whole video, so the white balance does not pump from frame to frame. Low-confidence footage shows a notice and starts at a lower intensity; everything can still be adjusted by hand.

After the analysis, the original video plays immediately, graded live by hardware decoding and a single GPU shader; no re-encode is needed first. Sliders only update shader uniforms and never rebuild the decoder. Trim-bar thumbnails are taken from the original's keyframes in the background. Only footage heavier than 4K30 (e.g. 4K60) also gets a proxy in the background (long edge 1280px, at most about 30fps, 8Mbps; H.264 for SDR, 10-bit HEVC for HDR), and the player switches to it at the same position once it is ready, so mid-range phones do not stutter. Exports **always use the original URI**, never the proxy.

Photo previews have a 720px long edge and are graded in the background; each finished preview immediately picks up the latest slider values, so continuous dragging never keeps cancelling work until you let go. Photos and videos use the same grading formula. The video shader grades directly in Media3's default SDR working space (gamma-encoded BT.709), matching the analysis thumbnails and the photo CPU path. Photos are decoded as sRGB. HDR is processed as FP16 / BT.2020 textures and graded on an HLG curve extended above 1.0, keeping highlights up to about 10,000 nits; Media3 encodes the output with the source's PQ / HLG curve. HLG is SDR-compatible (diffuse white near 0.7), so the recommendation behaves the same as on SDR video; grading in PQ, where everyday scene brightness is squeezed into a narrow band, made HDR footage turn red. Devices, encoders and color management may cause slight display differences.

## Export

| Option | Video | Photo |
| --- | --- | --- |
| Original | Keeps the source dimensions, frame timestamps / variable frame rate and codec; uses the source video bitrate (adjusted for speed), estimating it only when unavailable; no silent encoder downgrade | Full size, lossless PNG after correction |
| Custom size | Original, or long edge 3840 / 2560 / 1920 / 1280 / 960 / 640; keeps the aspect ratio, never upscales | Same |
| Custom fps | Original / 24 / 25 / 30 / 50 / 60 (nothing above the source), lowering the average frame rate by dropping frames | Not applicable |
| Quality | Target bitrate, 10–100% | JPEG 10–100%, or lossless PNG |
| Output | MP4; Custom uses H.264 for SDR and 10-bit HEVC for HDR; compatible audio is kept as is | JPEG / PNG |

Color correction requires re-encoding the video, so **Original does not mean bit-for-bit lossless**, and colors that the water absorbed completely cannot be fully recovered. Original keeps frame timestamps; Custom fps is an average close to the target, without motion interpolation or guaranteed fixed frame intervals. If the device's encoder does not support the source codec or size, the export fails clearly; choose Custom H.264 with a smaller size instead.

Output is saved to `Movies/AquaRestore` or `Pictures/AquaRestore`. It is written to a temporary file first and then published with MediaStore's pending mechanism; failed or cancelled exports clean up their partial files, and the source is never overwritten.

## One-step build and release

```bash
./scripts/build-android-debug.sh
```

This produces `dist/AquaRestore-debug.apk` and runs the tests and lint by default. The debug build has its own package name (`com.aquarestore.app.debug`) and is called **AquaRestore Dev**, so it installs next to the release app instead of over it.

The release APK checks the latest published GitHub release quietly on app open (at most once every six hours). When a newer version is available, Settings shows a red dot and an **Update now** button. The downloaded APK is checked against its published SHA-256 and Android asks you to approve installation. The debug app has no updater. A separate `playRelease` variant uses Google Play's in-app updates and has no APK-install permission; see the [release guide](docs/RELEASING.md).

To release:

```bash
./scripts/release-github.sh --version 1.0.0
```

The first release offers to create AquaRestore's own signing key at `~/.aquarestore-signing/aquarestore-release.jks` (alias `release`); back it up with its password right away. Use a key separate from your other apps. To use an existing key instead, set `AQUARESTORE_KEYSTORE` and `AQUARESTORE_KEY_ALIAS`. To let phones running an older build (by default, debug builds) update in place, run `./scripts/rotate-signing-key.sh` once; releases then carry the key-rotation lineage automatically.

Passwords are prompted without echo. The script verifies the signature, commits the version, tags and pushes, and creates a GitHub Release with the APK and SHA256SUMS. The working tree must be clean; `--dry-run` only builds and verifies locally. See the [Android release guide](docs/RELEASING.md) for full setup and options. This release flow covers Android only.

To remove the tools these scripts install on macOS, run `./scripts/uninstall-build-env.sh`; it asks before removing each item.

## Building

The tuned color grading (scene analysis, grading formula and GPU shaders) lives in a private repository, mounted at `core/` as a git submodule. With access, clone with `git clone --recurse-submodules`, or run `git submodule update --init` in an existing clone. Without access, run `scripts/use-core-stub.sh` once: it fills `core/` with the basic grading in `core-stub/`, so the app builds and runs, though its results are noticeably weaker than the released app.

Open `android/` in Android Studio with Android SDK 36 and JDK 17. From the command line, set `ANDROID_HOME` or `sdk.dir` in `android/local.properties`, then:

```sh
cd android
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

APK: `android/app/build/outputs/apk/debug/app-debug.apk`. The Gradle Wrapper, pinned dependency versions and a GitHub Actions build are included.

## iOS version

`ios/` is a native iOS port that follows the Android app screen for screen: the same home screen, preview with hold-to-compare and full-screen viewer, speed, trim filmstrip, audio and music bar, Restore intensity and advanced sliders, export dialog, settings, strings (中文 / English) and light / dark colors. The grading formula, the automatic recommendations, the export size and bitrate policy and the music window rules are the same code, ported line by line and covered by the same unit tests (`ios/Tests`).

| | Android | iOS |
| --- | --- | --- |
| UI | Jetpack Compose, Material3 1.4, Material Icons, Media3 player controls | SwiftUI, rebuilt to the same specs: the same Material icons (generated from their sources), Material3 1.4 buttons, chips, slider, progress bars, dialogs and type scale, and Media3's styled player controller |
| Live preview | ExoPlayer + a GLSL shader | AVPlayer + a Metal compute shader in a custom `AVVideoCompositing` (the same grade as the photo path, to within one level) |
| Export | Media3 Transformer | `AVAssetReader` → the same Metal compositor → `AVAssetWriter` (H.264 / HEVC, bitrate from the same plan as the size estimate) |
| Photos | Decoded with `ImageDecoder`, graded on the CPU | Decoded with ImageIO, graded on the CPU |
| Import | System file picker | Photos picker for media, Files for music |
| Output | `Movies/AquaRestore`, `Pictures/AquaRestore` | Photos library (add-only access; the app never reads your library) |

Differences that come from the platform:

- **Background export:** this iOS 16+ build pauses export while it is not in the foreground and keeps the screen awake while it runs. iOS 26+ can support continued GPU processing on eligible devices with a Background GPU Access entitlement; that capability is not configured for this build.
- **No preview proxy.** Heavy footage (such as 4K60) is played directly; smoothness on target devices still needs testing.
- **Audio:** untouched AAC is passed through on iOS; speed, volume or music edits are encoded as AAC. Other source audio is also encoded as AAC for MP4 compatibility.
- **Original video codec:** iOS Original keeps AVC or HEVC codec families; for other codecs, choose Custom H.264/HEVC. Both platforms derive Original frame timing from the source track.
- **HDR10+ metadata:** Android rejects recognizable HDR10+ profiles because dynamic metadata is not preserved. The iOS importer does not currently detect HDR10+ metadata, so an HDR10+ export may lose it.
- **Dolby Vision:** the compatible profiles that iPhones record are graded from their HLG base layer and exported as plain HLG; profile 5 is rejected. HDR10 / PQ and HLG are graded on the HLG curve exactly as on Android.
- The system font is SF Pro instead of Roboto; sizes, weights and line heights follow the Material type scale. iOS has no Back button, so full screen and the editor are left with their on-screen buttons.
- The player's settings menu offers Speed only.

Build (needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen); the Xcode project is generated from `ios/project.yml`):

```bash
./scripts/build-ios-debug.sh              # tests + simulator build -> dist/AquaRestore-debug.app
./scripts/build-ios-debug.sh --run        # also installs and launches on the simulator
DEVELOPMENT_TEAM=<team id> ./scripts/build-ios-debug.sh --device
```

As on Android, the debug build has its own bundle id (`com.aquarestore.app.debug`) and is called **AquaRestore Dev**. To work in Xcode, run `cd ios && xcodegen generate` and open `AquaRestore.xcodeproj`. The platform-independent logic builds and tests on its own with `cd ios && swift test`.

iOS code layout (`ios/AquaRestore`):

- `Core/`: `ExportPlan.swift` (export sizing and bitrate), `FrameCadence.swift`, `MusicMath.swift`, `Strings.swift`, and `Tuning/` (a link to `core/ios/Core`: `Grade.swift` with the grading formula and intensity, and `AutoGrade.swift`). No UI or AVFoundation, so these are unit-testable anywhere.
- `App/GradeRenderer.swift`: the `AVVideoCompositing` classes and the video composition shared by preview and export; the Metal shader itself is `core/ios/App/GradeShader.swift`.
- `App/MediaIO.swift`, `Soundtrack.swift`, `PlayerController.swift`, `EditorModel.swift`, `Exporter.swift`: the counterparts of the Android files of the same names.
- `App/EditorView.swift`, `PreviewView.swift`, `Panels.swift`, `Timeline.swift`, `Dialogs.swift`: the screens, mirroring `MainActivity.kt`.
- `App/Theme.swift`, `MaterialIcons.swift`, `PlayerControls.swift`, `Logo.swift`: Material3 components, the Material icons (regenerate with `ios/scripts/make-material-icons.py`), the Media3-style player view and the logo art.

See the [validation log](docs/VALIDATION.md#ios) for what has been verified on iOS and what still needs a device.

## Scope and limitations

- SDR, plus HDR10 / PQ and HLG on compatible devices. Keeping HDR needs Android 13+ and a 10-bit HDR encoder that Media3 accepts; the HEVC HDR encoder is checked at import, and the source codec again for Original export. Both Original and Custom keep HDR; there is no automatic SDR downgrade.
- `onFallbackApplied` intercepts Media3's automatic tone-mapping and blocks silent codec / size downgrades. HDR preview brightness depends on the physical display; an emulator cannot replace testing on a real HDR device.
- Dolby Vision and recognizable HDR10+ dynamic metadata are not fully preserved yet and are rejected at import. HDR10+ is not always detectable from the track format when the container does not label the dynamic profile; this version does not promise to keep dynamic metadata. Static HDR mastering / content light metadata is not re-measured after grading.
- Dehaze is a bounded black-point / contrast correction and clarity a small luma unsharp mask, not depth estimation, spatial descattering or machine-learning denoising.
- Recommendations are based on samples from the whole clip; for clips that combine several scenes, very dark footage or strong colored lights, check the result with the intensity slider. Sampling uses keyframes, so very short clips may sample the same frame more than once.
- Temporary files need extra storage. High-resolution photos are limited by memory; when there is not enough, the app asks for a smaller size instead of silently downscaling.
- Photo EXIF / GPS / container metadata is not kept; an Original PNG can be much larger than the source JPEG. Source audio is subject to MP4 container compatibility.
- Background export uses a foreground service and a wake lock; work does not resume automatically if the system kills the app or the device restarts. Android's limits on long-running background services still apply.
- Smoothness depends on the device; dropped frames cannot be ruled out on every older phone. Test on your target phones with `docs/DEVICE_TESTS.md`.

What has been verified so far, and what still needs testing on real devices, is in the [validation log](docs/VALIDATION.md).

## Code layout

- `core/android/main`: `AutoGrade.kt` (frame color statistics, scene detection and automatic recommendations), `Grade.kt` (grading formula and intensity scaling) and `GradeShader.kt` (the GPU shader).
- `ExportPlan.kt`: resolution and bitrate policy.
- `UnderwaterEffect.kt`: the single-pass GPU effect and thread-safe parameter snapshots.
- `FrameCadence.kt` / `FrameRateCap.kt`: timeline frame dropping that keeps the target average fps and source timestamps.
- `MediaIO.kt`: media info, sampling, photo decoding, filmstrip and the Media3 Transformer wrapper.
- `Soundtrack.kt`: background music sections, volume processing (up to 200%, clipping rather than wrapping) and the loudness envelope.
- `EditorModel.kt`: import, background proxy (heavy footage only), preview and preference state.
- `ExportService.kt`: background export, progress, cancel and MediaStore saving.
- `MainActivity.kt` / `Strings.kt`: Compose UI, Traditional Chinese / English and themes.

HDR capabilities follow [Media3 supported formats](https://developer.android.com/media/media3/transformer/supported-formats). Exact behavior follows the Media3 1.9.3 sources this project pins, and validation on target devices.

### Intensity and video speed

The advanced sliders show the values applied at the current intensity and move with it; manual edits are converted back to base values at the current intensity. 0–200% scales every correction parameter together (including auto levels), and 0% is a pixel-exact original; the photo CPU path and the video GPU path follow the same rules. SDR levels use thumbnail channel endpoints. HDR levels use a luminance-only curve for flat milky water and selectively for bright cast-heavy water with lifted shadows; dark water without a bright reference and neutral scenes leave it at zero. Recommendations start at a conservative 85%, lower for low-confidence footage, and can be raised to 200%.

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
