import SwiftUI

/// 邮件列表，对应 Android 端 `org.mort.gaymail.MainActivity`。
struct MailListView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var box: MailBox = .inbox
    @State private var mails: [MailItem] = []
    @State private var page = 1
    @State private var loading = false
    @State private var finished = false
    @State private var unread = 0
    @State private var total = 0
    @State private var errorMessage: String?

    @State private var showCompose = false
    @State private var showServerDialog = false
    @State private var showLogoutConfirm = false
    @State private var quota: Quota?
    @State private var showQuota = false
    @State private var serverDraft = ""
    @State private var pendingDelete: MailItem?

    private let perPage = 50

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                boxPicker
                content
            }
            .background(Color.gmBackground.ignoresSafeArea())
            .navigationTitle(L10n.appName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(L10n.menuQuota) { Task { await loadQuota() } }
                        Button(L10n.menuSettings) { openServerDialog() }
                        Button(L10n.menuLogout, role: .destructive) { showLogoutConfirm = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCompose = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showCompose) {
                ComposeView()
            }
            .sheet(isPresented: $showServerDialog) { serverSheet }
            .alert(L10n.menuQuota, isPresented: $showQuota, presenting: quota) { _ in
                Button("好", role: .cancel) {}
            } message: { quota in
                Text("已用 \(quota.used) / \(quota.limit)\n剩余 \(quota.remaining)")
            }
            .alert(L10n.logoutConfirm, isPresented: $showLogoutConfirm) {
                Button(L10n.menuLogout, role: .destructive) { session.logout() }
                Button(L10n.deleteCancel, role: .cancel) {}
            }
            .alert(L10n.deleteConfirm, isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )) {
                Button(L10n.deleteOk, role: .destructive) {
                    if let item = pendingDelete { Task { await performDelete(item) } }
                    pendingDelete = nil
                }
                Button(L10n.deleteCancel, role: .cancel) { pendingDelete = nil }
            }
        }
        .navigationViewStyle(.stack)
        .task { refresh() }
    }

    // MARK: - 子视图

    private var boxPicker: some View {
        Picker("", selection: $box) {
            ForEach(MailBox.allCases) { item in
                Text(title(for: item)).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: box) { _ in refresh() }
    }

    private var content: some View {
        ZStack {
            if mails.isEmpty && !loading {
                Text(errorMessage ?? L10n.emptyList)
                    .foregroundColor(errorMessage == nil ? Color.gmText.opacity(0.6) : Color.gmDanger)
                    .padding(32)
            } else {
                List {
                    ForEach(mails) { mail in
                        row(for: mail)
                            .onAppear {
                                if mail.id == mails.last?.id { loadMore() }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { pendingDelete = mail } label: {
                                    Label(L10n.menuDelete, systemImage: "trash")
                                }
                            }
                    }
                    if loading && !mails.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await load(reset: true) }
            }
        }
    }

    private func row(for mail: MailItem) -> some View {
        NavigationLink {
            MailDetailView(mailID: mail.id, box: box.rawValue)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if mail.isUnread && box == .inbox {
                        Circle().fill(Color.gmUnread).frame(width: 8, height: 8)
                    }
                    Text(mail.subject.isEmpty ? "(无主题)" : mail.subject)
                        .font(.system(size: 15, weight: mail.isUnread ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Formatters.humanSize(mail.size))
                        .font(.caption2)
                        .foregroundColor(Color.gmText.opacity(0.5))
                }
                Text(counterparty(for: mail))
                    .font(.caption)
                    .foregroundColor(Color.gmText.opacity(0.7))
                    .lineLimit(1)
                Text(mail.receivedAt)
                    .font(.caption2)
                    .foregroundColor(Color.gmText.opacity(0.5))
            }
            .padding(.vertical, 4)
        }
    }

    private var serverSheet: some View {
        NavigationView {
            Form {
                Section(header: Text(L10n.hintServer)) {
                    TextField(ApiClient.defaultBaseURL, text: $serverDraft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
            }
            .navigationTitle(L10n.menuSettings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.deleteCancel) { showServerDialog = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("好") {
                        var value = serverDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        while value.hasSuffix("/") { value.removeLast() }
                        guard value.hasPrefix("http") else {
                            errorMessage = L10n.serverInvalid
                            return
                        }
                        session.saveServer(value)
                        showServerDialog = false
                        refresh()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 行为

    private func title(for item: MailBox) -> String {
        item == .inbox && unread > 0 ? "\(item.title) (\(unread))" : item.title
    }

    private func counterparty(for mail: MailItem) -> String {
        mail.isOutgoing ? mail.toEmail : mail.fromEmail
    }

    private func refresh() {
        page = 1
        finished = false
        Task { await load(reset: true) }
    }

    private func loadMore() {
        guard !loading, !finished else { return }
        page += 1
        Task { await load(reset: false) }
    }

    private func load(reset: Bool) async {
        guard !loading else { return }
        if reset { mails = [] }
        loading = true
        do {
            let result = try await session.api.list(box: box, page: page, perPage: perPage)
            await MainActor.run {
                if reset {
                    mails = result.mails
                } else {
                    mails.append(contentsOf: result.mails)
                }
                total = result.total
                if box == .inbox { unread = result.unread }
                finished = result.mails.count < perPage
                errorMessage = nil
                loading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription
                finished = true
                loading = false
            }
        }
    }

    private func performDelete(_ mail: MailItem) async {
        do {
            try await session.api.delete(id: mail.id)
            await MainActor.run {
                mails.removeAll { $0.id == mail.id }
            }
        } catch {
            await MainActor.run {
                errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func loadQuota() async {
        do {
            let value = try await session.api.quota()
            await MainActor.run {
                quota = value
                showQuota = true
            }
        } catch {
            await MainActor.run {
                errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func openServerDialog() {
        serverDraft = session.server
        showServerDialog = true
    }
}