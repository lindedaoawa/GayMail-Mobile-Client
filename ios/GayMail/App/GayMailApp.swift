import SwiftUI

@main
struct GayMailApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}

/// 根据会话状态在登录页与邮件列表之间切换，
/// 对应 Android 端 `LoginActivity` / `MainActivity` 的跳转逻辑。
struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if session.isLoggedIn {
                MailListView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isLoggedIn)
    }
}