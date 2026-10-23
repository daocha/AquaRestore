# Android 建置與 GitHub 發布

## 應用程式內更新

一般 `release` APK 安裝版會在開啟時靜默查詢 `daocha/AquaRestore` 最新公開 GitHub Release（每六小時最多一次）。僅在該 Release 含版本碼更高、名稱符合 `AquaRestore-<version>-<versionCode>.apk` 的 APK，以及對應的 `AquaRestore-<version>-<versionCode>.SHA256SUMS` 時顯示更新。下載時核對 SHA-256、檔案大小、套件名稱及版本碼，最後交由 Android 安裝確認；使用者可能需允許從 AquaRestore 安裝應用程式。升級必須沿用相容的簽署金鑰。`debug` 版預設不檢查更新，也沒有網路與 APK 安裝權限；可改為從區域網路更新，見下方「區域網路更新 debug 版」。

未來上架 Google Play 時，使用 `:app:bundlePlayRelease` 建立 Play 專用 AAB；此版本走 Google Play 應用程式內更新，不含 `REQUEST_INSTALL_PACKAGES` 權限或 GitHub APK 安裝流程。請以與既有安裝相容的簽署方式及遞增的 `versionCode` 發布。若以一般 `release` 版本經 Google Play 安裝，程式也會依安裝來源走 Google Play 更新。請先在 Play 測試軌道測試更新流程；Play 更新是否可用由 Play 服務決定。

腳本參考 `~/git/password-vault/scripts` 的命名與本機簽署方式，僅處理 Android APK，沒有 iOS 步驟。發布時不需要把 JKS 上傳到 GitHub。

## 1. 在另一台電腦準備環境

經過調校的調色核心是私人 submodule `core/`（`daocha/AquaRestore-Core`），這台電腦的 SSH 金鑰需能讀取它：

```bash
git clone --recurse-submodules git@github.com:daocha/AquaRestore.git
```

建置腳本在 `core/` 為空時會自動抓取。發布版本拒絕使用 `core-stub/` 的基本調色，並要求 `core/` 沒有未提交的修改、與本儲存庫記錄的 commit 一致，且該 commit 已推送到 AquaRestore-Core。修改調色時，先在 `core/` 提交並推送，再在本儲存庫提交 `core` 的新指標。

需要 Bash、JDK 17+、Android SDK 36、Build-Tools 35／36，以及 GitHub CLI。macOS 可直接執行：

```bash
./scripts/setup-release-env.sh
gh auth login
```

此準備腳本會安裝缺少的 Homebrew 套件、接受 Android SDK 授權並安裝 SDK；可重複執行。Linux 請自行安裝上述工具。建置腳本支援 macOS／Linux，會從常用路徑偵測工具，也可手動設定：

```bash
export JAVA_HOME="/path/to/jdk-17"
export ANDROID_HOME="/path/to/Android/sdk"
```

## 2. 一鍵 debug APK

```bash
./scripts/build-android-debug.sh
```

預設執行單元測試、Lint，再輸出：

```text
dist/AquaRestore-debug.apk
```

可選項：

```bash
./scripts/build-android-debug.sh --install       # 同時安裝至 adb 裝置
./scripts/build-android-debug.sh --skip-tests    # 省略單元測試，仍執行 Lint
ANDROID_SERIAL=emulator-5554 ./scripts/build-android-debug.sh --install
```

不需要 release JKS。即使 shell 已設定簽署密碼，debug／測試的 Gradle 程序也不會收到它們。

### 區域網路更新 debug 版

將 `.env.example` 複製為 `.env`（已列入 `.gitignore`），填入這台電腦的區域網路位址：

```bash
AQUARESTORE_DEV_UPDATE_HOST=192.168.1.10
AQUARESTORE_DEV_UPDATE_PORT=8765   # 選填，預設 8765
```

設定後，debug 版會：

- 以建置時間（自 2026-01-01 起的分鐘數）作為版本碼，讓每次建置都比已安裝的版本新；版本名稱也帶上此編號（例如 `2026.10.25-debug.425918`），同一天的建置也能分辨。
- 只對該位址允許 HTTP，並取得網路與 APK 安裝權限；沒有 `.env` 時（例如 CI）與以往相同。
- 在 `assembleDebug` 後寫出 `android/dist/dev-update/`：APK、`SHA256SUMS` 與 `latest.json`。

接著執行 `scripts/serve-dev-update.sh`，它只綁定該位址。手機上的 debug 版每次回到前景都會檢查，也可在設定中手動檢查。
位址只寫入 debug APK，不會進入原始碼或 Git；請勿公開散布設定過的 debug APK。
Android 只接受與已安裝版本相同簽署金鑰的更新，因此區域網路上的他人無法以自己的 APK 取代它。

## 3. 簽署金鑰

預設金鑰：

- JKS：`~/.aquarestore-signing/aquarestore-release.jks`
- alias：`release`

找不到金鑰時，release 腳本會在終端詢問是否建立（PKCS12、RSA 4096、有效期 10000 天；新建資料夾與檔案僅本人可讀）。keytool 會要求設定密碼與姓名／組織資料。建立後請立即將金鑰與密碼備份到至少兩處，其中一處離線：已安裝的 App 之後每次更新都必須使用同一把金鑰。請勿與其他 App（例如 PassVault）共用金鑰。腳本永不覆蓋既有金鑰；無終端時不會建立，會直接停止。

若要使用既有金鑰（路徑可以包含空白）：

```bash
export AQUARESTORE_KEYSTORE="$HOME/path/to/existing-release.jks"
export AQUARESTORE_KEY_ALIAS="your-existing-alias"
```

可將這兩個非密碼設定放入該電腦的 `~/.zshrc`。密碼由終端隱藏輸入；key 密碼可與 keystore 密碼不同，直接 Enter 表示相同。也可由秘密管理工具提供環境變數：

- `AQUARESTORE_KEYSTORE_PASSWORD`
- `AQUARESTORE_KEY_PASSWORD`（未設定時預設使用 keystore 密碼）

不需要把密碼放在命令列、Gradle properties 或專案檔案中。JKS／keystore／p12 與常見簽署設定檔已加入 `.gitignore`。Release 使用單次 Gradle 程序與程序內 Kotlin 編譯，不留長時間持有密碼的編譯 daemon。

### 金鑰輪替

若手機已安裝以另一把金鑰簽署的版本（預設為 debug 版），執行一次：

```bash
./scripts/rotate-signing-key.sh
```

腳本以 `apksigner rotate` 建立 lineage（`~/.aquarestore-signing/lineage.bin`，可用 `AQUARESTORE_LINEAGE` 指定），證明新金鑰是舊金鑰的繼任者。之後 `build-android-release.sh` 會自動以 APK Signature Scheme v3 附上 lineage，讓舊版原地升級並保留設定。舊金鑰預設為 `~/.android/debug.keystore`（alias `androiddebugkey`）；其他舊金鑰可設定 `OLD_KEYSTORE`、`OLD_KEY_ALIAS`、`OLD_KEYSTORE_PASSWORD`。已有 lineage 時不會重做；`--force` 會先備份舊檔再取代。若只剩 `lineage.bin.bak-*` 而沒有 `lineage.bin`，release 會停止，避免發出無法升級的版本。請將 lineage 與新舊金鑰一起備份。

## 4. 一鍵簽署並發布 GitHub Release

先確認程式碼已提交、工作目錄乾淨，並已登入有權限發布 `origin` 儲存庫的 GitHub 帳號。JKS 在本機，Git／GitHub 憑證也須能推送 `origin`。

```bash
./scripts/release-github.sh --version 1.0.0
```

不帶 `--version` 時，在互動終端詢問版本，Enter 沿用目前版本：

```bash
./scripts/release-github.sh
```

這個命令會直接完成發布，不再要求額外確認：

1. 檢查乾淨工作目錄、分支、GitHub 登入及版本 tag 是否已存在。
2. 新版本名稱會自動增加 `versionCode`，並更新 `android/app/build.gradle.kts`。
3. 執行測試與 release Lint，以指定 JKS 簽署 APK。
4. 驗證 APK 簽章、簽署憑證與 JKS alias 一致、application ID／版本正確，且不是 debuggable APK。
5. 產生 APK 與 SHA-256 校驗檔；確認建置期間原始碼沒有被修改。
6. 如有版本變更，建立版本提交；建立 `vX.Y.Z` tag，將目前分支與 tag 原子推送到 `origin`。
7. 建立 draft Release，附上 APK 與 SHA256SUMS；上傳成功後轉為正式發布。

輸出範例：

```text
dist/AquaRestore-1.0.0-1.apk
dist/AquaRestore-1.0.0-1.SHA256SUMS
```

其他選項：

```bash
./scripts/release-github.sh --version 1.0.1 --version-code 2
./scripts/release-github.sh --version 1.1.0-beta.1 --prerelease
./scripts/release-github.sh --version 1.0.1 --draft
./scripts/release-github.sh --version 1.0.1 --notes-file /path/to/notes.md
```

`--draft` 保持 GitHub Release 未公開，但仍會提交版本、推送分支與 tag。`--skip-tests` 可跳過測試／release Lint，APK 簽署與憑證／版本驗證仍會執行。

已有的本機／遠端 tag 不會覆寫。發布使用 `origin` 指向的 GitHub 儲存庫，不會自行建立或切換儲存庫。預發布版本請明確帶 `--prerelease`。

## 5. 只驗證簽署，不發布

```bash
./scripts/build-android-release.sh
# 或檢查完整發布入口（不需要 GitHub 登入，也允許工作目錄有變更）
./scripts/release-github.sh --dry-run
```

`--dry-run` 仍會真的建置、簽署及驗證 APK，但不 commit／tag／push，不呼叫 GitHub。若另外指定了新版本，版本檔案的變更會保留在本機供檢查。

Debug 版使用獨立的套件名稱 `com.aquarestore.app.debug`，App 名稱為「AquaRestore Dev」，會與正式版並存安裝，不會互相覆蓋。在這項變更之前安裝的舊 debug 版仍使用 `com.aquarestore.app` 與 debug key：可先移除，或執行一次 `scripts/rotate-signing-key.sh`，讓正式版原地升級並保留設定。後續正式版本需繼續使用同一把簽署 key 才能原地升級。

## 6. 發布中斷

- 建置失敗：不會 push；若有版本編輯，留在工作目錄，不自動回復你的檔案。
- Git push 失敗：本機版本提交與 tag 保留，確認遠端／本機狀態後處理，不要盲目換版號。
- GitHub 上傳失敗：tag 可能已推送，Release 保持 draft；先用 `gh release view vX.Y.Z` 檢查，再補上缺少的資產。
- 發布狀態切換失敗：已上傳的資產留在 draft，可從 GitHub 檢查後發布。

## 腳本驗證

```bash
bash -n scripts/*.sh
python3 -m unittest discover -s scripts/tests -v
```

工作流程測試在隔離的臨時 Git 儲存庫執行，模擬 `gh` 與 push，驗證版本遞增、tag 對應提交、資產上傳順序、dirty tree／既有 tag 攔截、dry-run，以及失敗不公開半成品。測試不會存取真實 GitHub。
