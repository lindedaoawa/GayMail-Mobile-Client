import XCTest
@testable import GayMail

final class ApiErrorTests: XCTestCase {
    func testFallsBackToStatusCodeWhenBodyIsEmpty() {
        let error = ApiError.from(statusCode: 500, body: "")
        XCTAssertEqual(error.errorDescription, "HTTP 500")
        XCTAssertFalse(error.needCaptcha)
    }

    func testParsesErrorAndNeedCaptchaFlags() {
        let error = ApiError.from(statusCode: 403, body: #"{"error":"需要验证","needCaptcha":true}"#)
        XCTAssertEqual(error.errorDescription, "需要验证")
        XCTAssertTrue(error.needCaptcha)
    }

    /// Android 端在错误文案包含「人机验证」时也会标记需要验证码。
    func testChineseCaptchaKeywordForcesFlag() {
        let error = ApiError.from(statusCode: 403, body: #"{"error":"请先通过人机验证"}"#)
        XCTAssertTrue(error.needCaptcha)
    }

    func testTruncatesNonJsonBodyTo200Characters() {
        let body = String(repeating: "x", count: 500)
        let error = ApiError.from(statusCode: 502, body: body)
        XCTAssertEqual(error.errorDescription?.count, 200)
    }
}

final class FormattersTests: XCTestCase {
    func testHumanSizeMirrorsAndroidFormatting() {
        XCTAssertEqual(Formatters.humanSize(0), "0 B")
        XCTAssertEqual(Formatters.humanSize(1023), "1023 B")
        XCTAssertEqual(Formatters.humanSize(1024), "1.0 KB")
        XCTAssertEqual(Formatters.humanSize(1_048_576), "1.0 MB")
        XCTAssertEqual(Formatters.humanSize(2_621_440), "2.5 MB")
    }
}

final class HTMLViewTests: XCTestCase {
    func testEscapeNeutralizesMarkup() {
        XCTAssertEqual(
            HTMLView.escape("<script>alert(\"x\")&'</script>"),
            "&lt;script&gt;alert(&quot;x&quot;)&amp;&#39;&lt;/script&gt;"
        )
    }

    func testDocumentPrefersServerProvidedHTML() {
        let detail = MailDetail(
            item: makeItem(),
            body: "plain",
            html: "<p>rich</p>",
            attachments: []
        )
        let document = HTMLView.document(for: detail)
        // 正文保留服务端 HTML，同时注入 viewport 与移动端适配样式
        XCTAssertTrue(document.contains("<p>rich</p>"))
        XCTAssertTrue(document.contains("name=\"viewport\""))
        XCTAssertTrue(document.contains("-webkit-text-size-adjust"))
    }

    func testDocumentKeepsExistingViewport() {
        let detail = MailDetail(
            item: makeItem(),
            body: "",
            html: "<html><head><meta name=\"viewport\" content=\"width=640\"></head><body>x</body></html>",
            attachments: []
        )
        let document = HTMLView.document(for: detail)
        // 已有 viewport 时不重复注入
        XCTAssertEqual(document.components(separatedBy: "name=\"viewport\"").count - 1, 1)
        XCTAssertTrue(document.contains("content=\"width=640\""))
    }

    func testDocumentWrapsFragmentWithoutHTMLTag() {
        let detail = MailDetail(
            item: makeItem(),
            body: "",
            html: "<p>fragment</p>",
            attachments: []
        )
        let document = HTMLView.document(for: detail)
        XCTAssertTrue(document.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(document.contains("<p>fragment</p>"))
        XCTAssertTrue(document.contains("name=\"viewport\""))
    }

    func testDocumentWrapsPlainTextInEscapedPre() {
        let detail = MailDetail(
            item: makeItem(),
            body: "<b>hi</b>",
            html: "  ",
            attachments: []
        )
        let document = HTMLView.document(for: detail)
        XCTAssertTrue(document.contains("<pre>&lt;b&gt;hi&lt;/b&gt;</pre>"))
        XCTAssertFalse(document.contains("<b>hi</b>"))
    }

    private func makeItem() -> MailItem {
        MailItem(
            id: 1,
            direction: "in",
            fromEmail: "a@b.c",
            toEmail: "d@e.f",
            subject: "s",
            receivedAt: "now",
            isRead: 1,
            size: 0
        )
    }
}

final class MailItemTests: XCTestCase {
    func testDirectionFlags() {
        let incoming = MailItem(id: 1, direction: "in", fromEmail: "", toEmail: "", subject: "", receivedAt: "", isRead: 0, size: 0)
        XCTAssertTrue(incoming.isUnread)
        XCTAssertFalse(incoming.isOutgoing)

        let outgoing = MailItem(id: 2, direction: "out", fromEmail: "", toEmail: "", subject: "", receivedAt: "", isRead: 1, size: 0)
        XCTAssertFalse(outgoing.isUnread)
        XCTAssertTrue(outgoing.isOutgoing)
    }

    func testBoxRawValuesMatchApiContract() {
        XCTAssertEqual(MailBox.inbox.rawValue, "in")
        XCTAssertEqual(MailBox.sent.rawValue, "out")
    }
}