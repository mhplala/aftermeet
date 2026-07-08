import Foundation
import Security

/// AI 后端配置：内置服务（默认，设备额度零配置）或 BYOK（任意 OpenAI 兼容端点）。
/// API Key 存系统钥匙串，Base URL / 模型名存 UserDefaults。
enum AIBackend {
    static let modeKey = "aiMode"          // "builtin" | "byok"
    static let urlKey = "aiBaseURL"
    static let modelKey = "aiModel"

    static var isBYOK: Bool {
        UserDefaults.standard.string(forKey: modeKey) == "byok"
            && !baseURL.isEmpty && apiKey?.isEmpty == false
    }
    static var baseURL: String {
        (UserDefaults.standard.string(forKey: urlKey) ?? "")
            .trimmingCharacters(in: .whitespaces)
    }
    static var model: String {
        (UserDefaults.standard.string(forKey: modelKey) ?? "")
            .trimmingCharacters(in: .whitespaces)
    }
    /// 归一化：去掉尾部斜杠，补 /chat/completions
    static var chatURL: String {
        var base = baseURL
        while base.hasSuffix("/") { base.removeLast() }
        return base + "/chat/completions"
    }

    // MARK: - Keychain（generic password）

    private static let service = "app.siku.aftermeet"
    private static let account = "byok-api-key"

    static var apiKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !trimmed.isEmpty else { return true }   // 清空 = 删除
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// 连通性测试：发一条最小 completion，返回错误描述（nil = 成功）。
    static func test() async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            do {
                let reply = try Refine.chatOnce(system: "你是连通性测试。", user: "回复：OK", maxTokens: 8)
                return reply.isEmpty ? "服务返回为空" : nil
            } catch {
                return (error as NSError).localizedDescription
            }
        }.value
    }
}
