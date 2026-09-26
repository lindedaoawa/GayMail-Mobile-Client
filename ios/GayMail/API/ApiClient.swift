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

    // MARK: - 管理面板（对应 Android 端 /api/admin/*）

    /// 当前登录用户是否为管理员，对应 `ApiClient.me()`
    func me() async throws -> Bool {
        let object = try await get("/api/me")
        guard let user = object["user"] as? [String: Any] else { return false }
        if let flag = user["is_admin"] as? Bool { return flag }
        if let value = user["is_admin"] as? Int { return value == 1 }
        return false
    }

    func adminStats() async throws -> AdminStats {
        let object = try await get("/api/admin/stats")
        let stats = object["stats"] as? [String: Any] ?? [:]
        return AdminStats(
            users: stats["users"] as? Int ?? 0,
            mails: stats["mails"] as? Int ?? 0,
            unread: stats["unread"] as? Int ?? 0,
            storageBytes: (stats["storage_bytes"] as? NSNumber)?.int64Value ?? 0
        )
    }

    func adminUsers(q: String, page: Int, perPage: Int = 20) async throws -> AdminUserPage {
        let object = try await get("/api/admin/users?q=\(enc(q))&page=\(page)&per_page=\(perPage)")
        let users = ((object["users"] as? [[String: Any]]) ?? []).map { ApiClient.parseAdminUser($0) }
        return AdminUserPage(
            users: users,
            total: object["total"] as? Int ?? users.count,
            page: object["page"] as? Int ?? page,
            perPage: object["per_page"] as? Int ?? perPage
        )
    }

    func adminUserPatch(
        id: Int,
        isAdmin: Bool? = nil,
        banned: Bool? = nil,
        banReason: String? = nil,
        password: String? = nil
    ) async throws {
        var payload: [String: Any] = [:]
        if let isAdmin { payload["is_admin"] = isAdmin }
        if let banned { payload["banned"] = banned }
        if let banReason { payload["ban_reason"] = banReason }
        if let password { payload["password"] = password }
        guard !payload.isEmpty else { return }
        _ = try await patch("/api/admin/users/\(id)", payload)
    }

    func adminUserDelete(id: Int) async throws {
        _ = try await send(method: "DELETE", path: "/api/admin/users/\(id)", payload: nil)
    }

    func adminMails(q: String, page: Int, perPage: Int = 20) async throws -> AdminMailPage {
        let object = try await get("/api/admin/mails?q=\(enc(q))&page=\(page)&per_page=\(perPage)")
        let mails = ((object["mails"] as? [[String: Any]]) ?? []).map {
            ApiClient.parseAdminMail($0, owner: $0["owner"] as? String ?? "")
        }
        return AdminMailPage(
            mails: mails,
            total: object["total"] as? Int ?? mails.count,
            page: object["page"] as? Int ?? page,
            perPage: object["per_page"] as? Int ?? perPage
        )
    }

    func adminMailDetail(id: Int) async throws -> AdminMailView {
        let object = try await get("/api/admin/mails/\(id)")
        let mail = object["mail"] as? [String: Any] ?? [:]
        let item = ApiClient.parseAdminMail(mail, owner: "")
        let body = mail["body"] as? String ?? ""
        let html = (mail["html"] as? String) ?? (mail["body_html"] as? String) ?? ""
        return AdminMailView(item: item, body: body, html: html)
    }

    func adminMailDelete(id: Int) async throws {
        _ = try await send(method: "DELETE", path: "/api/admin/mails/\(id)", payload: nil)
    }

    // MARK: - IP 黑名单

    func ipList() async throws -> [IpRow] {
        let object = try await get("/api/admin/ipblacklist")
        return ((object["list"] as? [[String: Any]]) ?? []).map { raw in
            IpRow(
                id: raw["id"] as? Int ?? 0,
                ip: raw["ip"] as? String ?? "",
                reason: raw["reason"] as? String ?? "",
                createdAt: raw["created_at"] as? String ?? ""
            )
        }
    }

    /// 返回服务端提示信息，对应 `ApiClient.ipAdd`
    @discardableResult
    func ipAdd(ip: String, reason: String?) async throws -> String {
        var payload: [String: Any] = ["ip": ip]
        if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["reason"] = reason
        }
        let object = try await send(method: "POST", path: "/api/admin/ipblacklist", payload: payload)
        return object["message"] as? String ?? L10n.ipAdded
    }

    func ipDelete(id: Int) async throws {
        _ = try await send(method: "DELETE", path: "/api/admin/ipblacklist/\(id)", payload: nil)
    }

    // MARK: - 公告 / 标语

    /// 公告列表为公开接口 `/api/announcements`
    func annList() async throws -> [TextRow] {
        try await textRows(key: "announcements", path: "/api/announcements")
    }

    @discardableResult
    func annCreate(content: String) async throws -> Int {
        let object = try await send(method: "POST", path: "/api/admin/announcements", payload: ["content": content])
        return object["id"] as? Int ?? 0
    }

    func annUpdate(id: Int, content: String) async throws {
        _ = try await patch("/api/admin/announcements/\(id)", ["content": content])
    }

    func annDelete(id: Int) async throws {
        _ = try await send(method: "DELETE", path: "/api/admin/announcements/\(id)", payload: nil)
    }

    func sloganList() async throws -> [TextRow] {
        try await textRows(key: "slogans", path: "/api/admin/slogans")
    }

    @discardableResult
    func sloganCreate(content: String) async throws -> Int {
        let object = try await send(method: "POST", path: "/api/admin/slogans", payload: ["content": content])
        return object["id"] as? Int ?? 0
    }

    func sloganUpdate(id: Int, content: String) async throws {
        _ = try await patch("/api/admin/slogans/\(id)", ["content": content])
    }

    func sloganDelete(id: Int) async throws {
        _ = try await send(method: "DELETE", path: "/api/admin/slogans/\(id)", payload: nil)
    }

    private func textRows(key: String, path: String) async throws -> [TextRow] {
        let object = try await get(path)
        return ((object[key] as? [[String: Any]]) ?? []).map { raw in
            TextRow(
                id: raw["id"] as? Int ?? 0,
                content: raw["content"] as? String ?? "",
                createdAt: raw["created_at"] as? String ?? "",
                updatedAt: raw["updated_at"] as? String ?? ""
            )
        }
    }

    // MARK: - 应用更新

    /// 最新版本，无更新记录时返回 nil，对应 `ApiClient.latestUpdate`
    func latestUpdate() async throws -> AppUpdate? {
        let object = try await get("/api/updates/latest")
        guard let update = object["update"] as? [String: Any] else { return nil }
        return ApiClient.parseUpdate(update)
    }

    func adminUpdates() async throws -> [AppUpdate] {
        let object = try await get("/api/admin/updates")
        return ((object["updates"] as? [[String: Any]]) ?? []).map { ApiClient.parseUpdate($0) }
    }

    @discardableResult
    func updateCreate(version: String, content: String, link: String) async throws -> Int {
        let payload: [String: Any] = ["version": version, "content": content, "link": link]
        let object = try await send(method: "POST", path: "/api/admin/updates", payload: payload)
        return object["id"] as? Int ?? 0
    }

    func updatePatch(id: Int, version: String, content: String, link: String) async throws {
        _ = try await patch("/api/admin/updates/\(id)", ["version": version, "content": content, "link": link])
    }

    func updateDelete(id: Int) async throws {
        _ = try await send(method: "DELETE", path: "/api/admin/updates/\(id)", payload: nil)
    }

    // MARK: - 解析

    static func parseUser(_ object: [String: Any]) throws -> UserResult {
        guard let token = object["token"] as? String else {
            throw ApiError.decoding(message: "响应缺少 token 字段")
        }
        let user = object["user"] as? [String: Any] ?? [:]
        var isAdmin = false
        if let flag = user["is_admin"] as? Bool {
            isAdmin = flag
        } else if let value = user["is_admin"] as? Int {
            isAdmin = value == 1
        }
        return UserResult(
            token: token,
            username: user["username"] as? String ?? "",
            email: user["email"] as? String ?? "",
            isAdmin: isAdmin
        )
    }

    static func parseAdminUser(_ object: [String: Any]) -> AdminUser {
        AdminUser(
            id: object["id"] as? Int ?? 0,
            username: object["username"] as? String ?? "",
            email: object["email"] as? String ?? "",
            isAdmin: object["is_admin"] as? Int ?? 0,
            banned: object["banned"] as? Int ?? 0,
            banReason: object["ban_reason"] as? String ?? "",
            registerIp: object["register_ip"] as? String ?? "",
            createdAt: object["created_at"] as? String ?? "",
            mailCount: object["mail_count"] as? Int ?? 0
        )
    }

    static func parseAdminMail(_ object: [String: Any], owner: String) -> AdminMailRow {
        AdminMailRow(
            id: object["id"] as? Int ?? 0,
            userId: object["user_id"] as? Int ?? 0,
            direction: object["direction"] as? String ?? "in",
            fromEmail: object["from_email"] as? String ?? "",
            toEmail: object["to_email"] as? String ?? "",
            subject: object["subject"] as? String ?? "",
            receivedAt: object["received_at"] as? String ?? "",
            isRead: object["is_read"] as? Int ?? 0,
            size: (object["size"] as? NSNumber)?.int64Value ?? 0,
            owner: owner
        )
    }

    static func parseUpdate(_ object: [String: Any]) -> AppUpdate {
        AppUpdate(
            id: object["id"] as? Int ?? 0,
            version: object["version"] as? String ?? "",
            content: object["content"] as? String ?? "",
            link: object["link"] as? String ?? "",
            createdAt: object["created_at"] as? String ?? ""
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

    /// 对应 Android 端 `ApiClient.patch`（PATCH + JSON 请求体）
    private func patch(_ path: String, _ payload: [String: Any]) async throws -> [String: Any] {
        try await send(method: "PATCH", path: path, payload: payload)
    }

    /// 复刻 Android 端 `ApiClient.enc`，用于查询参数编码
    private func enc(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
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