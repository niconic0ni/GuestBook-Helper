import SwiftUI
import UIKit

// MARK: - Header

private enum HeaderSheet: Identifiable {
    case stores
    case scanner

    var id: String {
        switch self {
        case .stores: return "stores"
        case .scanner: return "scanner"
        }
    }
}

struct AppHeader: View {
    @EnvironmentObject private var state: AppState
    var onManageStores: () -> Void

    @State private var activeSheet: HeaderSheet?

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Image("BrandIcon")
                    .resizable()
                    .frame(width: 31, height: 31)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 0) {
                    Text("GuestBook")
                        .font(.system(size: 19, weight: .semibold, design: .serif))
                        .foregroundColor(AppTheme.ink)
                        .lineLimit(1)
                        .fixedSize()
                    Text("INVENTORY HELPER")
                        .font(.system(size: 7.5, weight: .semibold))
                        .tracking(1.35)
                        .foregroundColor(AppTheme.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }

                Spacer(minLength: 6)

                Button(action: { activeSheet = .stores }) {
                    HStack(spacing: 5) {
                        if let store = state.activeStore {
                            Text(store.storeID)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.ink)
                                .lineLimit(1)
                                .fixedSize()
                        } else {
                            Text("未载入")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppTheme.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        Image(systemName: SFSymbol.available("chevron.down", fallback: "chevron.down"))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(AppTheme.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(AppTheme.surfaceMuted)
                    )
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.line.opacity(0.8), lineWidth: 0.6)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(state.stores.isEmpty)
            }

            HStack(spacing: 8) {
                GlobalSearchBar(
                    text: $state.searchText,
                    placeholder: state.activeStore == nil ? "导入数据后开始搜索" : "搜索序列号、型号、颜色、标签…",
                    isEnabled: state.activeStore != nil
                )
                .frame(height: 46)

                Button(action: { activeSheet = .scanner }) {
                    Image(systemName: SFSymbol.available("barcode.viewfinder", fallback: "camera"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                        .frame(width: 46, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(AppTheme.surfaceMuted)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(AppTheme.line.opacity(0.85), lineWidth: 0.7)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(state.activeStore == nil)
                .accessibility(label: Text("扫描序列号条码"))
            }
        }
        .frame(maxWidth: 980)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 30 : 6)
        .padding(.bottom, 8)
        .background(Color.clear)
        .onAppear {
            #if DEBUG
            if DebugLaunchOptions.route == "scanner" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    activeSheet = .scanner
                }
            }
            #endif
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .stores:
                StorePickerSheet(
                    selectedStoreID: state.activeStoreID,
                    stores: state.stores,
                    onSelect: { storeID in
                        state.selectStore(storeID)
                        activeSheet = nil
                    },
                    onManage: {
                        activeSheet = nil
                        onManageStores()
                    },
                    onCancel: { activeSheet = nil }
                )
            case .scanner:
                ScannerSheet(onScanned: { serial in
                    state.applyScannedSerial(serial)
                    activeSheet = nil
                })
            }
        }
    }
}

struct DatabaseImportConflictOverlay: View {
    let conflict: DatabaseImportConflict
    let onMerge: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .edgesIgnoringSafeArea(.all)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    Image(systemName: SFSymbol.available("exclamationmark.triangle.fill", fallback: "exclamationmark.triangle"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppTheme.warning)
                    Text("发现同名数据库")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundColor(AppTheme.ink)
                }
                Text("\(conflict.storeID).ngbd 已经存在。\n\n选择“合并数据”会把导入文件中的条目和标签合并进现有数据库；选择“暂不导入”会保留现有数据库不变。")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 9) {
                    Button("暂不导入", action: onSkip)
                        .buttonStyle(QuietButtonStyle())
                    Button("合并数据", action: onMerge)
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                }
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppTheme.line.opacity(0.8), lineWidth: 0.7)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 28)
        }
        .transition(.opacity)
    }
}

// MARK: - Store picker

struct StorePickerSheet: View {
    var selectedStoreID: String?
    var stores: [StoreSummary]
    var onSelect: (String) -> Void
    var onManage: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(stores) { store in
                        Button(action: { onSelect(store.storeID) }) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Store \(store.storeID)")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(AppTheme.ink)
                                    Text("\(store.stockCount) 件在库 · \(store.itemCount) 条记录")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.secondary)
                                }
                                Spacer()
                                if selectedStoreID == store.storeID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppTheme.accent)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } header: {
                    Text("可用数据库")
                }

                Section {
                    Button(action: onManage) {
                        HStack(spacing: 10) {
                            Image(systemName: SFSymbol.available("tray.full.fill", fallback: "folder.fill"))
                                .foregroundColor(AppTheme.accent)
                            Text("管理数据库与导入报表")
                                .foregroundColor(AppTheme.ink)
                        }
                    }
                }
            }
            .listStyle(GroupedListStyle())
            .gbInlineTitle("切换商店")
            .navigationBarItems(trailing: Button("完成", action: onCancel))
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - Badges

struct StatusBadge: View {
    var type: TransactionType

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(AppTheme.statusColor(for: type))
                .frame(width: 5, height: 5)
            Text(type.title)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundColor(AppTheme.statusColor(for: type))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(AppTheme.statusSoftColor(for: type))
        )
    }
}

struct ConditionBadge: View {
    var condition: ItemCondition
    var compact: Bool = false

    var body: some View {
        Text(condition.title)
            .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold))
            .foregroundColor(AppTheme.conditionColor(for: condition))
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 3 : 5)
            .background(
                Capsule()
                    .fill(AppTheme.conditionSoftColor(for: condition))
            )
    }
}

struct TagChip: View {
    var tag: Tag
    var removable: Bool = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tagColor)
                .frame(width: 5, height: 5)
            Text(tag.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(AppTheme.ink)
            if removable {
                Button(action: { onRemove?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(AppTheme.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(tagColor.opacity(0.14))
        )
    }

    private var tagColor: Color {
        switch tag.color {
        case .blue: return AppTheme.dynamic(light: 0x2F6DD0, dark: 0x78AEFF)
        case .violet: return AppTheme.dynamic(light: 0x7A51CB, dark: 0xB59AFF)
        case .teal: return AppTheme.dynamic(light: 0x198275, dark: 0x6BD8C7)
        case .amber: return AppTheme.dynamic(light: 0xA46E1A, dark: 0xE8BA6A)
        case .rose: return AppTheme.dynamic(light: 0xB64462, dark: 0xFF9CB2)
        case .slate: return AppTheme.dynamic(light: 0x626A78, dark: 0xA6B0BF)
        }
    }
}

struct FilterChip: View {
    var title: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.ink)
            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(AppTheme.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(AppTheme.surfaceMuted)
        )
        .overlay(
            Capsule()
                .stroke(AppTheme.line.opacity(0.9), lineWidth: 0.6)
        )
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 56, height: 56)
                Image(systemName: SFSymbol.available(symbol, fallback: "cube.box"))
                    .font(.system(size: 23, weight: .medium))
                    .foregroundColor(AppTheme.accent)
            }
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundColor(AppTheme.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundColor(AppTheme.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 26)
    }
}

// MARK: - Busy & report overlays

struct BusyOverlayView: View {
    var title: String
    var detail: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.26)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {}
            VStack(spacing: 14) {
                ActivityIndicatorView(style: .medium)
                    .frame(width: 28, height: 28)
                VStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundColor(AppTheme.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 300)
            .surfaceCard(cornerRadius: 22)
        }
        .transition(.opacity)
        .zIndex(10)
    }
}

struct ImportReportOverlay: View {
    var report: ImportReport
    var onClose: () -> Void
    var onOpenDatabases: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("导入完成")
                            .font(.system(size: 22, weight: .semibold, design: .serif))
                            .foregroundColor(AppTheme.ink)
                        Text(DateFormatter.gbDateTime.string(from: report.importedAt))
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.tertiary)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppTheme.secondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(AppTheme.surfaceMuted))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(report.results) { result in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Store \(result.storeID)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppTheme.ink)
                                    Spacer()
                                    Text("\(result.totalItems) 条记录")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.secondary)
                                }
                                HStack(spacing: 6) {
                                    miniStat("EOH", "\(result.eohRows) 行")
                                    miniStat("LOG", "\(result.logRows) 行")
                                    miniStat("在库", "\(result.stockCount)")
                                    miniStat("退货", "\(result.returnedRows)")
                                    miniStat("出库", "\(result.transferOutRows)")
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 9))
                                    Text("记录日期 \(result.recordDateRangeText)")
                                        .font(.system(size: 10.5))
                                }
                                .foregroundColor(AppTheme.secondary)
                                Text("新增 \(result.newItems) · 更新 \(result.updatedItems) · \(result.databaseFileName)")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.secondary)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.surfaceMuted)
                            )
                        }

                        if !report.warnings.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("提示")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppTheme.warning)
                                ForEach(Array(report.warnings.prefix(5).enumerated()), id: \.offset) { _, warning in
                                    Text("• \(warning)")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(AppTheme.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if report.warnings.count > 5 {
                                    Text("另有 \(report.warnings.count - 5) 条提示")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(AppTheme.tertiary)
                                }
                            }
                        }
                    }
                }
                .frame(height: reportContentHeight)

                HStack(spacing: 10) {
                    Button("查看数据库", action: onOpenDatabases)
                        .buttonStyle(QuietButtonStyle())
                    Spacer()
                    Button("完成", action: onClose)
                        .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                }
            }
            .padding(20)
            .frame(maxWidth: 390)
            .padding(.horizontal, 22)
            .surfaceCard(cornerRadius: 26, padding: 0)
        }
        .transition(.opacity)
        .zIndex(20)
    }

    private var reportContentHeight: CGFloat {
        let resultsHeight = CGFloat(report.results.count) * 132
        let warningsHeight: CGFloat = report.warnings.isEmpty ? 0 : min(150, CGFloat(report.warnings.count) * 32 + 36)
        return min(400, max(132, resultsHeight + warningsHeight))
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(AppTheme.tertiary)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(AppTheme.ink)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.surface)
        )
    }
}
