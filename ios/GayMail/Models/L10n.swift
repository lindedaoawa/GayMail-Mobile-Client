import Foundation

/// 文案集中管理，与 Android 端 `res/values/strings.xml` 保持一致
enum L10n {
    static let appName = "GayMail"
    static let loginSubtitle = "Mort.gay 邮箱"

    static let tabInbox = "收件箱"
    static let tabSent = "已发送"

    static let composeTo = "收件人（多个用逗号分隔）"
    static let composeSubject = "主题"
    static let composeBody = "正文"
    static let composeAttachments = "附件"

    static let detailFrom = "发件人"
    static let detailTo = "收件人"
    static let detailNoAttachments = "无附件"

    static let deleteConfirm = "确定删除这封邮件？"
    static let deleteOk = "删除"
    static let deleteCancel = "取消"

    static let logoutConfirm = "退出当前账号？"
    static let menuLogout = "退出登录"
    static let menuQuota = "今日配额"
    static let menuSettings = "服务器地址"
    static let menuRefresh = "刷新"
    static let menuSend = "发送"
    static let menuAttach = "添加附件"
    static let menuDelete = "删除"
    static let menuReply = "回复"
    static let menuForward = "转发"

    static let hintServer = "服务器地址"
    static let attachmentTooLarge = "附件超过 16MB 限制"
    static let loginCaptcha = "正在人机验证…"
    static let loginFailed = "登录失败"
    static let captchaFailed = "人机验证失败"
    static let emptyList = "暂无邮件"
    static let loadFailed = "加载失败"
    static let sendSuccess = "发送成功"
    static let saveSuccess = "已保存到「文件」"
    static let serverInvalid = "请输入以 http 开头的服务器地址"
}