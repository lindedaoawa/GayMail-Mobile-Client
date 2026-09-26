import Foundation

/// 对应 Android 端 `org.mort.gaymail.api.ApiException`
enum ApiError: LocalizedError, Equatable {
    case http(code: Int, message: String, needCaptcha: Bool)
    case transport(message: String)
    case decoding(message: String)

    var errorDescription: String? {
        switch self {
        case let .http(_, message, _): return message
        case let .transport(message): return message
        case let .decoding(message): return message
        }
    }

    var needCaptcha: Bool {
        if case let .http(_, _, needCaptcha) = self { return needCaptcha }
        return false
    }

    /// 复刻 Android 端 `ApiClient.errorOf(code, body)` 的解析逻辑
    static func from(statusCode: Int, body: String) -> ApiError {
        var message = "HTTP \(statusCode)"
        var needCaptcha = false

        if let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? String, !error.isEmpty {
                message = error
            }
            if let flag = object["needCaptcha"] as? Bool {
                needCaptcha = flag
            }
        } else if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = String(body.prefix(200))
        }

        if message.contains("人机验证") {
            needCaptcha = true
        }
        return .http(code: statusCode, message: message, needCaptcha: needCaptcha)
    }
}