import SwiftUI

struct StoresView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedStore: StoreSummary?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                importCard
                if state.stores.isEmpty {
                    EmptyStateView(
                        symbol: "externaldrive.badge.questionmark",
                        title: "等待第一个数据库",
                        message: "导入 EOH/LOG xlsx 报表，或导入已有的 .ngbd 数据库文件。"
                    )
                    .surfaceCard(cornerRadius: 20)
                } else {
                    storeList
                }
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 96)
        }
        .sheet(item: $selectedStore) { store in
            StoreDetailSheet(storeID: store.storeID)
                .environmentObject(state)
        }
        .onAppear {
            #if DEBUG
            if DebugLaunchOptions.route == "store-detail" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    selectedStore = state.stores.first
                }
            }
            #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionKicker(text: "Local databases")
            Text("数据库")
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundColor(AppTheme.ink)
            Text("按 Store ID 分开存储，只允许对应商店的条目进入各自的 .ngbd 文件。")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(AppTheme.accentSoft)
                        .frame(width: 44, height: 44)
                    Image(systemName: SFSymbol.available("doc.badge.plus", fallback: "doc"))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("导入报表或数据库")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                    Text("选择 EOH/LOG xlsx，或导入已有的 .ngbd 数据库文件。xlsx 会按 Store ID 自动拆分。")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.secondary)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 7) {
                importHint("EOH", "现有库存")
                importHint("LOG", "销售记录")
                importHint(".ngbd", "数据库文件")
            }

            HStack(spacing: 9) {
                Button(action: { state.requestImport() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text("导入文件")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                Spacer()
            }

            LabelText(symbol: "square.and.arrow.up", text: "也可在“文件”、邮件等 App 的分享菜单中选择 GuestBook Helper 直接导入 xlsx 或 .ngbd。")
        }
        .padding(16)
        .surfaceCard(cornerRadius: 21)
    }

    private func importHint(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.ink)
            Text(subtitle)
                .font(.system(size: 8.5))
                .foregroundColor(AppTheme.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppTheme.surfaceMuted)
        )
    }

    private var storeList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已建立的数据库")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundColor(AppTheme.ink)
                Spacer()
                Text("\(state.stores.count) 个")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(AppTheme.tertiary)
            }

            ForEach(state.stores) { store in
                Button(action: { selectedStore = store }) {
                    StoreCard(store: store, isActive: store.storeID == state.activeStoreID)
                }
                .buttonStyle(PressableCardButtonStyle())
            }
        }
    }
}

struct LabelText: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: SFSymbol.available(symbol, fallback: "circle"))
                .font(.system(size: 10))
                .foregroundColor(AppTheme.tertiary)
                .frame(width: 12)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundColor(AppTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StoreCard: View {
    var store: StoreSummary
    var isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("STORE \(store.storeID)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(AppTheme.tertiary)
                        if isActive {
                            Text("当前")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(AppTheme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(AppTheme.accentSoft))
                        }
                    }
                    Text(store.fileName)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppTheme.ink)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.tertiary.opacity(0.7))
            }

            HStack(spacing: 16) {
                storeStat("在库", "\(store.stockCount)")
                storeStat("记录", "\(store.itemCount)")
                storeStat("已售", "\(store.soldCount)")
                storeStat("标签", "\(store.tagCount)")
                Spacer(minLength: 4)
                Text(store.fileSize.gbFileSize)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(AppTheme.tertiary)
            }

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                Text("最后导入 " + (store.lastImportAt.map { DateFormatter.gbDateTime.string(from: $0) } ?? "—"))
                    .font(.system(size: 9.5))
                Spacer()
            }
            .foregroundColor(AppTheme.tertiary)
        }
        .padding(15)
        .surfaceCard(cornerRadius: 18)
    }

    private func storeStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(AppTheme.ink)
            Text(label)
                .font(.system(size: 8.5))
                .foregroundColor(AppTheme.tertiary)
        }
    }
}

// MARK: - Store detail

private enum StoreDetailAlert: Identifiable {
    case delete
    case restore(DatabaseSnapshot)

    var id: String {
        switch self {
        case .delete: return "delete"
        case .restore(let snapshot): return "restore-\(snapshot.id)"
        }
    }
}

struct StoreDetailSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.presentationMode) private var presentationMode
    let storeID: String

    @State private var history: [ImportHistoryEntry] = []
    @State private var snapshots: [DatabaseSnapshot] = []
    @State private var showShare = false
    @State private var activeAlert: StoreDetailAlert?
    @State private var didLoad = false

    private var store: StoreSummary? {
        state.stores.first(where: { $0.storeID == storeID })
    }

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                if let store = store {
                    VStack(spacing: 16) {
                        hero(store)
                        stats(store)
                        actions(store)
                        snapshotsSection
                        importHistory
                        fileInfo(store)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                } else {
                    EmptyStateView(symbol: "externaldrive", title: "数据库不存在", message: "这个 .ngbd 文件可能已被删除。")
                }
            }
            .background(AppBackground().edgesIgnoringSafeArea(.all))
            .gbInlineTitle("数据库详情")
            .navigationBarItems(trailing: Button("完成") { presentationMode.wrappedValue.dismiss() })
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showShare) {
            if let url = store.map({ state.exportURL(for: $0.storeID) }) {
                ActivityView(activityItems: [url])
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .delete:
                return Alert(
                    title: Text("删除数据库？"),
                    message: Text("\(storeID).ngbd 及其中的标签、导入记录都会被永久删除。"),
                    primaryButton: .destructive(Text("删除")) {
                        state.deleteStore(storeID)
                        presentationMode.wrappedValue.dismiss()
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .restore(let snapshot):
                return Alert(
                    title: Text("恢复快照？"),
                    message: Text("当前数据库会先自动备份，然后恢复到 \(snapshot.reason) · \(DateFormatter.gbDateTime.string(from: snapshot.createdAt))。"),
                    primaryButton: .destructive(Text("恢复")) {
                        state.restoreSnapshot(snapshot)
                        loadHistory()
                        loadSnapshots()
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            loadHistory()
            loadSnapshots()
        }
    }

    private func hero(_ store: StoreSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    SectionKicker(text: "GuestBook database")
                    Text("Store \(store.storeID)")
                        .font(.system(size: 29, weight: .semibold, design: .serif))
                        .foregroundColor(AppTheme.ink)
                }
                Spacer()
                Image("BrandIcon")
                    .resizable()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 10))
                Text(store.fileName)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(AppTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(AppTheme.accentSoft))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .surfaceCard(cornerRadius: 21)
    }

    private func stats(_ store: StoreSummary) -> some View {
        HStack(spacing: 10) {
            summaryTile("可售库存", "\(store.stockCount)", AppTheme.success)
            summaryTile("全部记录", "\(store.itemCount)", AppTheme.ink)
            summaryTile("已售", "\(store.soldCount)", AppTheme.sold)
        }
    }

    private func summaryTile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 25, weight: .semibold, design: .serif))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundColor(AppTheme.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .surfaceCard(cornerRadius: 15)
    }

    private func actions(_ store: StoreSummary) -> some View {
        VStack(spacing: 9) {
            if store.storeID != state.activeStoreID {
                Button(action: {
                    state.selectStore(store.storeID)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle")
                        Text("设为当前商店")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            HStack(spacing: 9) {
                Button(action: { showShare = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("分享 .ngbd")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(QuietButtonStyle())

                Button(action: { activeAlert = .delete }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("删除")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(QuietButtonStyle(destructive: true))
            }
        }
    }

    private var snapshotsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("快照")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.ink)
                Text("最近 3 次更改")
                    .font(.system(size: 9.5))
                    .foregroundColor(AppTheme.tertiary)
                Spacer()
            }
            if snapshots.isEmpty {
                Text("还没有快照。导入报表、修改标签或合并数据库前会自动记录。")
                    .font(.system(size: 11.5))
                    .foregroundColor(AppTheme.tertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                        HStack(spacing: 9) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(snapshot.reason)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppTheme.ink)
                                Text(DateFormatter.gbDateTime.string(from: snapshot.createdAt))
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundColor(AppTheme.tertiary)
                            }
                            Spacer()
                            Button("恢复") {
                                activeAlert = .restore(snapshot)
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.accent)
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 8)
                        if index < snapshots.count - 1 {
                            Rectangle().fill(AppTheme.line.opacity(0.6)).frame(height: 0.6)
                        }
                    }
                }
            }
            Text("恢复到旧快照前，会先自动备份当前数据库；最多保留最近 3 次。")
                .font(.system(size: 9.5))
                .foregroundColor(AppTheme.tertiary)
                .lineSpacing(1.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .surfaceCard(cornerRadius: 18)
    }

    private var importHistory: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("导入记录")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.ink)
            if history.isEmpty {
                Text("暂无导入记录。")
                    .font(.system(size: 11.5))
                    .foregroundColor(AppTheme.tertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 9) {
                            Text(entry.kind)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(entry.kind == "EOH" ? AppTheme.accent : AppTheme.warning)
                                .frame(width: 30, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.fileName)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(AppTheme.ink)
                                    .lineLimit(1)
                                Text("\(entry.rowCount) 行 · \(DateFormatter.gbDateTime.string(from: entry.importedAt))")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(AppTheme.tertiary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        if index < history.count - 1 {
                            Rectangle().fill(AppTheme.line.opacity(0.6)).frame(height: 0.6)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .surfaceCard(cornerRadius: 18)
    }

    private func fileInfo(_ store: StoreSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文件")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.ink)
            infoLine("文件名", store.fileName)
            infoLine("大小", store.fileSize.gbFileSize)
            infoLine("最后导入", store.lastImportAt.map { DateFormatter.gbDateTime.string(from: $0) } ?? "—")
            infoLine("最后 EOH", store.lastEOHImportAt.map { DateFormatter.gbDateTime.string(from: $0) } ?? "—")
            infoLine("最后 LOG", store.lastLOGImportAt.map { DateFormatter.gbDateTime.string(from: $0) } ?? "—")
            Text("文件位于 Documents/GuestBook/Stores，可在“文件”App 中查看。")
                .font(.system(size: 9.5))
                .foregroundColor(AppTheme.tertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .surfaceCard(cornerRadius: 18)
    }

    private func infoLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(AppTheme.secondary)
                .frame(width: 64, alignment: .leading)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(AppTheme.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    private func loadHistory() {
        guard let database = try? state.databaseStore.openStore(storeID) else { return }
        defer { database.close() }
        history = database.importHistory()
    }

    private func loadSnapshots() {
        snapshots = state.databaseStore.snapshots(forStoreID: storeID)
    }
}
