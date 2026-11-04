import SwiftUI

struct BatchQuestDialog: View {
    let video: Bool
    let onUnlocked: () -> Void
    let dismiss: () -> Void
    @Environment(\.strings) private var s
    @Environment(\.palette) private var c
    @ObservedObject private var campaign = ReferralCampaign.shared
    @State private var checking = false
    @State private var error = false
    @State private var invited = false
    var body: some View {
        M3Dialog(title: s.text("Unlock batch processing", "解鎖批次處理"), dismiss: dismiss) {
            VStack(alignment: .leading, spacing: 12) {
                if campaign.active {
                    MText(s.text("Complete the app quest: invite friends to use AquaRestore. They enter your referral code in Settings.",
                                 "完成 App 任務：邀請朋友使用 AquaRestore，並請他們在設定中輸入你的推薦碼。"))
                    MText(s.text("Invite 5 friends → unlock batch photo processing", "邀請 5 位朋友 → 解鎖批次照片處理"))
                    MText(s.text("Invite 10 friends → unlock batch video processing", "邀請 10 位朋友 → 解鎖批次影片處理"))
                    if let code = campaign.code { OwnReferralCode(code: code) { invited = true } }
                    if invited { MText(s.text("Invite copied.", "邀請內容已複製。")) }
                    MText(s.text("Friends invited: \(campaign.count)", "已邀請朋友：\(campaign.count)"))
                    if checking { ProgressView() }
                    if error { MText(s.text("Could not check quest progress. Check your connection and tap the batch button again.",
                                           "無法查詢任務進度。請檢查網路，然後再次點選批次按鈕。"), color: c.error) }
                } else {
                    MText(s.text("This feature is locked. Enter an unlock code in Settings → Developer tools.",
                                 "此功能尚未解鎖。請在「設定 → 開發者工具」中輸入解鎖碼。"))
                }
            }
        } buttons: { M3TextButton(title: s.text("Done", "完成"), action: dismiss) }
        .task {
            let access = BatchAccess.shared
            if video ? access.videoEnabled : access.photoEnabled { onUnlocked(); return }
            guard campaign.active else { return }
            checking = true
            defer { checking = false }
            do {
                try await campaign.request()
                guard !Task.isCancelled else { return }
                if video ? access.videoEnabled : access.photoEnabled { onUnlocked() }
            } catch { if !Task.isCancelled { self.error = true } }
        }
    }
}

/// Monospaced, because codes are read and retyped: this font tells l from I and O from 0.
private struct ReferralCode: View {
    let label: String
    let code: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            MText(label)
            Text(code).font(.system(.body, design: .monospaced).weight(.semibold)).textSelection(.enabled)
        }
    }
}

private struct InviteShare: Identifiable {
    let id = UUID()
    let text: String
}

private struct OwnReferralCode: View {
    let code: String
    let onInvited: () -> Void
    @Environment(\.strings) private var s
    @State private var invite: InviteShare?
    /// Copies first, so the invite is still on the clipboard if the share sheet is dismissed.
    @MainActor private func shareInvite() {
        let text = ReferralInvite.message(s, code: code)
        Platform.copy(text)
        invite = InviteShare(text: text)
        onInvited()
        // A device that was offline at launch must exist on the server before a friend tries this code.
        Task { await ReferralCampaign.shared.registerIfNeeded() }
    }
    var body: some View {
        HStack(spacing: 8) {
            ReferralCode(label: s.text("Your referral code", "你的推薦碼"), code: code)
                .frame(maxWidth: .infinity, alignment: .leading)
            M3Button(title: s.text("Invite", "邀請"), style: .outlined) { shareInvite() }
        }
        .sheet(item: $invite) { ActivityShare(items: [$0.text]) }
    }
}

struct ReferralSettings: View {
    /// The settings dialog shows these in a popup: the submit button can sit at the bottom of the scrolling
    /// settings, with anything below it out of view.
    let onError: (String) -> Void
    @Environment(\.strings) private var s
    @Environment(\.palette) private var c
    @ObservedObject private var campaign = ReferralCampaign.shared
    @State private var code = ""
    @State private var busy = false
    @State private var message: String?
    private var invalidCode: String {
        s.text("This referral code is invalid. Codes are case-sensitive and some characters look alike, such as l and I or O and 0. Paste the code if you can.",
               "此推薦碼無效。推薦碼區分大小寫，部分字元外觀相近（如 l 與 I、O 與 0），建議直接貼上。")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(c.outlineVariant).frame(height: 1)
            MText(s.text("Invite friends", "邀請朋友"), weight: .semibold)
            if let ownCode = campaign.code {
                OwnReferralCode(code: ownCode) { message = s.text("Invite copied.", "邀請內容已複製。") }
            } else { MText(s.text("Device identity unavailable. Try reopening the app.", "無法取得裝置識別碼，請重新開啟 App。")) }
            MText(s.text("Invite 5 friends for batch photos; 10 for batch videos.", "邀請 5 位朋友解鎖批次照片；10 位解鎖批次影片。"))
            if let bound = campaign.referredBy {
                ReferralCode(label: s.text("Friend’s referral code", "朋友的推薦碼"), code: bound)
                MText(s.text("Referral code saved. It cannot be changed.", "推薦碼已儲存，無法變更。"))
            } else {
                TextField(s.text("Friend’s referral code", "朋友的推薦碼"),
                          text: Binding(get: { code }, set: { code = ReferralIdentity.codeIn($0); message = nil }))
                    .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(busy)
                MText(s.text("You can submit a friend’s code only once.", "朋友的推薦碼只能提交一次。"))
                M3Button(title: s.text("Submit referral code", "提交推薦碼"), style: .outlined, spinner: busy) {
                    let entered = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard ReferralIdentity.acceptable(entered, ownCode: campaign.code ?? "") else { onError(invalidCode); return }
                    busy = true; message = nil
                    Task {
                        defer { busy = false }
                        do {
                            let accepted = try await campaign.request(referralCode: entered)
                            code = ""
                            message = accepted ? s.text("Referral code saved.", "推薦碼已儲存。") :
                                s.text("This device already used a referral code. The original code has been restored.", "此裝置已使用推薦碼，已還原原本的推薦碼。")
                        } catch ReferralFailure.api("invalid_referral_code") {
                            onError(invalidCode)
                        } catch {
                            onError(s.text("Could not submit the code. Check your connection and try again.", "無法提交推薦碼。請檢查網路連線後重試。"))
                        }
                    }
                }.disabled(busy || campaign.code == nil || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let message { MText(message, size: 12) }
        }
    }
}
