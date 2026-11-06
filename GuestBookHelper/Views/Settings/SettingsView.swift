import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showTagManager = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 17) {
                header
                appearanceCard
                dataCard
                tagsCard
                privacyCard
                aboutCard
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 96)
        }
        .sheet(isPresented: $showTagManager) {
            TagManagerSheet()
                .environmentObject(state)
        }
        .onAppear {
            #if DEBUG
            if DebugLaunchOptions.route == "tag-manager" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showTagManager = true
                }
            }
            #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionKicker(text: "Preferences")
            Text("设置")
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundColor(AppTheme.ink)
            Text("外观、标签与本地数据。")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.secondary)
        }
    }

    private var appearanceCard: some View {
        SettingsCard(title: "外观", symbol: "circle.lefthalf.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Text("界面外观")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(AppTheme.ink)
                Picker("界面外观", selection: Binding(
                    get: { state.appearance },
                    set: { state.setAppearance($0) }
                )) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())

                HStack(spacing: 6) {
                    Image(systemName: state.appearance.symbolName)
                        .font(.system(size: 10))
                    Text(state.appearanceDetailText)
                        .font(.system(size: 10.5))
                }
                .foregroundColor(AppTheme.secondary)
            }
        }
    }

    private var dataCard: some View {
        SettingsCard(title: "数据", symbol: "externaldrive.fill") {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 0) {
                    settingsStat("数据库", "\(state.stores.count)")
                    cardDivider
                    settingsStat("条目", "\(state.items.count)")
                    cardDivider
                    settingsStat("标签", "\(state.allTags.count)")
                    cardDivider
                    settingsStat("占用", state.storageBytes.gbFileSize)
                }

                Rectangle()
                    .fill(AppTheme.line.opacity(0.65))
                    .frame(height: 0.6)

                Toggle(isOn: Binding(
                    get: { state.legacyOutAsSales },
                    set: { state.legacyOutAsSales = $0 }
                )) {
                    Text("老出库记录视为销量")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(AppTheme.ink)
                }

                Text("将 2024 年 8 月 23 日及之前、最新状态为出库的条目计入销量；打开后在筛选销售数据时也会视为销售。")
                    .font(.system(size: 10.5))
                    .foregroundColor(AppTheme.tertiary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)

                Text("导入最新的 EOH 会刷新当前库存快照，同时保留已导入的销售记录和自定义标签。")
                    .font(.system(size: 10.5))
                    .foregroundColor(AppTheme.tertiary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var tagsCard: some View {
        SettingsCard(title: "自定义标签", symbol: "tag.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(state.allTags.isEmpty ? "还没有标签" : "\(state.allTags.count) 个标签，可在条目详情中添加")
                        .font(.system(size: 11.5))
                        .foregroundColor(AppTheme.secondary)
                    Spacer()
                }
                Button(action: { showTagManager = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "tag")
                        Text("管理标签")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var privacyCard: some View {
        SettingsCard(title: "隐私", symbol: "lock.shield.fill") {
            VStack(alignment: .leading, spacing: 8) {
                privacyLine("wifi.slash", "完全离线，不发起网络请求")
                privacyLine("internaldrive", "数据库保存在 App 文档目录")
                privacyLine("person.crop.circle.badge.xmark", "无账号、无分析 SDK、无广告")
            }
        }
    }

    private var aboutCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("GuestBook Helper")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundColor(AppTheme.ink)
            Spacer(minLength: 8)
            Text(appVersion)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppTheme.tertiary)
        }
        .padding(15)
        .surfaceCard(cornerRadius: 18)
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(AppTheme.line.opacity(0.7))
            .frame(width: 0.6, height: 22)
            .padding(.horizontal, 10)
    }

    private func settingsStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8.5))
                .foregroundColor(AppTheme.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func privacyLine(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: SFSymbol.available(symbol, fallback: "lock"))
                .font(.system(size: 10))
                .foregroundColor(AppTheme.success)
                .frame(width: 13)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.secondary)
        }
    }
}

private extension AppState {
    var appearanceDetailText: String {
        switch appearance {
        case .system: return "跟随系统设置，在浅色与深色之间自动切换"
        case .light: return "始终使用浅色外观"
        case .dark: return "始终使用深色外观"
        }
    }
}

struct SettingsCard<Content: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: SFSymbol.available(symbol, fallback: "gear"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundColor(AppTheme.ink)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .surfaceCard(cornerRadius: 18)
    }
}

// MARK: - Tag manager

struct TagManagerSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.presentationMode) private var presentationMode
    @State private var pendingDelete: Tag?

    var body: some View {
        NavigationView {
            List {
                if state.allTags.isEmpty {
                    Section {
                        EmptyStateView(
                            symbol: "tag",
                            title: "还没有标签",
                            message: "打开一条库存详情，在“自定义标签”中添加。"
                        )
                    }
                } else {
                    Section {
                        ForEach(state.allTags) { tag in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tag.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(AppTheme.ink)
                                    Text(systemTagDescription(tag))
                                        .font(.system(size: 10.5))
                                        .foregroundColor(AppTheme.tertiary)
                                }
                                Spacer()
                                if SystemTag.isNoRecordSale(tag) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(AppTheme.tertiary)
                                        .frame(width: 30, height: 30)
                                } else {
                                    Button(action: { pendingDelete = tag }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(AppTheme.danger)
                                            .frame(width: 30, height: 30)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } footer: {
                        Text("“无记录销售”是系统标签，不能删除。其他标签删除后会从所有条目中移除，但不会删除条目本身。")
                    }
                }
            }
            .listStyle(GroupedListStyle())
            .gbInlineTitle("标签管理")
            .navigationBarItems(trailing: Button("完成") { presentationMode.wrappedValue.dismiss() })
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .alert(item: $pendingDelete) { tag in
            Alert(
                title: Text("删除“\(tag.name)”？"),
                message: Text("它会被从 \(tag.itemCount) 条记录中移除。"),
                primaryButton: .destructive(Text("删除")) {
                    state.deleteTag(id: tag.id)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private func systemTagDescription(_ tag: Tag) -> String {
        if SystemTag.isNoRecordSale(tag) {
            return "系统标签 · \(tag.itemCount) 条记录，不计入库存"
        }
        return "\(tag.itemCount) 条记录使用"
    }
}
