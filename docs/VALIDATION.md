# 驗證紀錄

本次環境：JDK 17、Android SDK 36、Gradle 8.13；Android 15（API 35）ARM64 模擬器，SwiftShader GPU。

已完成：

- `scripts/build-android-debug.sh` 實際執行成功，產生 `dist/AquaRestore-debug.apk`。
- Android debug／release 編譯成功；debug／release Lint 無阻擋錯誤（仍有依賴更新等警告）。
- 18 項 JVM 單元測試通過：自動推薦、黑畫面不誤判、透明邊緣、異常影格穩健性、強度混合、尺寸與位元率，以及抽幀比例與微秒時間戳邊界。
- 14 項裝置端測試通過：3 項 GPU、8 項媒體／狀態流程、3 項真實 Compose 介面操作。
  - GPU：實際編譯 shader、FP16 HDR 高光保留、即時 uniforms、原色對比與 SDR 零強度。
  - 媒體：圖片 Original PNG、連續匯出、自訂尺寸及 JPEG 畫質差異、EXIF 旋轉、取消及再次匯出、匯入壞檔案後恢復、偏好持久儲存。
  - 影片：640×360／30fps 實際輸出為 320×180／約 24fps，逐一讀取輸出影格時間戳及數量驗證，且存在音軌；帶 90° 旋轉 metadata 的直式影片輸出比例正確。
  - 介面：主滑桿不需捲動即能操作，按住原色對比、鬆開與觸控取消後恢復還原預覽；進階區捲到陰影時預覽仍可見；點擊匯出直到可見的完成提示；中文／深色模式與 Activity 重建。
  - 暫停影片：Activity 重建後保留約 800ms 的位置及暫停狀態；直接比較 SurfaceView 的螢幕像素，確認暫停時調色也會刷新。
- SDR 合成影片實際匯入、自動分析、代理預覽及 Original 匯出成功；ffprobe 確認 1280×720／30fps／H.264，AAC 音訊資料 SHA-256 與來源一致。
- JPEG 實際匯入、預覽與 Original 圖片匯出成功；結果為 1280×720 PNG。
- `scripts/release-github.sh --dry-run` 使用 `/tmp` 臨時 JKS 實際完成簽署；JKS 路徑包含空白，store／key 密碼不同。apksigner、憑證比對、版本與非 debug APK 檢查通過。測試簽署 APK 已移出專案交付目錄，不作為正式版本。
- 6 項發布腳本隔離測試通過，覆蓋版本／tag／提交對應、原子 push、draft 上傳後才公開、dry-run 不寫 GitHub、dirty tree／重複 tag 阻擋、上傳失敗不公開。
- Shell 語法與 `git diff --check` 通過。

未做或仍需真機驗收：

- 未使用正式 JKS，未 push、建立真實 GitHub Release 或上傳資產。發布 orchestration 使用隔離 Git 儲存庫及模擬 gh／push 驗證。
- HDR10／HLG 的完整硬體解碼→10-bit 編碼→實體 HDR 螢幕顯示，須在具 HDR 編碼能力的 Android 13+ 手機驗證。模擬器 GPU 測試不等於 HDR 編碼器驗收。
- 4K60、實際 VFR 檔案、長片音畫同步、低階裝置幀時間、熱節流、其他 EXIF 旋轉／鏡像組合、各廠牌背景服務行為等，依 [真機清單](DEVICE_TESTS.md) 執行。

## 功能審查修正

- 改成依整段時間軸選取影格，修正原抽幀器在 30→24fps 時未達到指定幀率；等幀率亦不會因微秒四捨五入丟幀。
- 調整強度或進階參數時自動離開原色對比，避免誤以為滑桿無效。
- 保留影片位置與播放／暫停意圖，改善畫面重建和背景回前景行為。
- 匯入新素材會回到預覽頂部；匯入錯誤、匯出成功／失敗／取消使用直接可見的對話框，不藏在捲動區末端。
- 匯出在前景服務清理後才回報完成，避免緊接下一次匯出時工作被忽略；最後發布步驟以短交易完成，避免已儲存卻顯示取消。
- 匯出期間禁止更換素材，包含 Activity 重新建立後的空白首頁，避免撤銷正在匯出的來源權限。
- 來源全黑／全透明時不捏造紅色缺失或偏藍判斷；透明邊緣不干擾推薦統計。

重新執行功能回歸測試（需先啟動 Android 模擬器或連接測試裝置）：

```bash
cd android
./gradlew :app:testDebugUnitTest :app:lintDebug :app:connectedDebugAndroidTest
```

`android/app/src/androidTest/assets` 為自行產生的合成測試素材，包含彩色測試片、旋轉 metadata 及 EXIF 圖片，不是實際水下畫質驗收素材。

## 本輪互動改善回歸

- 完整 14 項 Android 測試、16 項 JVM 測試及 debug Lint／APK 編譯通過。
- 200% 強度在 CPU 與 GPU 均會提高實際紅色補償，基礎滑桿數值不被覆寫。
- 合成 2 秒有音軌影片分別以 0.5×、2×、4× Original 匯出，檢查兩軌時長與來源時長／速度相符（容許編碼封包邊界 180ms），且來源尺寸保留。
- 影片預覽 2× 實際播放器參數及 Activity 重建後速度、暫停狀態與位置驗證通過。
- 上述短片驗證不代表長片同步、實際音高聽感、高 fps 真機編碼及橫向／大字體佈局均已驗收。

## Original 位元率與大小預估修正

- Original 優先使用來源影片位元率，不再取高畫質推算值的較大者；影片軌位元率缺失時，由總位元率扣除音訊估算，仍缺資料才使用解析度／fps 公式。
- 變速以速度比例調整 Original 影片位元率，保留每影格的位元預算，避免慢速時無理由加倍大小。
- 預估大小與實際匯出共用設定計算，包含音訊、變速後時長及約 1% 容器開銷；並非硬性檔案大小限制。未知時長顯示無法估算。
- 18 項 JVM 測試通過，包含低於舊推算值／舊最低值的來源位元率、速度、音訊、缺少時長、解析度／fps／畫質對預估大小的影響。
- 不曾取得使用者的 621MB 原片，尚未對該原片核對 codec、位元率或重新匯出大小；不能保證更新後產物剛好等於原始大小。
- 本輪 14 項 Android 裝置測試與 Lint 通過；包含匯出頁 Original／Custom 預估值可見，調低 Quality 後預估大小更新，以及實際影片匯出回歸。6 項發布腳本隔離測試亦通過。

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
