import SwiftUI
import UIKit

struct InventoryDetailSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.presentationMode) private var presentationMode
    let serialNumber: String

    @State private var copied = false

    private var item: InventoryItem? {
        state.item(withSerial: serialNumber)
    }

    var body: some View {
        NavigationView {
            Group {
                if let item = item {
                    detailContent(item)
                } else {
                    EmptyStateView(
                        symbol: "questionmark.folder",
                        title: "条目不存在",
                        message: "数据库可能已在其他操作中更新。"
                    )
                }
            }
            .background(AppBackground().edgesIgnoringSafeArea(.all))
            .gbInlineTitle("条目详情")
            .navigationBarItems(trailing: Button("完成") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func detailContent(_ item: InventoryItem) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                hero(item)
                tagsSection(item)
                infoSection(item)
                sourceSection(item)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
    }

    private func hero(_ item: InventoryItem) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(AppTheme.categorySoftColor(item.displayCategory))
                        .frame(width: 54, height: 54)
                    Image(systemName: AppTheme.categorySymbol(item.displayCategory))
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(AppTheme.categoryColor(item.displayCategory))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    StatusBadge(type: item.transactionType)
                    if item.condition != .unknown {
                        ConditionBadge(condition: item.condition, compact: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayModel)
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundColor(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.displayCategory)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.secondary)
            }

            HStack(spacing: 8) {
                Text(item.serialNumber)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppTheme.ink)
                Spacer(minLength: 4)
                NavigationLink(destination: BarcodeView(serialNumber: item.serialNumber).environmentObject(state)) {
                    HStack(spacing: 4) {
                        Image(systemName: SFSymbol.available("barcode", fallback: "number"))
                        Text("条码")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(AppTheme.ink)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    UIPasteboard.general.string = item.serialNumber
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        copied = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "已复制" : "复制")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(copied ? AppTheme.success : AppTheme.accent)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(AppTheme.surfaceMuted)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    specChip(item.displayCapacity)
                    specChip(item.displayColor)
                    if let days = item.stockDays() {
                        specChip("库存 \(days) 天")
                    }
                    if !item.presentInLatestEOH && item.transactionType != .transferOut {
                        specChip("历史记录")
                    }
                }
            }
        }
        .padding(18)
        .surfaceCard(cornerRadius: 22)
    }

    private func specChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(AppTheme.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(AppTheme.surfaceMuted))
            .lineLimit(1)
    }

    private func tagsSection(_ item: InventoryItem) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("自定义标签")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.ink)
                Spacer()
                NavigationLink(destination: TagEditorView(serialNumber: item.serialNumber)) {
                    HStack(spacing: 3) {
                        Text(item.tags.isEmpty ? "添加" : "编辑")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
                }
                .buttonStyle(PlainButtonStyle())
            }

            if item.tags.isEmpty {
                Text("还没有标签。可以为这条库存添加“已验机”“待调拨”等自定义标签，并在筛选和搜索中使用。")
                    .font(.system(size: 11.5))
                    .foregroundColor(AppTheme.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(item.tags) { tag in
                            TagChip(tag: tag)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            if item.hasNoRecordSaleTag {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text("已标记为无记录销售，不计入实际可售库存。")
                        .font(.system(size: 10.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(AppTheme.warning)
                .padding(.top, 2)
            }

            Button(action: {
                state.toggleNoRecordSaleTag(serialNumber: item.serialNumber)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: item.hasNoRecordSaleTag ? SFSymbol.available("arrow.uturn.backward.circle", fallback: "arrow.counterclockwise.circle") : SFSymbol.available("cart.badge.minus", fallback: "minus.circle"))
                    Text(item.hasNoRecordSaleTag ? "取消“无记录销售”标记" : "标记为“无记录销售”")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(item.hasNoRecordSaleTag ? AppTheme.secondary : AppTheme.warning)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.warningSoft.opacity(0.75))
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(15)
        .surfaceCard(cornerRadius: 18)
    }

    private func infoSection(_ item: InventoryItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("条目信息")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.ink)
                .padding(.bottom, 11)

            infoRow("序列号", item.serialNumber, mono: true)
            divider
            infoRow("交易状态", item.transactionType.rawDisplayName, accent: true)
            divider
            infoRow("MPN", item.displayMPN, mono: true)
            divider
            infoRow("产品类别", item.displayCategory)
            divider
            infoRow("产品型号", item.displayModel)
            divider
            infoRow("颜色", item.displayColor)
            divider
            infoRow("容量", item.displayCapacity, mono: true)
            divider
            infoRow("入库日期", item.transferInDate.map { DateFormatter.gbDateTime.string(from: $0) } ?? "—")
            divider
            infoRow("库存天数", stockDaysText(item), accent: true)
            divider
            infoRow("销售日期", item.selloutDate.map { DateFormatter.gbDateTime.string(from: $0) } ?? "—", accent: item.selloutDate != nil)
            divider
            infoRow("退货日期", item.returnedDate.map { DateFormatter.gbDateTime.string(from: $0) } ?? "—", accent: item.returnedDate != nil)
            divider
            infoRow("出库日期", item.transferOutDate.map { DateFormatter.gbDateTime.string(from: $0) } ?? "—", accent: item.transferOutDate != nil)
            divider
            infoRow("商店 ID", item.storeID, mono: true)
            divider
            infoRow("商品状态", item.condition.rawDisplayName)
            divider
            infoRow("最新 EOH", item.presentInLatestEOH ? "包含" : "不包含")

            Text("库存天数：售出条目按销售时间、出库条目按出库时间，其余按当前时间；不足 1 天按 1 天计算。")
                .font(.system(size: 9.5))
                .foregroundColor(AppTheme.tertiary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)
        }
        .padding(15)
        .surfaceCard(cornerRadius: 18)
    }

    private func stockDaysText(_ item: InventoryItem) -> String {
        guard let days = item.stockDays() else { return "—" }
        return "\(days) 天 · \(item.stockDaysBasisText)"
    }

    private func sourceSection(_ item: InventoryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("数据")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.ink)
            Text("所有字段来自导入的 EOH / LOG 报表。标签与状态保存在 \(item.storeID).ngbd 中，不会上传网络。")
                .font(.system(size: 11.5))
                .foregroundColor(AppTheme.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                Image(systemName: "clock")
                Text("最后更新 \(DateFormatter.gbDateTime.string(from: item.updatedAt))")
            }
            .font(.system(size: 10))
            .foregroundColor(AppTheme.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .surfaceCard(cornerRadius: 18)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.line.opacity(0.65))
            .frame(height: 0.6)
            .padding(.vertical, 9)
    }

    private func infoRow(_ label: String, _ value: String, mono: Bool = false, accent: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(AppTheme.secondary)
                .frame(width: 72, alignment: .leading)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: mono ? 11.5 : 12, weight: mono ? .medium : .regular, design: mono ? .monospaced : .default))
                .foregroundColor(accent ? AppTheme.accent : AppTheme.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Tag editor

struct TagEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.presentationMode) private var presentationMode
    let serialNumber: String

    @State private var selectedIDs: Set<Int64> = []
    @State private var newTagName = ""
    @State private var didLoad = false

    private var systemTag: Tag? {
        state.allTags.first(where: { SystemTag.isNoRecordSale($0) })
    }

    private var userTags: [Tag] {
        state.allTags.filter { !SystemTag.isNoRecordSale($0) }
    }

    var body: some View {
        List {
            if let systemTag = systemTag {
                Section {
                    Button(action: { toggle(systemTag) }) {
                        HStack(spacing: 10) {
                            Image(systemName: SFSymbol.available("cart.badge.minus", fallback: "minus.circle"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppTheme.warning)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(SystemTag.noRecordSaleName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.ink)
                                Text("销售未记录，不计入实际库存")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(AppTheme.tertiary)
                            }
                            Spacer()
                            Image(systemName: selectedIDs.contains(systemTag.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundColor(selectedIDs.contains(systemTag.id) ? AppTheme.warning : AppTheme.lineStrong)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                } header: {
                    Text("系统销售标签")
                } footer: {
                    Text("带有“无记录销售”标签的条目仍会保留在数据库和搜索中，但不会计入首页、类别或数据库的实际库存数量。")
                }
            }

            Section {
                HStack(spacing: 8) {
                    TextField("新标签名称", text: $newTagName, onCommit: addTag)
                        .font(.system(size: 14))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button(action: addTag) {
                        Text("添加")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(canAdd ? AppTheme.accent : AppTheme.tertiary)
                    }
                    .disabled(!canAdd)
                }
            } header: {
                Text("新建标签")
            } footer: {
                Text("最多 24 个字符。标签只保存在当前商店的 .ngbd 数据库中。")
            }

            if userTags.isEmpty {
                Section {
                    Text("还没有其他标签。输入名称并点“添加”即可创建。")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondary)
                }
            } else {
                Section {
                    ForEach(userTags) { tag in
                        Button(action: { toggle(tag) }) {
                            HStack(spacing: 11) {
                                Circle()
                                    .fill(tagColor(tag))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tag.name)
                                        .font(.system(size: 14))
                                        .foregroundColor(AppTheme.ink)
                                    Text("\(tag.itemCount) 条记录")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(AppTheme.tertiary)
                                }
                                Spacer()
                                Image(systemName: selectedIDs.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundColor(selectedIDs.contains(tag.id) ? AppTheme.accent : AppTheme.lineStrong)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } header: {
                    Text("已有标签")
                }
            }
        }
        .listStyle(GroupedListStyle())
        .gbInlineTitle("编辑标签")
        .navigationBarItems(
            leading: Button("取消") { presentationMode.wrappedValue.dismiss() },
            trailing: Button("保存") {
                state.saveTags(serialNumber: serialNumber, tagIDs: selectedIDs)
                presentationMode.wrappedValue.dismiss()
            }
            .font(.system(size: 14, weight: .semibold))
        )
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            selectedIDs = Set(state.item(withSerial: serialNumber)?.tags.map { $0.id } ?? [])
        }
    }

    private var canAdd: Bool {
        !newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let existing = state.allTags.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
            selectedIDs.insert(existing.id)
        } else if let created = state.createTag(named: name) {
            selectedIDs.insert(created.id)
        }
        newTagName = ""
        Keyboard.dismiss()
    }

    private func toggle(_ tag: Tag) {
        if selectedIDs.contains(tag.id) {
            selectedIDs.remove(tag.id)
        } else {
            selectedIDs.insert(tag.id)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func tagColor(_ tag: Tag) -> Color {
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
