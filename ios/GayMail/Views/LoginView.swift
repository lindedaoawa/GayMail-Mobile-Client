import SwiftUI
import UIKit

/// 登录页，对应 Android 端 `org.mort.gaymail.LoginActivity`。
struct LoginView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var username = ""
    @State private var password = ""

    @State private var busy = false
    @State private var message: String?
    @State private var captchaToken: String?
    @State private var captchaError: String?
    @State private var captchaAttempt = UUID()
    @State private var showCaptcha = false
    @State private var captchaHeight: CGFloat = 78
    /// 对应 Android 端 `recaptchaUsed`，同一次登录只自动重新验证一次
    @State private var recaptchaUsed = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    VStack(spacing: 12) {
                        labelledField(title: "用户名 / 邮箱", systemImage: "person") {
                            TextField("username", text: $username)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                        }
                        labelledField(title: "密码", systemImage: "lock") {
                            SecureField("password", text: $password)
                        }
                    }

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(Color.gmDanger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: startLogin) {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? L10n.loginCaptcha : "登录")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .background(Color.gmPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(busy)

                    Button("注册新账号") { openRegister() }
                        .font(.footnote)
                        .foregroundColor(Color.gmPrimary)
                }
                .padding(24)
            }
            .background(Color.gmBackground.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showCaptcha) {
            captchaSheet
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 52))
                .foregroundColor(Color.gmPrimary)
            Text(L10n.appName)
                .font(.largeTitle.bold())
                .foregroundColor(Color.gmText)
            Text(L10n.loginSubtitle)
                .font(.subheadline)
                .foregroundColor(Color.gmText.opacity(0.7))
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private func labelledField<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundColor(Color.gmText.opacity(0.8))
            content()
                .padding(10)
                .background(Color.gmSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gmPrimary.opacity(0.25), lineWidth: 1)
                )
                .cornerRadius(8)
        }
    }

    private var captchaSheet: some View {
        // 挑战面板较高，外层可滚动以保证内容完整可见
        ScrollView {
            VStack(spacing: 16) {
                Text(L10n.loginCaptcha)
                    .font(.headline)
                HCaptchaView(
                    siteKey: ApiClient.hcaptchaSiteKey,
                    token: $captchaToken,
                    errorMessage: $captchaError,
                    height: $captchaHeight
                )
                .frame(height: captchaHeight)
                .id(captchaAttempt)

                if let captchaError {
                    Text("\(L10n.captchaFailed)：\(captchaError)")
                        .font(.footnote)
                        .foregroundColor(Color.gmDanger)
                        .multilineTextAlignment(.center)
                }

                Button(L10n.deleteCancel) {
                    showCaptcha = false
                    reset()
                }
                .foregroundColor(Color.gmText)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: captchaToken) { token in
            guard let token, !token.isEmpty else { return }
            showCaptcha = false
            Task { await performLogin(captcha: token) }
        }
    }

    // MARK: - 行为

    private func startLogin() {
        guard !busy else { return }
        message = nil
        captchaToken = nil
        captchaError = nil
        captchaHeight = 78
        captchaAttempt = UUID()

        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else {
            message = L10n.loginFailed
            return
        }

        busy = true
        recaptchaUsed = false
        showCaptcha = true
    }

    private func performLogin(captcha: String) async {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await loginWithRetry(user: user, password: password, captcha: captcha)
            await MainActor.run {
                // 服务端未返回用户名时回退到用户输入值，与 Android 端一致
                let resolved = result.username.isEmpty ? user : result.username
                session.saveSession(
                    UserResult(token: result.token, username: resolved, email: result.email, isAdmin: result.isAdmin)
                )
                reset()
            }
        } catch {
            await MainActor.run { handleLoginFailure(error, user: user) }
        }
    }

    /// 对应 Android 端 `LoginActivity.loginWithRetry`：
    /// 最多尝试 3 次，普通异常按 1s/2s 退避重试；ApiException（含人机验证）立即抛出。
    private func loginWithRetry(user: String, password: String, captcha: String) async throws -> UserResult {
        var attempt = 1
        var last: Error = ApiError.transport(message: L10n.loginFailed)
        while attempt < 4 {
            do {
                return try await session.api.login(username: user, password: password, captchaToken: captcha)
            } catch let error as ApiError {
                throw error
            } catch {
                last = error
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
            attempt += 1
        }
        throw last
    }

    /// 服务端要求重新人机验证时，自动重新拉起一次验证窗口；否则展示错误。
    private func handleLoginFailure(_ error: Error, user: String) {
        let apiError = error as? ApiError
        if apiError?.requiresCaptchaRetry == true, !recaptchaUsed {
            recaptchaUsed = true
            message = L10n.captchaExpired
            captchaToken = nil
            captchaError = nil
            captchaHeight = 78
            captchaAttempt = UUID()
            showCaptcha = true
            return
        }
        let reason = apiError?.errorDescription ?? error.localizedDescription
        message = "\(L10n.loginFailed): \(reason)"
        reset()
    }

    private func openRegister() {
        var address = session.server.trimmingCharacters(in: .whitespacesAndNewlines)
        while address.hasSuffix("/") { address.removeLast() }
        if let url = URL(string: address + "/register") {
            UIApplication.shared.open(url)
        }
    }

    private func reset() {
        busy = false
    }
}