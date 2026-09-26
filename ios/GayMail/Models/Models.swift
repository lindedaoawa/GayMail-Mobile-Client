import Foundation

/// 登录结果，对应 Android 端 `org.mort.gaymail.api.UserResult`
struct UserResult: Equatable {
    let token: String
    let username: String
    let email: String
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
}