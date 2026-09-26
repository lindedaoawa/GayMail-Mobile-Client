import XCTest
@testable import GayMail

/// 拦截 URLSession 请求，便于在无网络环境下验证请求构造与响应解析。
final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lastRequest = request
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// `URLSession` 会以 stream 形式传递请求体，这里统一还原成 Data。
    static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

final class ApiClientTests: XCTestCase {
    private var client: ApiClient!

    override func setUp() {
        super.setUp()
        client = ApiClient(session: StubURLProtocol.makeSession())
        client.baseURL = ApiClient.defaultBaseURL
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
        client = nil
        super.tearDown()
    }

    private func respond(_ json: String, status: Int = 200) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }
    }

    // MARK: - 常量

    func testConstantsMatchAndroidClient() {
        XCTAssertEqual(ApiClient.defaultBaseURL, "https://mail.mort.gay")
        XCTAssertEqual(ApiClient.hcaptchaSiteKey, "92463c0a-aed2-466e-860e-e17eee882910")
    }

    // MARK: - 登录

    func testLoginSendsBearerlessRequestAndParsesUser() async throws {
        respond(#"{"token":"tok-123","user":{"username":"alice","email":"a@mort.gay"}}"#)

        let result = try await client.login(username: "alice", password: "secret", captchaToken: "cap")

        XCTAssertEqual(result.token, "tok-123")
        XCTAssertEqual(result.username, "alice")
        XCTAssertEqual(result.email, "a@mort.gay")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://mail.mort.gay/api/login")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let body = try XCTUnwrap(StubURLProtocol.body(of: request))
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["username"] as? String, "alice")
        XCTAssertEqual(payload["password"] as? String, "secret")
        XCTAssertEqual(payload["hcaptchaToken"] as? String, "cap")
    }

    func testLoginOmitsEmptyCaptchaToken() async throws {
        respond(#"{"token":"t","user":{}}"#)

        _ = try await client.login(username: "u", password: "p", captchaToken: "")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        let body = try XCTUnwrap(StubURLProtocol.body(of: request))
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(payload["hcaptchaToken"])
    }

    // MARK: - 邮件列表

    func testListBuildsQueryAndParsesPage() async throws {
        client.token = "tok"
        respond(#"""
        {"mails":[{"id":7,"direction":"in","from_email":"x@a.com","to_email":"me@mort.gay",
        "subject":"hi","received_at":"2026-01-01 10:00","is_read":0,"size":2048}],
        "total":1,"unread":1}
        """#)

        let page = try await client.list(box: .inbox, page: 2, perPage: 50)

        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.unread, 1)
        XCTAssertEqual(page.mails.count, 1)
        XCTAssertEqual(page.mails[0].id, 7)
        XCTAssertTrue(page.mails[0].isUnread)
        XCTAssertFalse(page.mails[0].isOutgoing)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://mail.mort.gay/api/mail?box=in&page=2&per_page=50"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func testListUsesSentBoxRawValue() async throws {
        respond(#"{"mails":[],"total":0,"unread":0}"#)
        _ = try await client.list(box: .sent, page: 1)
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.query, "box=out&page=1&per_page=50")
    }

    // MARK: - 详情

    func testDetailParsesAttachmentsAndFallsBackToBodyHtml() async throws {
        respond(#"""
        {"mail":{"id":3,"direction":"in","from_email":"a@b.c","to_email":"me@mort.gay",
        "subject":"s","received_at":"now","is_read":1,"size":10,
        "body":"plain","body_html":"<p>rich</p>",
        "attachments":[{"id":9,"filename":"a.pdf","mime_type":"application/pdf","size":1234,"data":"QUJD"}]}}
        """#)

        let detail = try await client.detail(id: 3)

        XCTAssertEqual(detail.body, "plain")
        XCTAssertEqual(detail.html, "<p>rich</p>")
        XCTAssertEqual(detail.attachments.count, 1)
        XCTAssertEqual(detail.attachments[0].filename, "a.pdf")
        XCTAssertEqual(detail.attachments[0].size, 1234)
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/api/mail/3")
    }

    func testDetailDefaultsMissingAttachmentFields() async throws {
        respond(#"{"mail":{"id":1,"attachments":[{}]}}"#)

        let detail = try await client.detail(id: 1)

        XCTAssertEqual(detail.attachments[0].filename, "attachment")
        XCTAssertEqual(detail.attachments[0].mimeType, "application/octet-stream")
    }

    // MARK: - 删除 / 配额 / 发送

    func testDeleteUsesDeleteMethodWithoutBody() async throws {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }

        try await client.delete(id: 42)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/mail/42")
    }

    func testQuotaParsing() async throws {
        respond(#"{"quota":{"limit":100,"used":40,"remaining":60}}"#)

        let quota = try await client.quota()

        XCTAssertEqual(quota.limit, 100)
        XCTAssertEqual(quota.used, 40)
        XCTAssertEqual(quota.remaining, 60)
    }

    func testSendBuildsAttachmentsPayload() async throws {
        respond("{}")
        let attachment = OutAttachment(filename: "a.txt", mimeType: "text/plain", size: 3, data: "QUJD")

        try await client.send(
            to: "b@c.d",
            subject: "s",
            body: "b",
            html: "<p>b</p>",
            attachments: [attachment],
            captchaToken: "cap"
        )

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/send2")
        let body = try XCTUnwrap(StubURLProtocol.body(of: request))
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["to"] as? String, "b@c.d")
        XCTAssertEqual(payload["html"] as? String, "<p>b</p>")
        XCTAssertEqual(payload["hcaptchaToken"] as? String, "cap")

        let attachments = try XCTUnwrap(payload["attachments"] as? [[String: Any]])
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments[0]["filename"] as? String, "a.txt")
        XCTAssertEqual(attachments[0]["content"] as? String, "QUJD")
        XCTAssertEqual(attachments[0]["mime_type"] as? String, "text/plain")
    }

    // MARK: - 错误

    func testHttpErrorSurfacesServerMessage() async throws {
        respond(#"{"error":"请输入用户名/邮箱和密码"}"#, status: 400)

        do {
            _ = try await client.login(username: "u", password: "p", captchaToken: nil)
            XCTFail("应当抛出错误")
        } catch let error as ApiError {
            XCTAssertEqual(error.errorDescription, "请输入用户名/邮箱和密码")
            XCTAssertFalse(error.needCaptcha)
        }
    }

    func testHttpErrorDetectsCaptchaRequirement() async throws {
        respond(#"{"error":"请完成人机验证"}"#, status: 403)

        do {
            _ = try await client.login(username: "u", password: "p", captchaToken: nil)
            XCTFail("应当抛出错误")
        } catch let error as ApiError {
            XCTAssertTrue(error.needCaptcha)
        }
    }

    func testBaseURLTrailingSlashIsTrimmed() async throws {
        client.baseURL = "https://mail.mort.gay/"
        respond(#"{"quota":{}}"#)

        _ = try await client.quota()

        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.absoluteString, "https://mail.mort.gay/api/quota")
    }
}