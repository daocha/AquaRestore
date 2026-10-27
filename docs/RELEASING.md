# Android builds and GitHub releases

## In-app updates

The regular `release` APK install quietly checks the latest public GitHub Release of `daocha/AquaRestore` when it opens (at most once every six hours). It offers an update only when that Release has an APK with a higher version code named `AquaRestore-<version>-<versionCode>.apk` and the matching `AquaRestore-<version>-<versionCode>.SHA256SUMS`. The download is checked for its SHA-256, file size, package name and version code, then handed to Android's install confirmation; the user may need to allow installing apps from AquaRestore. Updates must use a compatible signing key. The `debug` build does not check for updates by default and has no network or APK install permission; it can update over the local network instead, see "LAN updates for the debug build" below.

For Google Play, `:app:bundlePlayRelease` builds the Play AAB. That build uses Google Play in-app updates and has neither the `REQUEST_INSTALL_PACKAGES` permission nor the GitHub APK install flow. Release it with signing compatible with existing installs and an increasing `versionCode`. If a regular `release` build is installed through Google Play, the app also uses Play updates, based on its install source. Test the update flow on a Play testing track first; whether a Play update is available is up to the Play services.

The Android build and release scripts are shared with PassVault (see "Keeping the scripts in sync with PassVault" at the end); there are no iOS steps. Releasing does not require uploading the JKS to GitHub.

## 1. Set up another computer

The tuned color grading core is the private submodule `core/` (`daocha/AquaRestore-Core`); this computer's SSH key must be able to read it:

```bash
git clone --recurse-submodules git@github.com:daocha/AquaRestore.git
```

The build scripts fetch `core/` when it is empty. Release builds refuse the basic grading in `core-stub/`, and require `core/` to have no uncommitted changes, to be at the commit this repository records, and that commit to be pushed to AquaRestore-Core. To change the grading, commit and push in `core/` first, then commit the new `core` pointer here.

You need Bash, JDK 17+, Android SDK 36, Build-Tools 35 / 36 and the GitHub CLI. On macOS run:

```bash
./scripts/setup-release-env.sh
gh auth login
```

This setup script installs missing Homebrew packages, accepts the Android SDK licenses and installs the SDK; it can be run again. On Linux, install these tools yourself. The build scripts support macOS and Linux and detect the tools in the usual locations, or you can set them:

```bash
export JAVA_HOME="/path/to/jdk-17"
export ANDROID_HOME="/path/to/Android/sdk"
```

## 2. One-step debug APK

```bash
./scripts/build-android-debug.sh
```

By default it runs the unit tests and Lint, then writes:

```text
dist/AquaRestore-debug.apk
```

Options:

```bash
./scripts/build-android-debug.sh --install       # also install on the adb device
./scripts/build-android-debug.sh --skip-tests    # skip unit tests; Lint still runs
ANDROID_SERIAL=emulator-5554 ./scripts/build-android-debug.sh --install
```

No release JKS is needed. Even when the shell has signing passwords set, the debug and test Gradle processes never receive them.

### LAN updates for the debug build

Copy `.env.example` to `.env` (it is in `.gitignore`) and fill in this computer's LAN address:

```bash
AQUARESTORE_DEV_UPDATE_HOST=192.168.1.10
AQUARESTORE_DEV_UPDATE_PORT=8765   # optional, default 8765
```

With it set, the debug build:

- Uses the build time (minutes since 2026-01-01) as its version code, so every build is newer than the installed one; the version name carries the same number (for example `2026.10.25-debug.425918`), so builds from the same day can be told apart.
- Allows HTTP to that address only, and gets the network and APK install permissions; without `.env` (for example in CI) nothing changes.
- Writes `android/dist/dev-update/` after `assembleDebug`: the APK, `SHA256SUMS` and `latest.json`.

Then run `scripts/serve-dev-update.sh`, which binds to that address only. The debug build on the phone checks every time it comes to the foreground, or manually from settings.
The address is written only into the debug APK, never into the source or Git; do not distribute a debug APK built with it.
Android accepts only updates signed with the same key as the installed build, so others on the LAN cannot replace it with their own APK.

## 3. Signing key

Default key:

- JKS: `~/.aquarestore-signing/aquarestore-release.jks`
- alias: `release`

When no key is found, the release scripts ask in the terminal whether to create one (PKCS12, RSA 4096, valid for 10000 days; a newly created folder and file are readable only by you). keytool asks for a password and your name / organization details. Back up the key and its password right away in at least two places, one of them offline: every later update to an installed app must be signed with the same key. Do not share the key with another app. The scripts never overwrite an existing key, and without a terminal they stop instead of creating one.

To use an existing key (the path may contain spaces):

```bash
export AQUARESTORE_KEYSTORE="$HOME/path/to/existing-release.jks"
export AQUARESTORE_KEY_ALIAS="your-existing-alias"
```

You can put these two non-secret settings in that computer's `~/.zshrc`. Passwords are typed hidden in the terminal; the key password may differ from the keystore password, and Enter means the same. A secrets manager can also provide them as environment variables:

- `AQUARESTORE_KEYSTORE_PASSWORD`
- `AQUARESTORE_KEY_PASSWORD` (defaults to the keystore password when unset)

Passwords never need to be on the command line, in Gradle properties or in project files. JKS / keystore / p12 files and common signing config files are in `.gitignore`. Release builds use a single-use Gradle process with in-process Kotlin compilation, so no long-lived compile daemon holds the passwords.

`scripts/print-signing-fingerprint.sh [cert.pem]` prints the key's SHA-256 fingerprint (to compare with Play Console's **App integrity** page or to register the package for Android developer verification), and can save the public certificate. It needs only a JDK or openssl, not the Android SDK, and never creates a key.

### Key rotation

If phones have a build signed with another key (the debug key by default), run once:

```bash
./scripts/rotate-signing-key.sh
```

The script builds a lineage with `apksigner rotate` (`~/.aquarestore-signing/lineage.bin`, or `AQUARESTORE_LINEAGE`) proving that the new key succeeds the old one. From then on `build-android-release.sh` attaches the lineage with APK Signature Scheme v3, so old installs update in place and keep their settings. The old key defaults to `~/.android/debug.keystore` (alias `androiddebugkey`); set `OLD_KEYSTORE`, `OLD_KEY_ALIAS` and `OLD_KEYSTORE_PASSWORD` for another one. An existing lineage is not redone; `--force` backs up the old file before replacing it. If only `lineage.bin.bak-*` exists without `lineage.bin`, release builds stop, so a version that cannot update in place is never shipped. Back up the lineage together with the old and new keys.

## 4. One-step signed GitHub Release

First make sure the code is committed, the working tree is clean, and you are logged in to a GitHub account that can publish to the `origin` repository. The JKS is local, and the Git / GitHub credentials must be able to push to `origin`.

```bash
./scripts/release-github.sh --version 1.0.0
```

Without `--version`, an interactive terminal asks for the version; Enter keeps the current one:

```bash
./scripts/release-github.sh
```

In a terminal it asks before publishing, once the build and checks are done; a non-interactive run publishes directly:

1. Checks that tracked files are committed, that `android/`, `core/` and `scripts/` have no untracked files (release notes and the like at the root cannot affect the build and are allowed), and the branch, GitHub login and whether the version tag already exists.
2. A new version name automatically increments `versionCode` and updates `android/app/build.gradle.kts`.
3. Runs the tests and release Lint, and signs the APK with the configured JKS.
4. Verifies the APK signature, that the signing certificate matches the JKS alias, that the application ID and version are right, and that the APK is not debuggable.
5. Writes the APK and its SHA-256 checksum file, and checks that the sources did not change during the build.
6. Commits the version change if there is one, creates the `vX.Y.Z` tag, and pushes the current branch and the tag to `origin` atomically: if the push is rejected, neither is pushed and the local tag is deleted.
7. Creates a draft Release with the APK and SHA256SUMS, and publishes it after the upload succeeds.

Example output:

```text
dist/AquaRestore-1.0.0-1.apk
dist/AquaRestore-1.0.0-1.SHA256SUMS
```

Other options:

```bash
./scripts/release-github.sh --version 1.0.1 --version-code 2
./scripts/release-github.sh --version 1.1.0-beta.1 --prerelease
./scripts/release-github.sh --version 1.0.1 --draft
./scripts/release-github.sh --version 1.0.1 --notes-file /path/to/notes.md
```

`--draft` keeps the GitHub Release unpublished, but still commits the version and pushes the branch and tag. `--skip-tests` skips the tests and release Lint; APK signing and the certificate and version checks still run.

Existing local or remote tags are never overwritten. Releases go to the GitHub repository `origin` points to; the script never creates or switches repositories. Pass `--prerelease` explicitly for pre-release versions.

## 5. Verify signing without releasing

```bash
./scripts/build-android-release.sh
# or check the full release entry point (no GitHub login needed, and the working tree may have changes)
./scripts/release-github.sh --dry-run
```

`--dry-run` still really builds, signs and verifies the APK, but does not commit, tag or push, and never calls GitHub. If a new version was given, the version file changes stay in the working tree for review.

The debug build uses its own package name `com.aquarestore.app.debug` and the app name "AquaRestore Dev", so it installs next to the release build without replacing it. Debug builds installed before this change still use `com.aquarestore.app` and the debug key: uninstall them, or run `scripts/rotate-signing-key.sh` once so the release build updates them in place and keeps their settings. Later releases must keep using the same signing key to update in place.

## 6. Interrupted releases

- Build failure: nothing is pushed; version edits stay in the working tree, and your files are not reverted.
- Git push rejected (for example a protected `main`): neither the branch nor the tag is pushed, the local tag is deleted and the version commit stays local. Merge that commit through a pull request, then run again on the merged branch with the same `--version`; do not change the version number.
- GitHub upload failure: the tag may already be pushed and the Release stays a draft; check with `gh release view vX.Y.Z`, then upload the missing assets.
- Publish failure: the uploaded assets stay in the draft; check it on GitHub and publish it.

## 7. Google Play

The Play build is `playRelease`: the same `com.aquarestore.app` as the GitHub build, but without `REQUEST_INSTALL_PACKAGES` and the GitHub update flow, using Play updates instead. For the GitHub APK and Play installs to update each other in place, the APKs Play delivers must be signed with the same key as the GitHub build, so **before the first upload** choose to upload your own key in Play App Signing. This choice cannot be undone; if Google generates the key, the two builds will always be signed differently and cannot update each other.

### Build

```bash
./scripts/build-android-play.sh
# or together with the GitHub release, so both use the same commit and versionCode:
./scripts/release-github.sh --version 1.0.1 --play
```

- Writes `dist/AquaRestore-<version>-<versionCode>-play.aab`; the AAB is not uploaded to GitHub.
- The AAB and the GitHub APK are signed with **the same key** (the release JKS from section 3), with no separate upload key: the GitHub APK already needs this key on the build computer, so another upload key adds almost no protection. With `--play` the password is asked for only once.
- The script verifies the AAB signature and signing certificate, and uses the APK of the same variant to check the package name, version, that it is not debuggable, and that it lacks `REQUEST_INSTALL_PACKAGES`.
- It also writes `dist/AquaRestore-<version>-<versionCode>-play-mapping.txt` (the R8 mapping); upload it with the AAB so Play Console's crash reports are readable.
- At the end it prints the key's SHA-256 (in Play Console's format) to compare after the first upload.

### First upload

1. Create the app in Play Console and open **Test and release → App integrity → Play app signing**.
2. Choose to use your own key, **Export and upload a key from Java keystore**. Download `pepk.jar` and the encryption public key as shown, and run on the release JKS:

   ```bash
   java -jar pepk.jar --keystore="$HOME/.aquarestore-signing/aquarestore-release.jks" --alias=release \
     --output=encrypted_private_key.zip --include-cert --rsa-aes-encryption --encryption-key-path=encryption_public_key.pem
   ```

   Upload the generated zip, then delete it and `pepk.jar`. Do not register a separate upload key: the AAB is signed with the same key.
3. Upload the AAB to the internal testing track, and the mapping file under **App bundle explorer → Downloads**. Then in **App integrity**, check that the SHA-256 of the "App signing key certificate" matches the output of:

   ```bash
   keytool -list -v -keystore ~/.aquarestore-signing/aquarestore-release.jks -alias release | grep SHA256
   ```

4. Install the Play build from internal testing and check that it updates the GitHub build in place (and the other way round) and keeps the settings.

### Later releases

For every release, run `release-github.sh --play` and upload the AAB and mapping file to Play, so both use the same `versionCode`; Play never offers an update lower than the version on the device. The lineage made by `scripts/rotate-signing-key.sh` is attached only to the GitHub APK, not the Play build: devices that still have a build signed with the old debug key must update once through the GitHub build first.

## Keeping the scripts in sync with PassVault

`_signing-common.sh`, `build-android-debug.sh`, `build-android-release.sh`, `build-android-play.sh`, `release-github.sh`, `rotate-signing-key.sh`, `print-signing-fingerprint.sh` and `tests/test_release_workflow.py` are the same files in AquaRestore and PassVault. Everything project-specific (app name, package name, key defaults, build directories, permissions forbidden in the Play build, release notes, `core/` checks) is in `scripts/release-settings.sh`. Change a shared file in both repositories, and check with:

```bash
for f in _signing-common.sh build-android-debug.sh build-android-release.sh build-android-play.sh \
         release-github.sh rotate-signing-key.sh print-signing-fingerprint.sh tests/test_release_workflow.py; do
  diff -q ~/git/AquaRestore/scripts/$f ~/git/password-vault/scripts/$f
done
```

## Script checks

```bash
bash -n scripts/*.sh
python3 -m unittest discover -s scripts/tests -v
```

The workflow tests run in an isolated temporary Git repository with mocked `gh` and push, and check version increments, tags pointing at the right commit, asset upload order, blocking on a dirty tree or an existing tag, dry-run, and that failures never publish a partial release. The tests never touch the real GitHub.
