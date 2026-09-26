import SwiftUI
import WebKit

/// 通过 WKWebView 承载 hCaptcha JS 组件，并把校验令牌回传给 Swift。
///
/// Android 端使用 `com.hcaptcha.sdk` 原生 SDK，站点密钥相同；
/// iOS 端使用官方 JS API（`https://js.hcaptcha.com/1/api.js`），无需第三方依赖。
struct HCaptchaView: UIViewRepresentable {
    let siteKey: String
    /// 校验成功后的令牌
    @Binding var token: String?
    /// 校验失败原因
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(token: $token, errorMessage: $errorMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.loadHTMLString(Self.html(siteKey: siteKey), baseURL: URL(string: "https://js.hcaptcha.com"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageName)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let messageName = "hcaptcha"

        private let token: Binding<String?>
        private let errorMessage: Binding<String?>

        init(token: Binding<String?>, errorMessage: Binding<String?>) {
            self.token = token
            self.errorMessage = errorMessage
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if let value = body["token"] as? String, !value.isEmpty {
                DispatchQueue.main.async {
                    self.token.wrappedValue = value
                    self.errorMessage.wrappedValue = nil
                }
            } else if let error = body["error"] as? String {
                DispatchQueue.main.async {
                    self.errorMessage.wrappedValue = error
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.errorMessage.wrappedValue = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.errorMessage.wrappedValue = error.localizedDescription
            }
        }
    }

    private static func html(siteKey: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <script src="https://js.hcaptcha.com/1/api.js" async defer></script>
        <style>
            html, body { margin: 0; padding: 0; background: transparent; }
            body { display: flex; justify-content: center; align-items: center; }
        </style>
        </head>
        <body>
        <div class="h-captcha" data-sitekey="\(siteKey)" data-callback="onCaptchaSuccess" data-error-callback="onCaptchaError"></div>
        <script>
            function onCaptchaSuccess(token) {
                window.webkit.messageHandlers.hcaptcha.postMessage({ token: token });
            }
            function onCaptchaError(error) {
                window.webkit.messageHandlers.hcaptcha.postMessage({ error: String(error) });
            }
        </script>
        </body>
        </html>
        """
    }
}