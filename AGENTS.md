# Working in this repository

AquaRestore is public. Its tuned color grading is not: it lives in the private
`daocha/AquaRestore-Core`, mounted here as the git submodule `core/`.

## Where code goes

- Grading changes (scene analysis, the grading formula, the GLSL and Metal shaders, their tests) go in
  `core/`. How the tuning works is in `core/TUNING.md`; read it before changing it.
- Never copy tuned code, constants or a description of the method into this repository: no public
  file, comment, commit message, pull request or README.
- `core-stub/` is the public stand-in with the same API and a basic formula. When a core API changes
  (a new `Grade` field, a new shader uniform), update `core-stub/` to match, and keep every uniform in
  use in the stub shaders.

## Changing the core

1. In `core/`: `git switch main && git pull`, make the change, run the tests, commit, and push to
   AquaRestore-Core. Core is private, so it has no branch rules.
2. Here: `git add core` and commit the new pointer on a branch. `main` is protected, so open a pull
   request for every change in this repository.

Order matters: a pointer to a core commit that is not pushed breaks CI and every other clone.
After `git pull`, run `git submodule update`, because pulling does not move `core/`.

## Building and testing

- Android: `./gradlew :app:testDebugUnitTest :app:assembleDebug :app:lintDebug` in `android/`
  (shader tests: `:app:connectedDebugAndroidTest` on a device or emulator).
- iOS: `swift test` in `ios/` (needs Xcode); the app builds with `scripts/build-ios-debug.sh`.
- Script tests: `python3 -m unittest discover -s scripts/tests -v`.
- Without access to the core, `scripts/use-core-stub.sh` fills `core/` with the stub.

## Building the debug APK on the maintainer's Mac

Do not use `scripts/` to build it (`build-android-debug.sh`, `setup-release-env.sh` and the like use
Homebrew and install software). Install nothing: no Homebrew, no system JDK, no Android Studio, nothing
under `~/Library`. Run Gradle directly with a portable toolchain kept in one folder under `/tmp`:

```bash
T=/private/tmp/aquarestore-tools
export JAVA_HOME=$(echo $T/jdk-17*/Contents/Home) ANDROID_HOME=$T/android-sdk GRADLE_USER_HOME=$T/gradle-home
cd android && ./gradlew --console=plain :app:testDebugUnitTest :app:assembleDebug :app:lintDebug
```

`/tmp` is cleared on reboot. If `$T` is missing, recreate it there and nowhere else:
- JDK 17: the Temurin tarball from
  `https://api.adoptium.net/v3/binary/latest/17/ga/mac/aarch64/jdk/hotspot/normal/eclipse`, extracted into `$T`.
- Android SDK: the macOS "command line tools only" zip from developer.android.com/studio, extracted to
  `$ANDROID_HOME/cmdline-tools/latest`, then
  `yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --sdk_root=$ANDROID_HOME --licenses` and
  `sdkmanager --sdk_root=$ANDROID_HOME 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0'`.
- Gradle: the wrapper downloads it into `$GRADLE_USER_HOME` by itself.

Do not set `ANDROID_USER_HOME`: the APK must be signed with `~/.android/debug.keystore`, the key the
phone's installed debug build has. Check that the package is `com.aquarestore.app.debug`
(`$ANDROID_HOME/build-tools/36.0.0/aapt2 dump badging android/app/build/outputs/apk/debug/app-debug.apk`).
Spurious "Unresolved reference" errors for functions in the same package mean a stale build: run `clean`.

After a successful build, copy the APK to `android/dist/AquaRestore-debug.apk`. Then publish it to the phone over
the LAN: when the gitignored `.env` sets `AQUARESTORE_DEV_UPDATE_HOST`, the build has already written
`android/dist/dev-update/`. Run `scripts/serve-dev-update.sh` in the background, since it keeps serving until stopped.
If a server is already running, leave it running: it serves the folder, so the new build is picked up.
Never write the address from `.env` into a committed file, commit message or pull request.

## CI and releases

- CI fetches `core/` with the `CORE_DEPLOY_KEY` secret; rotate it with `scripts/setup-core-deploy-key.sh`.
  Keep the workflows on `pull_request`, never `pull_request_target`, so pull requests from forks
  cannot reach that secret.
- Releases come from `scripts/release-github.sh` (see `docs/RELEASING.md`). Release builds refuse the
  stub and any core commit that is modified, unrecorded or not pushed.
