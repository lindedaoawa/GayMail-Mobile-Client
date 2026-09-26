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
    static let captchaExpired = "验证已过期，重新验证…"
    static let emptyList = "暂无邮件"
    static let loadFailed = "加载失败"
    static let sendSuccess = "发送成功"
    static let saveSuccess = "已保存到「文件」"
    static let serverInvalid = "请输入以 http 开头的服务器地址"

    // MARK: - 管理面板（对应 res/values/strings.xml）

    static let menuAdmin = "管理面板"
    static let adminDenied = "需要管理员权限"

    static let tabStats = "概览"
    static let tabUsers = "用户"
    static let tabMails = "邮件"
    static let tabIp = "黑名单"
    static let tabAnns = "公告"
    static let tabSlogans = "标语"
    static let tabUpdates = "更新"

    static let statUsers = "用户总数"
    static let statMails = "邮件总数"
    static let statUnread = "未读邮件"
    static let statStorage = "存储占用"

    static let searchHint = "搜索…"
    static let userSearchHint = "用户名或邮箱"
    static let userMailsCountFormat = "%d 封邮件"

    static let userActionAdmin = "设为管理员"
    static let userActionUnadmin = "取消管理员"
    static let userActionBan = "封禁账号"
    static let userActionUnban = "解除封禁"
    static let userActionResetPw = "重置密码"
    static let userActionDelete = "删除用户"
    static let userDeleteConfirm = "删除该用户及其全部邮件？"
    static let banReasonHint = "封禁原因（可选）"
    static let resetPwHint = "新密码（至少 8 位）"

    static let mailDeleteConfirm = "删除这封邮件？"

    static let ipAddTitle = "加入黑名单"
    static let ipHint = "IPv4 地址"
    static let ipReasonHint = "原因（可选）"
    static let ipReasonLabel = "原因"
    static let ipDeleteConfirm = "移出黑名单？"
    static let ipAdded = "已加入黑名单"

    static let annNew = "发布公告"
    static let annEdit = "编辑公告"
    static let annHint = "公告内容"
    static let sloganNew = "新增标语"
    static let sloganEdit = "编辑标语"
    static let sloganHint = "标语内容（最多 200 字）"
    static let updatedAt = "更新于 %@"
    static let textDeleteConfirm = "删除这条记录？"
    static let menuEdit = "编辑"

    static let updatePublish = "发布更新"
    static let updateEdit = "编辑更新"
    static let updateVersionRequired = "请填写版本号"
    static let updateLinkInvalid = "链接必须以 http(s):// 开头"
    static let updateHintVersion = "版本号（如 1.0.1）"
    static let updateHintContent = "更新内容"
    static let updateHintLink = "跳转链接（http 开头，可选）"
    static let updateFound = "发现新版本 %@"
    static let updateNow = "去更新"
    static let updateLater = "稍后"
    static let updateOpenFailed = "无法打开链接"
    static let unknownError = "未知错误"
}