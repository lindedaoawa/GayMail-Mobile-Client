import SwiftUI
import WebKit

/// 渲染邮件正文 HTML，对应 Android 端 `DetailActivity` 中的 WebView 配置：
/// 关闭 JavaScript 与 DOM 存储、以服务器地址作为 baseURL。
///
/// 两点与 Android 端表现对齐的处理：
/// 1. 服务端返回的 HTML 通常没有 `viewport`，WKWebView 会按桌面宽度（约 980px）排版后
///    整体缩小，导致正文变小、内容缩在中间。这里注入 viewport 与移动端适配样式。
/// 2. WebView 没有固有高度，在 ScrollView 中会被撑满整屏，正文下方出现大片留白。
///    因此把内容高度回传给 SwiftUI 自适应 `frame`。
struct HTMLView: UIViewRepresentable {
    let html: String
    let baseURLString: String
    /// 由 WebView 内容高度驱动的自适应高度
    @Binding var contentHeight: CGFloat
    /// 内容渲染完成后的回调，用于收起加载指示器
    var onFinish: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, contentHeight: $contentHeight)
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
        // 高度贴合内容，滚动交给外层 ScrollView，避免嵌套滚动
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.observeContentSize(of: webView)
        context.coordinator.load(html: html, baseURLString: baseURLString, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onFinish = onFinish
        context.coordinator.load(html: html, baseURLString: baseURLString, in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        /// 正文最少高度，避免内容为空时塌陷
        private static let minHeight: CGFloat = 120

        var onFinish: (() -> Void)?
        private let contentHeight: Binding<CGFloat>
        private var observation: NSKeyValueObservation?
        private var loadedHTML: String?

        init(onFinish: (() -> Void)?, contentHeight: Binding<CGFloat>) {
            self.onFinish = onFinish
            self.contentHeight = contentHeight
        }

        deinit { observation?.invalidate() }

        /// 只在 HTML 变化时重新加载，避免 SwiftUI 每次刷新都重载页面
        func load(html: String, baseURLString: String, in webView: WKWebView) {
            guard loadedHTML != html else { return }
            loadedHTML = html
            webView.loadHTMLString(html, baseURL: URL(string: baseURLString))
        }

        func observeContentSize(of webView: WKWebView) {
            observation = webView.scrollView.observe(\.contentSize, options: [.initial, .new]) { [weak self] scrollView, _ in
                let value = scrollView.contentSize.height
                DispatchQueue.main.async {
                    guard let self else { return }
                    let height = max(value, Self.minHeight)
                    // 变化小于 1pt 时忽略，避免 frame 与 contentSize 互相触发导致抖动
                    guard abs(height - self.contentHeight.wrappedValue) > 1 else { return }
                    self.contentHeight.wrappedValue = height
                }
            }
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
            return mobileFriendly(detail.html)
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

    /// 为服务端 HTML 注入 viewport 与移动端适配样式：
    /// 缺少 viewport 时页面会按桌面宽度排版再整体缩小，正文会变得很小。
    private static func mobileFriendly(_ html: String) -> String {
        let hasViewport = html.range(of: "name=\"viewport\"", options: .caseInsensitive) != nil
            || html.range(of: "name='viewport'", options: .caseInsensitive) != nil

        var injections = ""
        if !hasViewport {
            injections += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
        }
        injections += "<style>html{-webkit-text-size-adjust:100%;}img{max-width:100% !important;height:auto !important;}</style>"

        if let head = html.range(of: "<head>", options: .caseInsensitive) {
            var result = html
            result.insert(contentsOf: injections, at: head.upperBound)
            return result
        }
        if let htmlTag = html.range(of: "<html", options: .caseInsensitive),
           let close = html.range(of: ">", range: htmlTag.upperBound..<html.endIndex) {
            var result = html
            result.insert(contentsOf: "<head>\(injections)</head>", at: close.upperBound)
            return result
        }
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\">\(injections)</head><body>\(html)</body></html>"
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