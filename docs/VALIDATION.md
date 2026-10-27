# Validation record

Environment: JDK 17, Android SDK 36, Gradle 8.13; Android 15 (API 35) ARM64 emulator with the SwiftShader GPU.

Done:

- `scripts/build-android-debug.sh` ran successfully and produced `dist/AquaRestore-debug.apk`.
- Android debug and release builds compile; debug and release Lint report no blocking errors (warnings such as dependency updates remain).
- 18 JVM unit tests pass: automatic recommendation, black frames not misjudged, transparent edges, robustness to unusual frames, intensity blending, size and bitrate, and frame-sampling ratios and microsecond timestamp boundaries.
- 14 on-device tests pass: 3 GPU, 8 media / state flow, 3 real Compose UI interaction tests.
  - GPU: the shader actually compiles, FP16 HDR highlights are kept, live uniforms, original-color compare and SDR at zero intensity.
  - Media: image Original PNG, consecutive exports, custom size and JPEG quality differences, EXIF rotation, cancel and export again, recovery after importing a corrupt file, persisted preferences.
  - Video: a 640×360 / 30 fps clip exports as 320×180 / about 24 fps, verified by reading every output frame's timestamp and count, with an audio track present; a portrait video with 90° rotation metadata exports with the right aspect ratio.
  - UI: the main slider works without scrolling; holding compare shows the original, and releasing or a touch cancel restores the graded preview; the preview stays visible when the advanced section is scrolled to shadows; tapping export through to the visible completion message; Chinese / dark mode and Activity recreation.
  - Paused video: after Activity recreation the position (about 800 ms) and paused state are kept; comparing SurfaceView screen pixels directly confirms that color changes also refresh while paused.
- A synthetic SDR video was imported, analyzed, previewed through the proxy and exported as Original; ffprobe confirms 1280×720 / 30 fps / H.264, and the SHA-256 of the AAC audio data matches the source.
- A JPEG was imported, previewed and exported as Original; the result is a 1280×720 PNG.
- `scripts/release-github.sh --dry-run` completed signing with a temporary JKS under `/tmp`, with a space in the JKS path and different store and key passwords. apksigner, certificate match, version and non-debug APK checks pass. The test-signed APK was moved out of the project's output folder and is not a release.
- 6 isolated release-script tests pass, covering version / tag / commit mapping, atomic push, publishing only after the draft upload, dry-run never writing to GitHub, blocking on a dirty tree or an existing tag, and not publishing after a failed upload.
- Shell syntax and `git diff --check` pass.

Not done, or still needing acceptance on a real device:

- The real JKS was not used; nothing was pushed, no real GitHub Release was created and no assets were uploaded. The release orchestration was verified with an isolated Git repository and mocked gh / push.
- HDR10 / HLG end to end (hardware decode → 10-bit encode → display on a physical HDR screen) must be verified on an Android 13+ phone with an HDR-capable encoder. Emulator GPU tests are not HDR encoder acceptance.
- 4K60, real VFR files, audio/video sync on long clips, frame time on low-end devices, thermal throttling, other EXIF rotation / mirror combinations, and background service behavior across manufacturers: run the [device checklist](DEVICE_TESTS.md).

## Fixes from the feature review

- Frames are now chosen across the whole timeline, fixing the old frame sampler that missed the target rate when going from 30 to 24 fps; equal frame rates no longer drop frames through microsecond rounding.
- Changing intensity or advanced parameters automatically leaves the original-color compare, so the sliders never seem to do nothing.
- The video position and play / pause intent are kept, improving behavior on recreation and when returning from the background.
- Importing new media scrolls back to the top of the preview; import errors and export success / failure / cancel use dialogs that are visible at once, not hidden at the end of the scroll area.
- An export reports completion only after the foreground service has cleaned up, so a following export is not ignored; the final publish step is a short transaction, so a saved file is never shown as cancelled.
- Media cannot be replaced during an export, including from the empty home screen after Activity recreation, so the permission for the source being exported is never revoked.
- All-black or fully transparent sources do not produce made-up missing-red or blue-cast judgements; transparent edges do not affect the recommendation statistics.

To run the feature regression tests again (start an Android emulator or connect a test device first):

```bash
cd android
./gradlew :app:testDebugUnitTest :app:lintDebug :app:connectedDebugAndroidTest
```

`android/app/src/androidTest/assets` holds synthetic test media generated for these tests (color test clips, rotation metadata and EXIF images), not real underwater footage for judging quality.

## Interaction improvements regression

- All 14 Android tests, 16 JVM tests and the debug Lint / APK build pass.
- 200% intensity raises the actual red compensation on both CPU and GPU, without overwriting the base slider values.
- A synthetic 2-second clip with audio was exported as Original at 0.5×, 2× and 4×; both tracks' durations match the source duration and speed (within 180 ms for encoder packet boundaries), and the source size is kept.
- Video preview at 2×: the actual player parameters, and speed, paused state and position after Activity recreation, verified.
- These short-clip checks do not mean that sync on long clips, perceived pitch, high-fps encoding on real devices, or landscape / large-font layouts have been accepted.

## Original bitrate and size estimate fixes

- Original now prefers the source video's bitrate instead of the larger of it and a value derived from high quality; when the video track's bitrate is missing it is estimated as the total bitrate minus audio, and only without that data does it fall back to the resolution / fps formula.
- Speed changes scale the Original video bitrate by the speed ratio, keeping the bit budget per frame, so slow motion no longer doubles the size for no reason.
- The size estimate and the actual export share the same settings calculation, including audio, duration after speed change and about 1% container overhead; it is not a hard file size limit. An unknown duration shows that the size cannot be estimated.
- 18 JVM tests pass, including source bitrates below the old derived value and old minimum, speed, audio, missing duration, and the effect of resolution / fps / quality on the estimate.
- The user's 621 MB source clip was never available, so its codec, bitrate and re-exported size have not been checked; an updated export is not guaranteed to match the original size exactly.
- This round's 14 Android device tests and Lint pass, including the Original / Custom estimates being visible on the export screen, the estimate updating after lowering Quality, and an actual video export regression. The 6 isolated release-script tests also pass.

## iOS

Environment: macOS 27 with the Command Line Tools only. Xcode was not installed, so the iOS app has **not been built as an app, run in the simulator or run on an iPhone**. What was verified instead, on the real code:

- The core logic (`ios/AquaRestore/Core`) was compiled and the 30 ported unit tests in `ios/Tests` were run with a small XCTest stand-in (65,891 checks, no failures): grading, intensity, recommendations for blue, green, hazy and dark water, black and transparent frames, export sizing and bitrate, size estimates, trim, speed, music windows and repetition, frame cadence and volume clipping.
- The Metal shader was compiled on a Mac GPU and compared with the CPU grade (`ColorGrade.pixel`) for nine grades, including intensity 0 and 200%, levels, exposure, shadows, tint, saturation and compare: at most one level of rounding difference. A 90° rotation maps pixels to the right place.
- The export pipeline (`Exporter.exportVideo`) ran on synthetic clips: Original keeps size and frame count and is graded like the CPU path (within YUV round-trip error); Custom with trim, 2× speed, a 160px edge, a 15 fps cap, muted original sound and music at 150% gives the expected duration, size, one audio track and about 15 fps; a rotated source exports upright; cancelling throws `CancellationError`.
- The audio gain stage was checked inside `AVAssetReaderAudioMixOutput`: 50% halves the level, 200% clips at full scale instead of wrapping, 150% music reaches the expected level, muting without music drops the track.
- The live preview (`EditorModel` + `PlayerController`) imported a clip, auto-played it, showed the graded frame, showed the original while comparing, refreshed a paused frame after a slider change, looped inside the trim range and followed the speed.

Not verified, and needing Xcode and a device:

- The whole app (all SwiftUI views included) compiles through SIL against the macOS SDK, with only `@State` swapped for an equivalent property wrapper because its macro plugin ships with Xcode. The UIKit-only code (`Platform.swift`: the player layer and the touch handling) was reviewed by hand. The screens were rendered offscreen on macOS (home, analysis, video and photo editors, every panel expanded, export and settings dialogs, export progress, light and dark) and checked against the Compose layout and the Material3 1.4.0 / Media3 1.9.3 sources; they still need a side-by-side look on an iPhone next to the Android app, including touch behavior (slider, trim bar, music bar, player controls) and animations.
- Photos picker import, saving to the Photos library, the add-only permission prompt, and the iOS build settings generated by XcodeGen.
- HDR (HLG / PQ): the half-float compositing path, the 10-bit HEVC encode and display on an HDR screen. Nothing HDR was run.
- Pausing and resuming an export when the app goes to the background, and playback, trim and export of long, 4K and variable-frame-rate files on real hardware.
