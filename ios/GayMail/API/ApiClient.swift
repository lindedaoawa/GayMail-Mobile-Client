import Foundation

/// GayMail 服务端 API 客户端。
///
/// 忠实移植自 Android 端 `org.mort.gaymail.api.ApiClient`，
/// 保持相同的接口路径、请求体字段与鉴权方式（`Authorization: Bearer <token>`）。
final class ApiClient {
    static let defaultBaseURL = "https://mail.mort.gay"
    static let hcaptchaSiteKey = "92463c0a-aed2-466e-860e-e17eee882910"

    /// 服务端地址，可由用户在登录页/设置中修改
    var baseURL: String = ApiClient.defaultBaseURL
    /// 登录后获得的服务端令牌
    var token: String?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - 认证

    func login(username: String, password: String, captchaToken: String?) async throws -> UserResult {
        var payload: [String: Any] = ["username": username, "password": password]
        if let captchaToken, !captchaToken.isEmpty {
            payload["hcaptchaToken"] = captchaToken
        }
        let object = try await send(method: "POST", path: "/api/login", payload: payload)
        return try ApiClient.parseUser(object)
    }

    // MARK: - 邮件

    func list(box: MailBox, page: Int, perPage: Int = 50) async throws -> MailPage {
        let path = "/api/mail?box=\(box.rawValue)&page=\(page)&per_page=\(perPage)"
        let object = try await get(path)
        let rawMails = (object["mails"] as? [[String: Any]]) ?? []
        let mails = try rawMails.map { try ApiClient.parseMail($0) }
        return MailPage(
            mails: mails,
            total: object["total"] as? Int ?? mails.count,
            unread: object["unread"] as? Int ?? 0
        )
    }

    func detail(id: Int) async throws -> MailDetail {
        let object = try await get("/api/mail/\(id)")
        guard let mail = object["mail"] as? [String: Any] else {
            throw ApiError.decoding(message: "响应缺少 mail 字段")
        }
        let attachments = ((mail["attachments"] as? [[String: Any]]) ?? []).map { raw -> Attachment in
            Attachment(
                id: raw["id"] as? Int ?? 0,
                filename: raw["filename"] as? String ?? "attachment",
                mimeType: raw["mime_type"] as? String ?? "application/octet-stream",
                size: (raw["size"] as? NSNumber)?.int64Value ?? 0,
                data: raw["data"] as? String ?? ""
            )
        }
        let body = mail["body"] as? String ?? ""
        let html = (mail["html"] as? String) ?? (mail["body_html"] as? String) ?? ""
        return MailDetail(item: try ApiClient.parseMail(mail), body: body, html: html, attachments: attachments)
    }

    func markRead(id: Int) async throws {
        _ = try await send(method: "POST", path: "/api/mail/\(id)/read", payload: [:])
    }

    func delete(id: Int) async throws {
        _ = try await send(method: "DELETE", path: "/api/mail/\(id)", payload: nil)
    }

    func quota() async throws -> Quota {
        let object = try await get("/api/quota")
        let q = object["quota"] as? [String: Any] ?? [:]
        return Quota(
            limit: q["limit"] as? Int ?? 0,
            used: q["used"] as? Int ?? 0,
            remaining: q["remaining"] as? Int ?? 0
        )
    }

    @discardableResult
    func send(
        to: String,
        subject: String,
        body: String,
        html: String = "",
        attachments: [OutAttachment] = [],
        captchaToken: String?
    ) async throws -> [String: Any] {
        var payload: [String: Any] = ["to": to, "subject": subject, "body": body]
        if !html.isEmpty {
            payload["html"] = html
        }
        if let captchaToken, !captchaToken.isEmpty {
            payload["hcaptchaToken"] = captchaToken
        }
        if !attachments.isEmpty {
            payload["attachments"] = attachments.map {
                ["filename": $0.filename, "content": $0.data, "mime_type": $0.mimeType, "size": $0.size] as [String: Any]
            }
        }
        return try await send(method: "POST", path: "/api/send2", payload: payload)
    }

    // MARK: - 解析

    static func parseUser(_ object: [String: Any]) throws -> UserResult {
        guard let token = object["token"] as? String else {
            throw ApiError.decoding(message: "响应缺少 token 字段")
        }
        let user = object["user"] as? [String: Any] ?? [:]
        return UserResult(
            token: token,
            username: user["username"] as? String ?? "",
            email: user["email"] as? String ?? ""
        )
    }

    static func parseMail(_ object: [String: Any]) throws -> MailItem {
        guard let id = object["id"] as? Int else {
            throw ApiError.decoding(message: "响应缺少 id 字段")
        }
        return MailItem(
            id: id,
            direction: object["direction"] as? String ?? "in",
            fromEmail: object["from_email"] as? String ?? "",
            toEmail: object["to_email"] as? String ?? "",
            subject: object["subject"] as? String ?? "",
            receivedAt: object["received_at"] as? String ?? "",
            isRead: object["is_read"] as? Int ?? 0,
            size: (object["size"] as? NSNumber)?.int64Value ?? 0
        )
    }

    // MARK: - HTTP

    private func normalizedBaseURL() -> String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private func get(_ path: String) async throws -> [String: Any] {
        try await send(method: "GET", path: path, payload: nil)
    }

    private func send(method: String, path: String, payload: [String: Any]?) async throws -> [String: Any] {
        guard let url = URL(string: normalizedBaseURL() + path) else {
            throw ApiError.transport(message: "服务器地址无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let payload {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ApiError.transport(message: error.localizedDescription)
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw ApiError.from(statusCode: code, body: body)
        }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [:]
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApiError.decoding(message: "响应不是合法的 JSON 对象")
        }
        return object
    }
}