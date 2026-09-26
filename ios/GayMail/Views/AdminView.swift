import SwiftUI

// MARK: - 管理面板容器

/// 管理面板，对应 Android 端 `org.mort.gaymail.admin.AdminActivity`。
/// 使用 Picker(.segmented) 点选切换标签，**禁用横向滑动**，
/// 避免与内部 List 左滑删除的手势冲突。
struct AdminView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var selection: Int = 0

    var body: some View {
        Group {
            switch selection {
            case 0: StatsTab()
            case 1: UsersTab()
            case 2: MailsTab()
            case 3: IpTab()
            case 4: TextTab(kind: .announcement)
            case 5: TextTab(kind: .slogan)
            default: UpdatesTab()
            }
        }
        .navigationTitle(L10n.menuAdmin)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selection) {
                    Text(L10n.tabStats).tag(0)
                    Text(L10n.tabUsers).tag(1)
                    Text(L10n.tabMails).tag(2)
                    Text(L10n.tabIp).tag(3)
                    Text(L10n.tabAnns).tag(4)
                    Text(L10n.tabSlogans).tag(5)
                    Text(L10n.tabUpdates).tag(6)
                }
                .pickerStyle(.segmented)
                .fixedSize(horizontal: false, vertical: true)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: reloadCurrent) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    private func reloadCurrent() {
        NotificationCenter.default.post(name: .adminReload, object: selection)
    }
}

extension Notification.Name {
    static let adminReload = Notification.Name("adminReload")
}

// MARK: - 统计概览

private struct StatsTab: View {
    @EnvironmentObject private var session: SessionStore
    @State private var stats: AdminStats?
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if loading {
                    ProgressView().padding(.top, 40)
                } else if let errorMessage {
                    Text(errorMessage).foregroundColor(.gmDanger).padding()
                } else if let stats {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        statCard(title: L10n.statUsers, value: "\(stats.users)")
                        statCard(title: L10n.statMails, value: "\(stats.mails)")
                        statCard(title: L10n.statUnread, value: "\(stats.unread)")
                        statCard(title: L10n.statStorage, value: Formatters.humanBytes(stats.storageBytes))
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top, 16)
        }
        .background(Color.gmBackground.ignoresSafeArea())
        .refreshable { await load() }
        .task(id: "stats") { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .adminReload)) { note in
            if (note.object as? Int) == 0 { Task { await load() } }
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.gmText.opacity(0.7))
            Text(value).font(.title2.weight(.bold)).foregroundColor(.gmPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.gmSurface, in: RoundedRectangle(cornerRadius: 10))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            stats = try await session.api.adminStats()
            errorMessage = nil
        } catch {
            errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - 用户管理

private struct UsersTab: View {
    @EnvironmentObject private var session: SessionStore
    @State private var query = ""
    @State private var users: [AdminUser] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var pendingAction: AdminUser?

    var body: some View {
        VStack(spacing: 0) {
            searchField
            content
        }
        .background(Color.gmBackground.ignoresSafeArea())
        .refreshable { await reload() }
        .alert(item: $pendingAction) { user in
            Alert(title: Text(user.username), message: nil, primaryButton: .cancel(Text(L10n.deleteCancel)), secondaryButton: .default(Text(L10n.menuEdit)) {
                showActions(for: user)
            })
        }
        .task(id: "users") { await reload() }
        .task(id: query) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .adminReload)) { note in
            if (note.object as? Int) == 1 { Task { await reload() } }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.gmText.opacity(0.5))
            TextField(L10n.userSearchHint, text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(10)
        .background(Color.gmSurface, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if users.isEmpty && !loading {
            Text(errorMessage ?? L10n.emptyList).foregroundColor(errorMessage == nil ? .gmText.opacity(0.6) : .gmDanger).padding(32)
        } else {
            List {
                ForEach(users) { user in
                    userRow(user)
                        .onAppear {
                            if user.id == users.last?.id { Task { await loadMore() } }
                        }
                }
                if loading && !users.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            .listStyle(.plain)
        }
    }

    private func userRow(_ user: AdminUser) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(user.username).font(.body.weight(.medium))
                Spacer()
                if user.banned == 1 { Text("已封禁").font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(Color.gmDanger.opacity(0.15), in: Capsule()).foregroundColor(.gmDanger) }
                if user.isAdmin == 1 { Text("管理员").font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(Color.gmPrimary.opacity(0.15), in: Capsule()).foregroundColor(.gmPrimary) }
            }
            Text(user.email).font(.caption).foregroundColor(.gmText.opacity(0.7))
            HStack {
                Text(String(format: L10n.userMailsCountFormat, user.mailCount))
                Spacer()
                Text(user.createdAt).foregroundColor(.gmText.opacity(0.5))
            }
            .font(.caption2).foregroundColor(.gmText.opacity(0.7))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { showActions(for: user) }
    }

    private func showActions(for user: AdminUser) {
        Task { @MainActor in pendingAction = user }
    }

    private func reload() async {
        page = 1; hasMore = true; users = []
        await loadMore()
    }

    private func loadMore() async {
        guard !loading, hasMore else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await session.api.adminUsers(q: query, page: page)
            users.append(contentsOf: result.users)
            hasMore = result.users.count >= 20
            page += 1
            errorMessage = nil
        } catch {
            errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription
            hasMore = false
        }
    }
}

// MARK: - 邮件管理

private struct MailsTab: View {
    @EnvironmentObject private var session: SessionStore
    @State private var query = ""
    @State private var mails: [AdminMailRow] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            searchField
            content
        }
        .background(Color.gmBackground.ignoresSafeArea())
        .refreshable { await reload() }
        .task(id: "adminMails") { await reload() }
        .task(id: query) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .adminReload)) { note in
            if (note.object as? Int) == 2 { Task { await reload() } }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.gmText.opacity(0.5))
            TextField(L10n.searchHint, text: $query)
        }
        .padding(10)
        .background(Color.gmSurface, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if mails.isEmpty && !loading {
            Text(errorMessage ?? L10n.emptyList).foregroundColor(errorMessage == nil ? .gmText.opacity(0.6) : .gmDanger).padding(32)
        } else {
            List {
                ForEach(mails) { mail in
                    mailRow(mail)
                        .onAppear {
                            if mail.id == mails.last?.id { Task { await loadMore() } }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await delete(mail.id) } } label: { Label(L10n.menuDelete, systemImage: "trash") }
                        }
                }
                if loading && !mails.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            .listStyle(.plain)
        }
    }

    private func mailRow(_ mail: AdminMailRow) -> some View {
        NavigationLink {
            AdminMailDetailView(id: mail.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(mail.subject.isEmpty ? "(无主题)" : mail.subject).font(.body.weight(.medium)).lineLimit(1)
                    Spacer()
                    Text(Formatters.humanSize(mail.size)).font(.caption2).foregroundColor(.gmText.opacity(0.5))
                }
                HStack {
                    Text(mail.isOutgoing ? "→ \(mail.toEmail)" : "← \(mail.fromEmail)").lineLimit(1)
                    Spacer()
                    Text(mail.owner).font(.caption).foregroundColor(.gmText.opacity(0.6))
                }
                .font(.caption).foregroundColor(.gmText.opacity(0.7))
                Text(mail.receivedAt).font(.caption2).foregroundColor(.gmText.opacity(0.5))
            }
            .padding(.vertical, 2)
        }
    }

    private func reload() async { page = 1; hasMore = true; mails = []; await loadMore() }
    private func loadMore() async {
        guard !loading, hasMore else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await session.api.adminMails(q: query, page: page)
            mails.append(contentsOf: result.mails)
            hasMore = result.mails.count >= 20
            page += 1
            errorMessage = nil
        } catch {
            errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription
            hasMore = false
        }
    }
    private func delete(_ id: Int) async {
        do { try await session.api.adminMailDelete(id: id); mails.removeAll { $0.id == id } }
        catch { errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription }
    }
}

private struct AdminMailDetailView: View {
    let id: Int
    @EnvironmentObject private var session: SessionStore
    @State private var detail: AdminMailView?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(detail.item.subject.isEmpty ? "(无主题)" : detail.item.subject).font(.title3.weight(.bold))
                        HStack { Text("发件人").foregroundColor(.gmText.opacity(0.6)); Spacer(); Text(detail.item.fromEmail) }
                        HStack { Text("收件人").foregroundColor(.gmText.opacity(0.6)); Spacer(); Text(detail.item.toEmail) }
                        HStack { Text("所属用户").foregroundColor(.gmText.opacity(0.6)); Spacer(); Text(detail.item.owner) }
                        Divider()
                        if !detail.html.isEmpty {
                            HTMLContent(html: detail.html)
                                .frame(minHeight: 200)
                        } else {
                            Text(detail.body).textSelection(.enabled)
                        }
                    }
                    .padding()
                }
            } else if let errorMessage {
                Text(errorMessage).foregroundColor(.gmDanger).padding()
            } else {
                ProgressView()
            }
        }
        .navigationTitle("邮件详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do { detail = try await session.api.adminMailDetail(id: id) }
        catch { errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription }
    }
}

// MARK: - IP 黑名单

private struct IpTab: View {
    @EnvironmentObject private var session: SessionStore
    @State private var rows: [IpRow] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var showAdd = false
    @State private var pendingDelete: IpRow?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if rows.isEmpty && !loading {
                    Text(errorMessage ?? L10n.emptyList).foregroundColor(errorMessage == nil ? .gmText.opacity(0.6) : .gmDanger).padding(32)
                } else {
                    List {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.ip).font(.body.weight(.medium))
                                Text(Formatters.ipSubtitle(row)).font(.caption).foregroundColor(.gmText.opacity(0.7))
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { pendingDelete = row } label: { Label(L10n.menuDelete, systemImage: "trash") }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .refreshable { await load() }
            .task(id: "ip") { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .adminReload)) { note in
                if (note.object as? Int) == 3 { Task { await load() } }
            }

            Button { showAdd = true } label: {
                Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundColor(.white).frame(width: 52, height: 52).background(Color.gmPrimary, in: Circle()).shadow(radius: 4)
            }
            .padding(16)
        }
        .background(Color.gmBackground.ignoresSafeArea())
        .sheet(isPresented: $showAdd) { IpAddSheet { ip, reason in await addIp(ip: ip, reason: reason) } }
        .alert(L10n.ipDeleteConfirm, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button(L10n.menuDelete, role: .destructive) {
                if let row = pendingDelete { Task { await delete(row.id) } }
                pendingDelete = nil
            }
            Button(L10n.deleteCancel, role: .cancel) { pendingDelete = nil }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { rows = try await session.api.ipList(); errorMessage = nil }
        catch { errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription }
    }
    private func addIp(ip: String, reason: String?) async {
        do { _ = try await session.api.ipAdd(ip: ip, reason: reason); await load() }
        catch { errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription }
    }
    private func delete(_ id: Int) async {
        do { try await session.api.ipDelete(id: id); rows.removeAll { $0.id == id } }
        catch { errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription }
    }
}

private struct IpAddSheet: View {
    let onAdd: (String, String?) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ip = ""
    @State private var reason = ""
    @State private var working = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(L10n.ipHint, text: $ip).keyboardType(.numbersAndPunctuation)
                    TextField(L10n.ipReasonHint, text: $reason)
                }
            }
            .navigationTitle(L10n.ipAddTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.deleteCancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.ipAddTitle) { Task { await submit() } }.disabled(ip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
                }
            }
        }
    }

    private func submit() async {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonTrimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        working = true
        await onAdd(trimmed, reasonTrimmed.isEmpty ? nil : reasonTrimmed)
        working = false
        dismiss()
    }
}

// MARK: - 公告 / 标语 通用

private struct TextTab: View {
    let kind: TextKind
    @EnvironmentObject private var session: SessionStore
    @State private var rows: [TextRow] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var editing: TextRow?
    @State private var creating = false

    enum TextKind { case announcement, slogan }
    var title: String { kind == .announcement ? L10n.tabAnns : L10n.tabSlogans }
    var newTitle: String { kind == .announcement ? L10n.annNew : L10n.sloganNew }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if rows.isEmpty && !loading {
                    Text(errorMessage ?? L10n.emptyList).foregroundColor(errorMessage == nil ? .gmText.opacity(0.6) : .gmDanger).padding(32)
                } else {
                    List {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.content).font(.body).lineLimit(3)
                                Text(Formatters.announcementSubtitle(row)).font(.caption2).foregroundColor(.gmText.opacity(0.5))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editing = row }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Task { await delete(row.id) } } label: { Label(L10n.menuDelete, systemImage: "trash") }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .refreshable { await load() }
            .task(id: "\(kind)") { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .adminReload)) { note in
                let target = kind == .announcement ? 4 : 5
                if (note.object as? Int) == target { Task { await load() } }
            }

            Button { creating = true } label: {
                Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundColor(.white).frame(width: 52, height: 52).background(Color.gmPrimary, in: Circle()).shadow(radius: 4)
            }
            .padding(16)
        }
        .background(Color.gmBackground.ignoresSafeArea())
        .sheet(item: $editing) { row in
            TextEditSheet(kind: kind, existing: row) { content in await save(id: row.id, content: content) }
        }
        .sheet(isPresented: $creating) {
            TextEditSheet(kind: kind, existing: nil) { content in await create(content: content) }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            rows = kind == .announcement ? try await session.api.annList() : try await session.api.sloganList()
            errorMessage = nil
        } catch { errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription }
    }
    private func create(content: String) async {
        do {
            if kind == .announcement { _ = try await session.api.annCreate(content: content) }
            else { _ = try await session.api.sloganCreate(content: content) }
            await load()
        } catch { errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription }
    }
    private func save(id: Int, content: String) async {
        do {
            if kind == .announcement { try await session.api.annUpdate(id: id, content: content) }
            else { try await session.api.sloganUpdate(id: id, content: content) }
            await load()
        } catch { errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription }
    }
    private func delete(_ id: Int) async {
        do {
            if kind == .announcement { try await session.api.annDelete(id: id) }
            else { try await session.api.sloganDelete(id: id) }
            rows.removeAll { $0.id == id }
        } catch { errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription }
    }
}

private struct TextEditSheet: View {
    let kind: TextTab.TextKind
    let existing: TextRow?
    let onSave: (String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    @State private var working = false

    init(kind: TextTab.TextKind, existing: TextRow?, onSave: @escaping (String) async -> Void) {
        self.kind = kind; self.existing = existing; self.onSave = onSave
        _content = State(initialValue: existing?.content ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 140)
                } footer: {
                    if kind == .slogan {
                        Text("最多 200 字（\(content.count)/200）").foregroundColor(.gmText.opacity(0.5))
                    }
                }
            }
            .navigationTitle(existing == nil ? (kind == .announcement ? L10n.annNew : L10n.sloganNew) : (kind == .announcement ? L10n.annEdit : L10n.sloganEdit))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.deleteCancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await submit() } }.disabled(working || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func submit() async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        if kind == .slogan && trimmed.count > 200 { return }
        working = true
        await onSave(trimmed)
        working = false
        dismiss()
    }
}

// MARK: - 更新管理

private struct UpdatesTab: View {
    @EnvironmentObject private var session: SessionStore
    @State private var updates: [AppUpdate] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var editing: AppUpdate?
    @State private var creating = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if updates.isEmpty && !loading {
                    Text(errorMessage ?? L10n.emptyList).foregroundColor(errorMessage == nil ? .gmText.opacity(0.6) : .gmDanger).padding(32)
                } else {
                    List {
                        ForEach(updates) { update in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("v\(update.version)").font(.body.weight(.medium))
                                Text(Formatters.updateSubtitle(update)).font(.caption).foregroundColor(.gmText.opacity(0.7))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editing = update }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Task { await delete(update.id) } } label: { Label(L10n.menuDelete, systemImage: "trash") }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .refreshable { await load() }
            .task(id: "updates") { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .adminReload)) { note in
                if (note.object as? Int) == 6 { Task { await load() } }
            }

            Button { creating = true } label: {
                Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundColor(.white).frame(width: 52, height: 52).background(Color.gmPrimary, in: Circle()).shadow(radius: 4)
            }
            .padding(16)
        }
        .background(Color.gmBackground.ignoresSafeArea())
        .sheet(item: $editing) { update in
            UpdateEditSheet(existing: update) { version, content, link in await save(id: update.id, version: version, content: content, link: link) }
        }
        .sheet(isPresented: $creating) {
            UpdateEditSheet(existing: nil) { version, content, link in await create(version: version, content: content, link: link) }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { updates = try await session.api.adminUpdates(); errorMessage = nil }
        catch { errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription }
    }
    private func create(version: String, content: String, link: String) async {
        do { _ = try await session.api.updateCreate(version: version, content: content, link: link); await load() }
        catch { errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription }
    }
    private func save(id: Int, version: String, content: String, link: String) async {
        do { try await session.api.updatePatch(id: id, version: version, content: content, link: link); await load() }
        catch { errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription }
    }
    private func delete(_ id: Int) async {
        do { try await session.api.updateDelete(id: id); updates.removeAll { $0.id == id } }
        catch { errorMessage = (error as? ApiError)?.errorDescription ?? error.localizedDescription }
    }
}

private struct UpdateEditSheet: View {
    let existing: AppUpdate?
    let onSave: (String, String, String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var version: String
    @State private var content: String
    @State private var link: String
    @State private var working = false

    init(existing: AppUpdate?, onSave: @escaping (String, String, String) async -> Void) {
        self.existing = existing; self.onSave = onSave
        _version = State(initialValue: existing?.version ?? "")
        _content = State(initialValue: existing?.content ?? "")
        _link = State(initialValue: existing?.link ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(L10n.updateHintVersion, text: $version)
                    TextField(L10n.updateHintLink, text: $link).keyboardType(.URL)
                }
                Section(L10n.updateHintContent) {
                    TextEditor(text: $content).frame(minHeight: 120)
                }
            }
            .navigationTitle(existing == nil ? L10n.updatePublish : L10n.updateEdit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.deleteCancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? L10n.updatePublish : "好") { Task { await submit() } }.disabled(working)
                }
            }
        }
    }

    private func submit() async {
        let ver = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ver.isEmpty else { return }
        if !l.isEmpty && !l.hasPrefix("http") { return }
        working = true
        await onSave(ver, c, l)
        working = false
        dismiss()
    }
}

// MARK: - HTML 正文占位（复用 MailDetailView 的实现）

private struct HTMLContent: UIViewRepresentable {
    let html: String
    func makeUIView(context: Context) -> UIView {
        let label = UILabel()
        label.numberOfLines = 0
        label.text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return label
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
