import SwiftUI
import WebKit

/// 渲染邮件正文 HTML，对应 Android 端 `DetailActivity` 中的 WebView 配置：
/// 关闭 JavaScript 与 DOM 存储、支持缩放、以服务器地址作为 baseURL。
struct HTMLView: UIViewRepresentable {
    let html: String
    let baseURLString: String
    /// 内容渲染完成后的回调，用于收起加载指示器
    var onFinish: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.setContentHuggingPriority(.defaultLow, for: .vertical)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onFinish = onFinish
        webView.loadHTMLString(html, baseURL: URL(string: baseURLString))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onFinish: (() -> Void)?

        init(onFinish: (() -> Void)?) {
            self.onFinish = onFinish
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onFinish?()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onFinish?()
        }
    }

    /// 把纯文本正文包装成 HTML，等价于 Android 端的
    /// `Html.escapeHtml(body)` + `<pre style='white-space:pre-wrap'>`。
    static func document(for detail: MailDetail) -> String {
        if !detail.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return detail.html
        }
        let escaped = escape(detail.body)
        return """
        <html><head><meta charset="utf-8">\
        <meta name="viewport" content="width=device-width, initial-scale=1.0">\
        <style>body{margin:12px;background:#ffffff;color:#154963;}\
        pre{white-space:pre-wrap;word-break:break-word;font-family:-apple-system,sans-serif;font-size:15px;margin:0;}\
        </style></head>\
        <body><pre>\(escaped)</pre></body></html>
        """
    }

    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }
}