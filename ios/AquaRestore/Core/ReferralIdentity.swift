import Foundation
import CryptoKit

enum ReferralIdentity {
    static func deviceID(package: String, deviceID: String) -> String {
        SHA256.hash(data: Data("referral-v1\n\(package)\n\(deviceID)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
    /// Must match referral_code in the referral server, so a code can be shown before the device registers.
    static func code(deviceID: String) -> String {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var input = Data("referral-code-v2\n".utf8)
        var index = deviceID.startIndex
        while index < deviceID.endIndex {
            let next = deviceID.index(index, offsetBy: 2)
            input.append(UInt8(deviceID[index..<next], radix: 16)!)
            index = next
        }
        var value = SHA256.hash(data: input).prefix(7).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        var result = ""
        repeat { result = String(alphabet[Int(value % 62)]) + result; value /= 62 } while value > 0
        return String(repeating: "0", count: max(0, 10 - result.count)) + result
    }
    /// The code the server issued wins: a device registered before this formula, or a rare collision, has a different one.
    static func ownCode(deviceID: String, issued: String?) -> String { issued ?? code(deviceID: deviceID) }
    /// Whether a friend's code is worth sending: well formed and not this device's own code.
    static func acceptable(_ code: String, ownCode: String) -> Bool {
        code != ownCode && code.range(of: "^[0-9a-zA-Z]{10}$", options: .regularExpression) != nil
    }
    private static let labelledCode = try! NSRegularExpression(pattern: "(?:code|推薦碼)\\s*[:：]\\s*([0-9a-zA-Z]{10})(?![0-9a-zA-Z])", options: .caseInsensitive)
    /// Pasting a whole invite, or the "Your referral code" line, enters just the code.
    static func codeIn(_ entered: String) -> String {
        guard let match = labelledCode.firstMatch(in: entered, range: NSRange(entered.startIndex..., in: entered)),
              let code = Range(match.range(at: 1), in: entered) else { return entered }
        return String(entered[code])
    }
}

enum ReferralInvite {
    /// The numeric Apple ID from App Store Connect. Until the listing exists, invites say to search the App Store.
    static let appStoreID: String? = "6829494205"
    /// The code stays on a line of its own so the recipient can select just the code.
    static func message(_ s: Strings, code: String, appStoreID: String? = appStoreID) -> String {
        let link = appStoreID.map { "https://apps.apple.com/app/id\($0)" }
        return s.text("Try AquaRestore: it brings back the natural colors of underwater photos and videos.\n\n" +
                      "My referral code:\n\(code)\n\nGet the app: \(link ?? "search for AquaRestore on the App Store")\nThen enter the code in Settings → Invite friends.",
                      "試試 AquaRestore：還原水下照片與影片的自然色彩。\n\n" +
                      "我的推薦碼：\n\(code)\n\n下載 App：\(link ?? "在 App Store 搜尋 AquaRestore")\n然後在「設定 → 邀請朋友」輸入推薦碼。")
    }
}
