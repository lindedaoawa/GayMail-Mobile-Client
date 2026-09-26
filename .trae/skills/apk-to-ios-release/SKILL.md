---
name: "apk-to-ios-release"
description: "逆新版 Android APK 并移植到 iOS SwiftUI，最后触发 GitHub Actions 发布 IPA+APK。Invoke when user puts a new APK in android/ folder and says '移植' or '更新到 iOS' or '发布'."
---

# APK → iOS 移植 + Release 发布

本技能覆盖"拿到新版 Android APK → 逆向定位变更 → 在 iOS SwiftUI 端完整还原 → 推 GitHub → 触发 Release 工作流打包 IPA+APK"的完整链路。适用于 GayMail-Mobile-Client 这类跨平台邮件客户端场景。

---

## 触发条件

用户说下面任一句，且 `android/` 目录下有 APK 文件时，激活本技能：
- "移植新版 APK"
- "把新内容移植到 iOS"
- "同步 Android 新版"
- "可以准备发布了"
- "执行发布"

---

## 一、逆向新版 APK

### 1.1 确认哪个是新版、版本号多少

```bash
# 新版 APK 往往不带版本号，先确认 BuildConfig
python3 -c "
import zipfile
with zipfile.ZipFile('android/<new>.apk') as z:
    data = z.read('classes.dex')
    # BuildConfig.VERSION_NAME / VERSION_CODE
    import re
    for m in re.finditer(rb'BUILD\\.?VERSION_NAME=([^\\\\x00]+)', data):
        print('VERSION_NAME:', m.group(1))
    for m in re.finditer(rb'BUILD\\.?VERSION_CODE=([0-9]+)', data):
        print('VERSION_CODE:', m.group(1))
"

# 列出 android/ 所有 apk* 文件，按 mtime 判断新旧
ls -lt android/*.apk*
```

### 1.2 用 jadx 反编译到独立目录（不要覆盖 /workspace 已有 src）

```bash
jadx -d /tmp/new_src android/<new>.apk
ls /tmp/new_src/sources/org/mort/gaymail/
```

### 1.3 识别新增 Activity / API / 数据模型

```bash
# 列出所有 Activity（通常是新增功能的入口）
find /tmp/new_src/sources -name "*.java" | xargs grep -l "extends AppCompatActivity\|extends ComponentActivity"

# API 接口清单：所有 def 方法
grep -E "^\s+(public\s+final\s+)?\w+(\[\])?\s+\w+\(" /tmp/new_src/sources/org/mort/gaymail/api/ApiClient.java | head -50

# 对比旧逆向目录（如果有）与新目录的差异
diff -rq /tmp/old_src/sources/org/mort/gaymail /tmp/new_src/sources/org/mort/gaymail | head -50
```

### 1.4 重点看 `AdminActivity.java`（79KB 大文件分段读）

```bash
# 大文件用 offset/limit 读
sed -n '1,450p' /tmp/new_src/sources/org/mort/gaymail/admin/AdminActivity.java
sed -n '450,900p' ...
sed -n '900,1400p' ...

# 关键方法索引
grep -nE "public final|private final|setup[A-Z]|load[A-Z]|patchUser|userActions|friendlyError" AdminActivity.java
```

需要对应移植的 Admin Activity 结构：
- `switchTab(index)` — 7 个标签页切换
- `setupUsers / setupMails / setupIp / setupAnns / setupSlogans / setupUpdates` — 初始化 RecyclerView + 搜索框 + 下拉刷新 + FAB
- `load* / reload*` — 分页面加载
- `userActions(u)` — 根据 self / isAdmin / banned 拼装操作菜单
- `patchUser(u, isAdmin?, banned?, banReason?, password?)` — 复用的用户修改入口
- `guard(e)` — 401 清会话跳登录 / 403 Toast 后 finish / 其他 friendlyError

### 1.5 对应 API 契约移植清单

Android ApiClient 新增方法 → iOS ApiClient.swift：
| Android | iOS | 备注 |
|---|---|---|
| `me()` | `me()` → Bool | 同步管理员权限 |
| `adminStats()` | `adminStats()` → AdminStats | |
| `adminUsers(q, page, perPage)` | `adminUsers(q, page, perPage)` → AdminUserPage | |
| `adminUserPatch(id, isAdmin, banned, banReason, password)` | `adminUserPatch(id:isAdmin:banned:banReason:password:)` | 可选参数 |
| `adminUserDelete(id)` | `adminUserDelete(id:)` | |
| `adminMails(q, page, perPage)` | `adminMails(q, page, perPage)` → AdminMailPage | |
| `adminMailDetail(id)` | `adminMailDetail(id:)` → AdminMailView | |
| `adminMailDelete(id)` | `adminMailDelete(id:)` | |
| `ipList()` | `ipList()` → [IpRow] | |
| `ipAdd(ip, reason)` | `ipAdd(ip:reason:)` → String | 返回 message |
| `ipDelete(id)` | `ipDelete(id:)` | |
| `annList()` / `annCreate(content)` / `annUpdate(id, content)` / `annDelete(id)` | 对应 | |
| `slogan*` 同上 | 对应 | |
| `latestUpdate()` | `latestUpdate()` → AppUpdate? | |
| `adminUpdates()` / `updateCreate` / `updatePatch` / `updateDelete` | 对应 | |
| `enc(s)` | 保留 | `[+&=]` 需额外编码 |
| `patch(path, payload)` | 保留 | PATCH + JSON body |

---

## 二、iOS SwiftUI 端实现要点

### 2.1 Admin 数据模型（Models.swift）

`AdminStats / AdminUser / AdminMailRow / AdminMailView / IpRow / TextRow / AppUpdate` 全部要做，字段照 Android Kotlin data class 对齐。

**必须 conform `Identifiable` 的类型**（SwiftUI 的 `.sheet(item:)` / `ForEach` 需要）：
```swift
extension AdminMailView: Identifiable { var id { item.id } }
extension AdminMailRow: Identifiable { var id { id } }
```

### 2.2 SessionStore 管理员状态

```swift
// 持久化：UserDefaults forKey "is_admin"
func saveSession(_ result: UserResult) { ... defaults.set(result.isAdmin, forKey: Key.isAdmin) ... }
func setAdmin(_ value: Bool) { defaults.set(value, forKey: Key.isAdmin); isAdmin = value }
```

### 2.3 MailListView 对接管理员入口 & 更新检查

```swift
// Toolbar 菜单只对管理员显示
Menu {
    Button(L10n.menuQuota) { ... }
    if session.isAdmin {
        Button(L10n.menuAdmin) { showAdmin = true }
    }
    Button(L10n.menuSettings) { ... }
}

// 启动时同步管理员权限 + 检查更新
.task {
    await refreshAdminFlag()   // POST /api/me
    refresh()
    await checkUpdates()       // 比对 UpdateChecker.isNewer(remote, current)
}

// 更新弹窗 —— iOS 系统 Alert
.alert(isPresented: $showUpdateAlert) { ... }
```

### 2.4 AdminView 7 个标签页（SwiftUI 容器）

**踩过的坑：**
- ❌ `private struct AnnsTab: View { var body: TextTab(kind: .announcement) }` 编译报错 `unexpected initializer in pattern` —— SwiftUI 的 `var body` 必须返回 `some View`，禁止直接写函数调用表达式。✅ 改为在 `TabView` 里直接 `TextTab(kind: .announcement).tag(4)`。
- ✅ `TabView` + `.tabViewStyle(.page(indexDisplayMode: .never))` 配合顶部 `Picker` 做"分段标签页"。
- ✅ 搜索框防抖：`@State private var query` + `.task(id: query)` 即可（Swift Concurrency 自动取消旧任务，比 Android 的 `searchJob.cancel()` 简洁）。
- ✅ 分页：`page / hasMore` + `onAppear` 到最后一个 cell 触发 `loadMore()`。
- ✅ 下拉刷新：原生 `.refreshable { await reload() }`。
- ✅ 删除确认 Alert：`.alert(isPresented: Binding(get: { pendingDelete != nil }, ...))`。

### 2.5 用户操作菜单复刻 Android 逻辑

```swift
let self = user.username == session.username || user.email == session.email
if user.isAdmin == 1 { ... }
if !self {
    // 不能操作自己：ban / resetPassword / delete 都跳过
}
```

### 2.6 分页 API 返回不足一页判断 hasMore

Android 端 `finish = m.count < perPage`。iOS 端同理：
```swift
hasMore = result.users.count >= 20   // perPage=20
```

### 2.7 更新检查（UpdateChecker.isNewer 移植）

版本字符串先去 `v`/`V` 前缀，按 `[.-+]` 切分，每段取开头数字比较：
```swift
while text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
let rp = value.components(separatedBy: CharacterSet(charactersIn: ".-+"))
let digits = value.prefix { $0.isNumber }
```

### 2.8 LoginView 人机验证重试

Android 端 `loginWithRetry` 最多 3 次，检测到 `ApiError.requiresCaptchaRetry` 时自动弹出人机验证。iOS 端对应：
```swift
if apiError?.requiresCaptchaRetry == true && !recaptchaUsed {
    recaptchaUsed = true
    captchaToken = nil
    showCaptcha = true
}
```

---

## 三、Push 到 GitHub

### 3.1 检查 remote URL（**关键坑！**）

```bash
git remote get-url origin
# Android APK 文件名容易写错，确认 glob
ls android/GayMail-*.apk
```

**曾经遇到**：用户给的 PAT 对应 repo `lindedaoawa` 实际重定向到 `lindedaoqwq`（少打了个 a），但 curl API 静默 301 不报错，导致本地推错 remote。**做法**：
1. 先 `git remote set-url origin https://github.com/<owner>/<repo>.git`
2. 再 `git push origin main`
3. 用 `curl api.github.com/repos/<owner>/<repo>` 确认返回 `full_name` 是预期的

### 3.2 commit 信息示例

```
fix: 替换旧版 1.0.0 APK 为真实 1.1.0 新版；Release Notes 去硬编码版本号
```

---

## 四、Release 工作流 & 坑

### 4.1 工作流路径

- `.github/workflows/build-ios.yml` — 构建测试，手动 `workflow_dispatch` 或 push 触发
- `.github/workflows/release.yml` — 手动 `workflow_dispatch` 触发，输入 `version` + `prerelease`

### 4.2 触发方式（PAT 直接调 API）

```bash
curl -s -X POST -H "Authorization: token $GH_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO/actions/workflows/release.yml/dispatches" \
  -H "Content-Type: application/json" \
  -d '{"ref":"main","inputs":{"version":"1.1.0","prerelease":false}}'
```

### 4.3 轮询状态

```bash
# 每 30-40 秒轮询一次，看 conclusion 变化
curl -s -H "Authorization: token $GH_TOKEN" \
  "https://api.github.com/repos/$REPO/actions/runs?per_page=2" | \
  python3 -c "... print(f'{r[\"name\"]} #{r[\"run_number\"]} [{r[\"status\"]}/{r[\"conclusion\"]}]')"
```

### 4.4 查看 Job 日志找错误

```bash
# 先拿 run 的所有 job id
curl ... /runs/<run_id>/jobs | python3 "print jobs"
# 再拉某 job 的完整日志（LIMIT 用 grep 过滤 error / warning）
curl -L ... /jobs/<job_id>/logs | grep -E "\.swift:[0-9]+:[0-9]+: (error|warning)" | head -30
```

### 4.5 Release 历史坑（全部踩过）

| 失败现象 | 根因 | 修 |
|---|---|---|
| `Android APK` 步骤打包出的是旧版 | `android/` 里旧 APK 文件名先被 glob 匹配到 | 新版命名 `GayMail-<ver>.apk`，删掉旧版 |
| Release Notes 里硬编码 `GayMail-1.0.0.apk` | release.yml 写死文件名 | 用 `ls dist/*.apk \| head -n1 \| xargs basename` 动态取值 |
| SwiftUI 编译 `unexpected initializer in pattern` | `var body: X(...)` 非法 | TabView 里直接实例化 |
| `.sheet(item:)` 报 `requires Identifiable` | AdminMailView 没 conform | 加 `extension AdminMailView: Identifiable { var id { item.id } }` |
| Release 创建报 `a release with the same tag name already exists` | 同一 version 不能触发两次 create | **先删旧 tag 和 release**：`DELETE /repos/<owner>/<repo>/git/refs/tags/v<ver>` + `DELETE /repos/<owner>/<repo>/releases/<release_id>`，再重新触发 workflow |
| 找不到 `xcpretty` | runner 没预装 | 删掉 `| xcpretty \|\| ...`，直接跑 `xcodebuild test` |
| 登录页服务器地址被我还原了 | 新版 Android 用 defaults 但 UI 不显示输入框 | iOS 端登录页删掉服务器输入框，默认 `ApiClient.defaultBaseURL = "https://mail.mort.gay"` |

---

## 五、快速命令清单

```bash
# 新版 APK 版本号
python3 -c "
import zipfile,re
with zipfile.ZipFile('android/*.apk') as z:
    d=z.read('classes.dex')
    print('VERSION_NAME =', re.search(rb'NAME=([^\\x00]+)', d).group(1))"

# 反编译
jadx -d /tmp/new_src android/*.apk

# 对比旧版差异
diff -rq /tmp/old_src/sources/org/mort/gaymail /tmp/new_src/sources/org/mort/gaymail

# 推 GitHub
git add -A && git commit -m "..." && git push origin main

# 触发 Release
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  -H "Authorization: token $GH_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO/actions/workflows/release.yml/dispatches" \
  -H "Content-Type: application/json" \
  -d '{"ref":"main","inputs":{"version":"1.1.0","prerelease":false}}'

# 删除旧 tag + release（准备重发同版本）
curl -s -o /dev/null -w "%{http_code}\n" -X DELETE \
  -H "Authorization: token $GH_TOKEN" \
  "https://api.github.com/repos/$REPO/git/refs/tags/v1.1.0"
REL_ID=$(curl ... /releases/tags/v1.1.0 | python3 "print(json.load(sys.stdin)['id'])")
curl -s -o /dev/null -w "%{http_code}\n" -X DELETE \
  -H "Authorization: token $GH_TOKEN" \
  "https://api.github.com/repos/$REPO/releases/$REL_ID"
```

---

## 六、交付检查清单

- [ ] 新版 APK 确认放在 `android/GayMail-<version>.apk`（文件名含版本号）
- [ ] 旧版 APK 从 `android/` 删除（workflow glob 容易误匹配）
- [ ] `ios/GayMail/API/ApiClient.swift` — 新增的 Android 方法全部移植
- [ ] `ios/GayMail/Models/Models.swift` — 新增数据模型 + `Identifiable` 扩展
- [ ] `ios/GayMail/Models/L10n.swift` — 新增字符串常量
- [ ] `ios/GayMail/Storage/SessionStore.swift` — `isAdmin` 持久化
- [ ] `ios/GayMail/Views/AdminView.swift` — 7 标签页实现
- [ ] `ios/GayMail/Views/MailListView.swift` — 管理员菜单入口 + 更新检查接入
- [ ] SwiftUI 编译过（可通过 GitHub Actions `build-ios.yml` 验证）
- [ ] Release workflow Release Notes 去硬编码文件名（动态取 dist/*.apk）
- [ ] Release workflow `apk` 文件名 glob 正确
- [ ] `README.md` 里 APK 文件名去硬编码
- [ ] 触发 `release.yml` + 等 `conclusion=success`
- [ ] 检查 release 附件里 APK 是正确版本号（不是旧 1.0.0）
