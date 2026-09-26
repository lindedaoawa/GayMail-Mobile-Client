import SwiftUI

/// 邮件详情，对应 Android 端 `org.mort.gaymail.DetailActivity`。
struct MailDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let mailID: Int
    let box: String

    @State private var detail: MailDetail?
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false
    @State private var shareItem: ShareItem?
    @State private var compose: ComposeSeed?

    private struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.top, 40)
                } else if let detail {
                    header(detail)
                    Divider()
                    bodyView(detail)
                    if !detail.attachments.isEmpty {
                        attachments(detail)
                    }
                } else {
                    Text(errorMessage ?? L10n.loadFailed)
                        .foregroundColor(Color.gmDanger)
                        .padding(.top, 40)
                }
            }
            .padding(16)
        }
        .background(Color.gmBackground.ignoresSafeArea())
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(L10n.menuReply) { reply() }
                    Button(L10n.menuForward) { forward() }
                    Button(L10n.menuDelete, role: .destructive) { showDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert(L10n.deleteConfirm, isPresented: $showDeleteConfirm) {
            Button(L10n.deleteOk, role: .destructive) { Task { await performDelete() } }
            Button(L10n.deleteCancel, role: .cancel) {}
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(item: $compose) { seed in
            ComposeView(seed: seed)
        }
        .task { await load() }
    }

    private var titleText: String {
        guard let subject = detail?.item.subject, !subject.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "(无主题)"
        }
        return subject
    }

    // MARK: - 子视图

    private func header(_ detail: MailDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleText)
                .font(.headline)
                .foregroundColor(Color.gmText)
            Text("\(L10n.detailFrom): \(detail.item.fromEmail)")
                .font(.caption)
                .foregroundColor(Color.gmText.opacity(0.8))
            Text("\(L10n.detailTo): \(detail.item.toEmail)")
                .font(.caption)
                .foregroundColor(Color.gmText.opacity(0.8))
            Text(detail.item.receivedAt)
                .font(.caption2)
                .foregroundColor(Color.gmText.opacity(0.6))
        }
    }

    private func bodyView(_ detail: MailDetail) -> some View {
        HTMLView(
            html: HTMLView.document(for: detail),
            baseURLString: session.server
        )
        .frame(minHeight: 240)
    }

    private func attachments(_ detail: MailDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.composeAttachments)
                .font(.subheadline.bold())
                .foregroundColor(Color.gmText)
            ForEach(detail.attachments) { attachment in
                HStack {
                    Image(systemName: "paperclip")
                        .foregroundColor(Color.gmPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.footnote)
                            .lineLimit(1)
                        Text(Formatters.humanSize(attachment.size))
                            .font(.caption2)
                            .foregroundColor(Color.gmText.opacity(0.6))
                    }
                    Spacer()
                    Button("保存") { save(attachment) }
                        .font(.footnote)
                        .foregroundColor(Color.gmPrimary)
                }
                .padding(10)
                .background(Color.gmSurface)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - 行为

    private func load() async {
        do {
            let value = try await session.api.detail(id: mailID)
            await MainActor.run {
                detail = value
                loading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription
                loading = false
            }
        }
    }

    private func performDelete() async {
        do {
            try await session.api.delete(id: mailID)
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run {
                errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// 把附件（Base64）写入临时文件后弹出分享面板，等价于 Android 端的
    /// `ACTION_CREATE_DOCUMENT` 保存流程。
    private func save(_ attachment: Attachment) {
        guard let data = Data(base64Encoded: attachment.data, options: .ignoreUnknownCharacters) else {
            errorMessage = "附件内容解码失败"
            return
        }
        let directory = FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent(attachment.filename)
        do {
            try? FileManager.default.removeItem(at: url)
            try data.write(to: url)
            shareItem = ShareItem(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reply() {
        guard let detail else { return }
        let item = detail.item
        let to = item.isOutgoing ? item.toEmail : item.fromEmail
        let subject = item.subject.hasPrefix("Re:") ? item.subject : "Re: \(item.subject)"
        compose = ComposeSeed(to: to, subject: subject, body: "\n\n--- 原始邮件 ---\n" + detail.body)
    }

    private func forward() {
        guard let detail else { return }
        let item = detail.item
        let subject = item.subject.hasPrefix("Fwd:") ? item.subject : "Fwd: \(item.subject)"
        let body = "\n\n--- 转发邮件 ---\nFrom: \(item.fromEmail)\nSubject: \(item.subject)\n\n" + detail.body
        compose = ComposeSeed(to: "", subject: subject, body: body)
    }
}