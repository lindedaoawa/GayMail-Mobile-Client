import SwiftUI
import UniformTypeIdentifiers

/// 撰写邮件时用于预填内容的种子值（回复 / 转发）。
struct ComposeSeed: Identifiable {
    let id = UUID()
    let to: String
    let subject: String
    let body: String
}

/// 写邮件页，对应 Android 端 `org.mort.gaymail.ComposeActivity`。
struct ComposeView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var seed: ComposeSeed?

    @State private var to = ""
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var attachments: [OutAttachment] = []

    @State private var sending = false
    @State private var message: String?
    @State private var toError = false
    @State private var showFileImporter = false

    @State private var captchaToken: String?
    @State private var captchaError: String?
    @State private var captchaAttempt = UUID()
    @State private var showCaptcha = false
    @State private var captchaHeight: CGFloat = 78

    private static let maxAttachmentBytes = 16 * 1024 * 1024

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(L10n.composeTo, text: $to)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    TextField(L10n.composeSubject, text: $subject)
                }
                Section(header: Text(L10n.composeBody)) {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 180)
                }
                Section {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label(L10n.menuAttach, systemImage: "paperclip")
                    }
                    ForEach(attachments) { attachment in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attachment.filename)
                                    .font(.footnote)
                                    .lineLimit(1)
                                Text(Formatters.humanSize(attachment.size))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                attachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(Color.gmDanger)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(Color.gmDanger)
                    }
                } header: {
                    Text(L10n.composeAttachments)
                }
            }
            .navigationTitle(L10n.appName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.deleteCancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button(L10n.menuSend) { startSend() }
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showCaptcha) { captchaSheet }
            .onAppear(perform: applySeed)
        }
        .navigationViewStyle(.stack)
    }

    private var captchaSheet: some View {
        VStack(spacing: 16) {
            Text(L10n.loginCaptcha).font(.headline)
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
                sending = false
            }
            .foregroundColor(Color.gmText)
        }
        .padding(24)
        .onChange(of: captchaToken) { token in
            guard let token, !token.isEmpty else { return }
            showCaptcha = false
            Task { await performSend(captcha: token) }
        }
    }

    // MARK: - 行为

    private func applySeed() {
        guard let seed else { return }
        if to.isEmpty { to = seed.to }
        if subject.isEmpty { subject = seed.subject }
        if bodyText.isEmpty { bodyText = seed.body }
    }

    private func startSend() {
        guard !sending else { return }
        message = nil
        toError = false

        let recipient = to.trimmingCharacters(in: .whitespaces)
        guard !recipient.isEmpty else {
            toError = true
            message = L10n.composeTo
            return
        }

        sending = true
        captchaToken = nil
        captchaError = nil
        captchaHeight = 78
        captchaAttempt = UUID()
        showCaptcha = true
    }

    private func performSend(captcha: String) async {
        let recipient = to.trimmingCharacters(in: .whitespaces)
        let title = subject.trimmingCharacters(in: .whitespaces)
        do {
            try await session.api.send(
                to: recipient,
                subject: title,
                body: bodyText,
                attachments: attachments,
                captchaToken: captcha
            )
            await MainActor.run {
                sending = false
                dismiss()
            }
        } catch {
            let reason = (error as? ApiError)?.errorDescription ?? error.localizedDescription
            await MainActor.run {
                message = reason
                sending = false
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            for url in urls { appendAttachment(from: url) }
        case let .failure(error):
            message = error.localizedDescription
        }
    }

    /// 读取文件并转成 Base64，超过 16MB 时拒绝，等价于 Android 端 `addAttachment`。
    private func appendAttachment(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maxAttachmentBytes else {
                message = L10n.attachmentTooLarge
                return
            }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            attachments.append(
                OutAttachment(
                    filename: url.lastPathComponent,
                    mimeType: mime,
                    size: Int64(data.count),
                    data: data.base64EncodedString()
                )
            )
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}