import Foundation

/// 登录结果，对应 Android 端 `org.mort.gaymail.api.UserResult`
struct UserResult: Equatable {
    let token: String
    let username: String
    let email: String
    /// 服务端返回的管理员标记（`is_admin`）
    let isAdmin: Bool
}

/// 邮件列表项，对应 `org.mort.gaymail.api.MailItem`
struct MailItem: Identifiable, Equatable {
    let id: Int
    /// "in" 收件箱 / "out" 已发送
    let direction: String
    let fromEmail: String
    let toEmail: String
    let subject: String
    let receivedAt: String
    let isRead: Int
    let size: Int64

    var isUnread: Bool { isRead == 0 }
    var isOutgoing: Bool { direction == "out" }
}

/// 收件箱 / 已发送分页结果，对应 `ApiClient.MailPage`
struct MailPage: Equatable {
    let mails: [MailItem]
    let total: Int
    let unread: Int
}

/// 邮件详情中的附件，对应 `org.mort.gaymail.api.Attachment`
struct Attachment: Identifiable, Equatable {
    let id: Int
    let filename: String
    let mimeType: String
    let size: Int64
    /// Base64 编码的文件内容
    let data: String
}

/// 待发送的附件，对应 `org.mort.gaymail.api.OutAttachment`
struct OutAttachment: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let size: Int64
    /// Base64 编码的文件内容
    let data: String

    static func == (lhs: OutAttachment, rhs: OutAttachment) -> Bool {
        lhs.filename == rhs.filename && lhs.mimeType == rhs.mimeType && lhs.size == rhs.size
    }
}

/// 邮件详情，对应 `org.mort.gaymail.api.MailDetail`
struct MailDetail: Equatable {
    let item: MailItem
    let body: String
    let html: String
    let attachments: [Attachment]
}

/// 配额，对应 `org.mort.gaymail.api.Quota`
struct Quota: Equatable {
    let limit: Int
    let used: Int
    let remaining: Int
}

/// 管理面板统计，对应 `org.mort.gaymail.api.AdminStats`
struct AdminStats: Equatable {
    let users: Int
    let mails: Int
    let unread: Int
    let storageBytes: Int64
}

/// 管理面板用户，对应 `org.mort.gaymail.api.AdminUser`
struct AdminUser: Identifiable, Equatable {
    let id: Int
    let username: String
    let email: String
    let isAdmin: Int
    let banned: Int
    let banReason: String
    let registerIp: String
    let createdAt: String
    let mailCount: Int
}

/// 管理面板用户分页，对应 `org.mort.gaymail.api.AdminUserPage`
struct AdminUserPage: Equatable {
    let users: [AdminUser]
    let total: Int
    let page: Int
    let perPage: Int
}

/// 管理面板邮件行，对应 `org.mort.gaymail.api.AdminMailRow`
struct AdminMailRow: Identifiable, Equatable {
    let id: Int
    let userId: Int
    let direction: String
    let fromEmail: String
    let toEmail: String
    let subject: String
    let receivedAt: String
    let isRead: Int
    let size: Int64
    let owner: String

    var isOutgoing: Bool { direction == "out" }
}

/// 管理面板邮件分页，对应 `org.mort.gaymail.api.AdminMailPage`
struct AdminMailPage: Equatable {
    let mails: [AdminMailRow]
    let total: Int
    let page: Int
    let perPage: Int
}

/// 管理面板邮件详情，对应 `org.mort.gaymail.api.AdminMailView`
struct AdminMailView: Identifiable, Equatable {
    var id: Int { item.id }
    let item: AdminMailRow
    let body: String
    let html: String
}

/// IP 黑名单条目，对应 `org.mort.gaymail.api.IpRow`
struct IpRow: Identifiable, Equatable {
    let id: Int
    let ip: String
    let reason: String
    let createdAt: String
}

/// 公告 / 标语条目，对应 `org.mort.gaymail.api.TextRow`
struct TextRow: Identifiable, Equatable {
    let id: Int
    let content: String
    let createdAt: String
    let updatedAt: String
}

/// 应用更新条目，对应 `org.mort.gaymail.api.AppUpdate`
struct AppUpdate: Identifiable, Equatable {
    let id: Int
    let version: String
    let content: String
    let link: String
    let createdAt: String
}

/// 管理面板中「标题 + 副标题」的通用行，对应 `org.mort.gaymail.admin.AdminRow`
struct AdminRow: Identifiable, Equatable {
    let id: Int
    let title: String
    let sub: String
}

/// 邮件箱
enum MailBox: String, CaseIterable, Identifiable {
    case inbox = "in"
    case sent = "out"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: return L10n.tabInbox
        case .sent: return L10n.tabSent
        }
    }
}

enum Formatters {
    /// 复刻 Android 端 `humanSize` / `renderAttachments` 的显示规则
    static func humanSize(_ size: Int64) -> String {
        if size >= 1_048_576 {
            return String(format: "%.1f MB", Double(size) / 1_048_576.0)
        }
        if size >= 1024 {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        }
        return "\(size) B"
    }

    /// 复刻 Android 端 `AdminActivity.humanBytes`
    static func humanBytes(_ value: Int64) -> String {
        if value >= 1_073_741_824 {
            return String(format: "%.2f GB", Double(value) / 1_073_741_824.0)
        }
        if value >= 1_048_576 {
            return String(format: "%.1f MB", Double(value) / 1_048_576.0)
        }
        if value < 1024 {
            return "\(value) B"
        }
        return String(format: "%.1f KB", Double(value) / 1024.0)
    }

    /// 复刻 Android 端 `AdminActivity.loadIp` 的副标题拼接
    static func ipSubtitle(_ row: IpRow) -> String {
        var text = "\(L10n.ipReasonLabel): \(row.reason.isEmpty ? "-" : row.reason)"
        if !row.createdAt.isEmpty {
            text += " · \(row.createdAt)"
        }
        return text
    }

    /// 复刻 Android 端 `AdminActivity.loadAnns` 的副标题拼接
    static func announcementSubtitle(_ row: TextRow) -> String {
        row.updatedAt.isEmpty ? "" : String(format: L10n.updatedAt, row.updatedAt)
    }

    /// 复刻 Android 端 `AdminActivity.loadUpdates` 的副标题拼接
    static func updateSubtitle(_ update: AppUpdate) -> String {
        let flat = update.content.replacingOccurrences(of: "\n", with: " ")
        var text = String(flat.prefix(80))
        if !update.createdAt.isEmpty {
            text += " · \(update.createdAt)"
        }
        return text
    }
}

/// 应用更新检查，对应 Android 端 `org.mort.gaymail.UpdateChecker`
enum UpdateChecker {
    /// 远端版本是否高于当前版本；支持 `v`/`V` 前缀与 `.-+` 分隔。
    static func isNewer(remote: String, current: String) -> Bool {
        let r = normalized(remote)
        let c = normalized(current)
        if r.isEmpty { return false }

        let rp = split(r)
        let cp = split(c)
        let count = max(rp.count, cp.count)
        for index in 0..<count {
            let a = leadingNumber(rp.indices.contains(index) ? rp[index] : "")
            let b = leadingNumber(cp.indices.contains(index) ? cp[index] : "")
            if a != b { return a > b }
        }
        return false
    }

    private static func normalized(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        return text
    }

    private static func split(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet(charactersIn: ".-+"))
    }

    /// 取字符串开头的数字部分，无有效数字时返回 0（与 Kotlin `toIntOrNull() ?: 0` 一致）
    private static func leadingNumber(_ value: String) -> Int {
        let digits = value.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }
}