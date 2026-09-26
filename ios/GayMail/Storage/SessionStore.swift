import Foundation

/// 全局会话状态，对应 Android 端 `GayMailApp` + `SharedPreferences`。
///
/// 负责令牌 / 用户名 / 邮箱 / 服务器地址的持久化，并同步给 `ApiClient`。
final class SessionStore: ObservableObject {
    private enum Key {
        static let token = "token"
        static let username = "username"
        static let email = "email"
        static let server = "server"
        static let prefs = "gaymail"
    }

    @Published private(set) var isLoggedIn: Bool
    @Published private(set) var username: String
    @Published private(set) var email: String

    let api: ApiClient
    private let defaults: UserDefaults

    init(api: ApiClient = ApiClient(), defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults

        let server = defaults.string(forKey: Key.server) ?? ApiClient.defaultBaseURL
        let token = KeychainStore.get(Key.token)
        let storedUsername = defaults.string(forKey: Key.username) ?? ""

        api.baseURL = server
        api.token = token

        self.username = storedUsername
        self.email = defaults.string(forKey: Key.email) ?? ""
        self.isLoggedIn = !(token ?? "").isEmpty && !storedUsername.isEmpty
    }

    var server: String {
        api.baseURL
    }

    func saveSession(_ result: UserResult) {
        KeychainStore.set(result.token, for: Key.token)
        defaults.set(result.username, forKey: Key.username)
        defaults.set(result.email, forKey: Key.email)
        api.token = result.token
        username = result.username
        email = result.email
        isLoggedIn = true
    }

    func saveServer(_ server: String) {
        api.baseURL = server
        defaults.set(server, forKey: Key.server)
    }

    func logout() {
        KeychainStore.set(nil, for: Key.token)
        defaults.removeObject(forKey: Key.token)
        defaults.removeObject(forKey: Key.username)
        defaults.removeObject(forKey: Key.email)
        api.token = nil
        username = ""
        email = ""
        isLoggedIn = false
    }
}