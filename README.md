# GayMail-Mobile-Client

GayMail 移动客户端。本项目包含 Android 原始客户端安装包，以及使用 **Swift / SwiftUI** 重写的 iOS 客户端源码，通过 **GitHub Actions** 自动构建与发布。

- 服务端：`https://mail.mort.gay`（可在 App 内「服务器地址」中修改）
- 支持的平台：Android、iOS 15.0+
- 默认语言：简体中文

## 功能特性

客户端与 Android 端保持一致的接口契约（路径、字段、鉴权方式），主要功能包括：

| 功能 | 说明 |
| --- | --- |
| 账号登录 | 用户名 + 密码登录，配合 hCaptcha 人机验证获取 `token` |
| 收件箱 / 已发送 | 双箱切换，分页加载（每页 50 封），显示未读状态 |
| 邮件列表 | 下拉刷新、上拉加载更多，展示发件人、主题、时间与大小 |
| 邮件详情 | 正文 / HTML 渲染、附件列表与「保存到文件」 |
| 撰写邮件 | 收件人（支持多个，逗号分隔）、主题、正文、附件（单文件上限 16MB） |
| 附件处理 | Base64 编码传输，支持下载保存到系统「文件」App |
| 回复 / 转发 | 在详情页直接回复或转发 |
| 删除邮件 | 二次确认后删除 |
| 配额查询 | 查看当日配额（上限 / 已用 / 剩余） |
| 会话管理 | 令牌等敏感信息使用 Keychain 存储，支持退出登录 |

### 接口一览

| 接口 | 方法 | 说明 |
| --- | --- | --- |
| `/api/login` | POST | 登录并获取令牌 |
| `/api/mail?box=&page=&per_page=` | GET | 邮件列表分页 |
| `/api/mail/{id}` | GET | 邮件详情（含附件） |
| `/api/mail/{id}/read` | POST | 标记为已读 |
| `/api/mail/{id}` | DELETE | 删除邮件 |
| `/api/quota` | GET | 查询当日配额 |
| `/api/send2` | POST | 发送邮件（支持附件） |

鉴权方式：请求头 `Authorization: Bearer <token>`。

## 目录结构

```
.
├── android/                 # Android 原始安装包
│   └── GayMail-1.0.0.apk
├── ios/                     # Swift / SwiftUI 重写的 iOS 客户端
│   ├── GayMail/
│   │   ├── API/             # ApiClient、错误映射
│   │   ├── App/             # App 入口
│   │   ├── Components/      # hCaptcha、HTMLView、分享面板
│   │   ├── Models/          # 数据模型与文案
│   │   ├── Resources/       # Info.plist、图标资源
│   │   ├── Storage/         # Keychain 与会话存储
│   │   └── Views/           # 登录 / 列表 / 详情 / 撰写 / 主题
│   ├── GayMailTests/        # 单元测试（API 契约、模型解析）
│   └── project.yml          # XcodeGen 工程定义
└── .github/workflows/       # CI/CD 工作流
```

## 构建与测试

### iOS

工程使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 管理，`project.yml` 为唯一工程来源。

```bash
brew install xcodegen
cd ios
xcodegen generate
open GayMail.xcodeproj
```

命令行构建（未签名 IPA）：

```bash
cd ios
xcodebuild archive \
  -project GayMail.xcodeproj \
  -scheme GayMail \
  -configuration Release \
  -sdk iphoneos \
  -archivePath build/GayMail.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

mkdir -p build/Payload
cp -R build/GayMail.xcarchive/Products/Applications/GayMail.app build/Payload/
(cd build && zip -qry GayMail-1.0.0-unsigned.ipa Payload)
```

最低部署版本：**iOS 15.0**（`IPHONEOS_DEPLOYMENT_TARGET = 15.0`）。

### Android

`android/GayMail-1.0.0.apk` 为原客户端安装包，可直接安装，无需额外构建。

## CI / CD

| 工作流 | 触发方式 | 说明 |
| --- | --- | --- |
| [`build-ios.yml`](.github/workflows/build-ios.yml) | push / PR / 手动 | 生成工程、运行单元测试、归档并打包未签名 IPA，校验 `MinimumOSVersion = 15.0`，上传 IPA 与测试报告 |
| [`release.yml`](.github/workflows/release.yml) | **手动触发** | 发布前回归测试 → 打包 IPA 与 APK → 创建 GitHub Release 并同时上传两个安装包 |

发布流程：先由 `build-ios.yml` 完成构建测试，确认无误后在 Actions 页面手动运行 **Release** 工作流并填写版本号，即可同时产出 Android APK 与 iOS IPA。

## 安装说明

### Android

下载 `GayMail-1.0.0.apk` 后直接安装（需允许「未知来源」安装）。

### iOS

发布产物 `GayMail-<版本>-unsigned.ipa` 为 **未签名** 包，无法直接安装，需重签名后使用：

- AltStore / SideStore / Sideloadly 等自签工具
- TrollStore（仅限支持的系统版本）
- 使用自有开发者证书执行 `codesign`，再通过 Xcode / Apple Configurator 安装

系统要求：iOS 15.0 及以上。

## 许可证

本项目遵循仓库根目录 [LICENSE](LICENSE) 中的许可条款。

## 免责声明

本项目为客户端移植与学习用途，请遵守服务端所在地区的法律法规及相关服务条款，勿用于任何非法用途。