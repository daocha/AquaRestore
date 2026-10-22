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

## CI and releases

- CI fetches `core/` with the `CORE_DEPLOY_KEY` secret; rotate it with `scripts/setup-core-deploy-key.sh`.
  Keep the workflows on `pull_request`, never `pull_request_target`, so pull requests from forks
  cannot reach that secret.
- Releases come from `scripts/release-github.sh` (see `docs/RELEASING.md`). Release builds refuse the
  stub and any core commit that is modified, unrecorded or not pushed.
