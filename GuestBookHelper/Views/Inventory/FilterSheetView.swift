import SwiftUI

struct FilterSheetView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.presentationMode) private var presentationMode

    @State private var draft = InventoryFilter()
    @State private var recordEnabled = false
    @State private var recordStart = Date()
    @State private var recordEnd = Date()
    @State private var didLoad = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("匹配条目")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.secondary)
                            Text("\(matchCount) 条")
                                .font(.system(size: 24, weight: .semibold, design: .serif))
                                .foregroundColor(AppTheme.ink)
                        }
                        Spacer()
                        Text("\(effectiveDraft.activeFacetCount) 个条件")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.secondary)
                    }
                    .padding(.vertical, 3)

                    if !effectiveDraft.isEmpty || !hasDefaultScope {
                        Button(action: reset) {
                            Text("恢复默认筛选")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.danger)
                        }
                    }
                }

                Section(header: Text("库存范围")) {
                    Toggle("仅在库", isOn: $draft.inStockOnly)
                    Toggle("仅良品", isOn: $draft.goodOnly)
                    Toggle("排除展示机和无记录销售", isOn: $draft.excludeDemoAndNoRecord)
                    Text("“在库”只看库存状态；“良品”只看 Condition=GOOD；两者可独立开关。排除项会隐藏展示机和带“无记录销售”标签的条目。")
                        .font(.system(size: 10.5))
                        .foregroundColor(AppTheme.tertiary)
                        .lineSpacing(1.5)
                }

                if !state.filterOptions.statuses.isEmpty {
                    Section(header: Text("库存状态")) {
                        ForEach(state.filterOptions.statuses) { option in
                            checkRow(
                                title: option.label,
                                count: option.count,
                                selected: draft.statuses.contains(option.value)
                            ) {
                                toggle(option.value, keyPath: \.statuses)
                            }
                        }
                    }
                }

                if !state.filterOptions.conditions.isEmpty {
                    Section(header: Text("商品状态")) {
                        ForEach(state.filterOptions.conditions) { option in
                            checkRow(
                                title: option.label,
                                count: option.count,
                                selected: draft.conditions.contains(option.value)
                            ) {
                                toggle(option.value, keyPath: \.conditions)
                            }
                        }
                    }
                }

                Section(header: Text("产品")) {
                    NavigationLink(destination: MultiSelectView(
                        title: "产品类别",
                        options: state.filterOptions.lobs,
                        selection: $draft.lobs
                    )) {
                        linkRow("产品类别", selectionCount: draft.lobs.count)
                    }
                    NavigationLink(destination: MultiSelectView(
                        title: "产品型号",
                        options: state.filterOptions.subLOBs,
                        selection: $draft.subLOBs
                    )) {
                        linkRow("产品型号", selectionCount: draft.subLOBs.count)
                    }
                    NavigationLink(destination: MultiSelectView(
                        title: "颜色",
                        options: state.filterOptions.colors,
                        selection: $draft.colors
                    )) {
                        linkRow("颜色", selectionCount: draft.colors.count)
                    }
                    NavigationLink(destination: MultiSelectView(
                        title: "容量",
                        options: state.filterOptions.capacities,
                        selection: $draft.capacities
                    )) {
                        linkRow("容量", selectionCount: draft.capacities.count)
                    }
                }

                Section(header: Text("记录日期")) {
                    Toggle(isOn: $recordEnabled) {
                        Text("按记录日期筛选")
                            .font(.system(size: 13))
                    }
                    if recordEnabled {
                        DatePicker("开始", selection: $recordStart, displayedComponents: .date)
                            .font(.system(size: 13))
                        DatePicker("结束", selection: $recordEnd, displayedComponents: .date)
                            .font(.system(size: 13))
                        Text("显示所选日期内曾经在库的完整记录，不区分入库或销售发生在哪一天；若要查看已售/出库历史，请同时关闭“仅在库”。")
                            .font(.system(size: 10.5))
                            .foregroundColor(AppTheme.tertiary)
                            .lineSpacing(1.5)
                    }
                }

                Section(header: Text("自定义标签")) {
                    if state.filterOptions.tags.isEmpty {
                        Text("还没有可筛选的标签。可在条目详情中添加。")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.secondary)
                    } else {
                        NavigationLink(destination: TagMultiSelectView(
                            title: "标签",
                            options: state.filterOptions.tags,
                            selection: $draft.tagIDs
                        )) {
                            linkRow("标签", selectionCount: draft.tagIDs.count)
                        }
                    }
                }
            }
            .listStyle(GroupedListStyle())
            .gbInlineTitle("筛选")
            .navigationBarItems(
                leading: Button("取消") { presentationMode.wrappedValue.dismiss() },
                trailing: Button("应用") {
                    state.applyFilter(effectiveDraft)
                    presentationMode.wrappedValue.dismiss()
                }
                .font(.system(size: 14, weight: .semibold))
            )
            .onAppear(perform: loadIfNeeded)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var hasDefaultScope: Bool {
        draft.inStockOnly && draft.goodOnly && draft.excludeDemoAndNoRecord
    }

    private var effectiveDraft: InventoryFilter {
        var result = draft
        if recordEnabled {
            result.recordRange = DateRangeFilter(
                start: min(recordStart, recordEnd),
                end: max(recordStart, recordEnd)
            )
        } else {
            result.recordRange = nil
        }
        return result
    }

    private var matchCount: Int {
        state.items.filter { effectiveDraft.matches($0, legacyOutAsSales: state.legacyOutAsSales) && $0.matchesSearch(state.searchText) }.count
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        draft = state.filter
        let dates = state.items.flatMap { item in
            [item.transferInDate, item.selloutDate, item.returnedDate, item.transferOutDate, item.createdAt]
                .compactMap { $0 }
        }
        let defaultDates = defaultRange(for: dates)
        if let range = state.filter.recordRange {
            recordEnabled = true
            recordStart = range.start
            recordEnd = range.end
        } else {
            recordStart = defaultDates.0
            recordEnd = defaultDates.1
        }
    }

    private func defaultRange(for dates: [Date]) -> (Date, Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        if let first = dates.min(), let last = dates.max() {
            return (calendar.startOfDay(for: first), calendar.startOfDay(for: last))
        }
        return (calendar.date(byAdding: .day, value: -30, to: today) ?? today, today)
    }

    private func reset() {
        draft = InventoryFilter.defaultInventory
        recordEnabled = false
        let dates = state.items.flatMap { item in
            [item.transferInDate, item.selloutDate, item.returnedDate, item.transferOutDate, item.createdAt]
                .compactMap { $0 }
        }
        let defaultDates = defaultRange(for: dates)
        recordStart = defaultDates.0
        recordEnd = defaultDates.1
    }

    private func toggle(_ value: String, keyPath: WritableKeyPath<InventoryFilter, Set<String>>) {
        var set = draft[keyPath: keyPath]
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
        draft[keyPath: keyPath] = set
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func checkRow(title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.ink)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AppTheme.tertiary)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(selected ? AppTheme.accent : AppTheme.lineStrong)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func linkRow(_ title: String, selectionCount: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.ink)
            Spacer()
            Text(selectionCount == 0 ? "全部" : "\(selectionCount) 项")
                .font(.system(size: 11))
                .foregroundColor(selectionCount == 0 ? AppTheme.tertiary : AppTheme.accent)
        }
    }
}

// MARK: - Multi select

struct MultiSelectView: View {
    let title: String
    let options: [FilterOption]
    @Binding var selection: Set<String>

    var body: some View {
        List {
            if options.isEmpty {
                Text("没有可用选项")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondary)
            } else {
                Section {
                    ForEach(options) { option in
                        Button(action: { toggle(option.value) }) {
                            HStack(spacing: 9) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .font(.system(size: 13.5))
                                        .foregroundColor(AppTheme.ink)
                                    Text("\(option.count) 条")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(AppTheme.tertiary)
                                }
                                Spacer()
                                Image(systemName: selection.contains(option.value) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundColor(selection.contains(option.value) ? AppTheme.accent : AppTheme.lineStrong)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .listStyle(GroupedListStyle())
        .gbInlineTitle(title)
        .navigationBarItems(trailing: Button(selection.isEmpty ? "全选" : "清除") {
            if selection.isEmpty {
                selection = Set(options.map { $0.value })
            } else {
                selection.removeAll()
            }
        })
    }

    private func toggle(_ value: String) {
        if selection.contains(value) {
            selection.remove(value)
        } else {
            selection.insert(value)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

struct TagMultiSelectView: View {
    let title: String
    let options: [TagFilterOption]
    @Binding var selection: Set<Int64>

    var body: some View {
        List {
            if options.isEmpty {
                Text("没有可用标签")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondary)
            } else {
                Section {
                    ForEach(options) { option in
                        Button(action: { toggle(option.id) }) {
                            HStack(spacing: 9) {
                                Circle()
                                    .fill(tagColor(option.colorIndex))
                                    .frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.name)
                                        .font(.system(size: 13.5))
                                        .foregroundColor(AppTheme.ink)
                                    Text("\(option.count) 条记录")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(AppTheme.tertiary)
                                }
                                Spacer()
                                Image(systemName: selection.contains(option.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundColor(selection.contains(option.id) ? AppTheme.accent : AppTheme.lineStrong)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .listStyle(GroupedListStyle())
        .gbInlineTitle(title)
        .navigationBarItems(trailing: Button(selection.isEmpty ? "全选" : "清除") {
            if selection.isEmpty {
                selection = Set(options.map { $0.id })
            } else {
                selection.removeAll()
            }
        })
    }

    private func toggle(_ id: Int64) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func tagColor(_ index: Int) -> Color {
        switch TagColor.allCases[abs(index) % TagColor.allCases.count] {
        case .blue: return AppTheme.dynamic(light: 0x2F6DD0, dark: 0x78AEFF)
        case .violet: return AppTheme.dynamic(light: 0x7A51CB, dark: 0xB59AFF)
        case .teal: return AppTheme.dynamic(light: 0x198275, dark: 0x6BD8C7)
        case .amber: return AppTheme.dynamic(light: 0xA46E1A, dark: 0xE8BA6A)
        case .rose: return AppTheme.dynamic(light: 0xB64462, dark: 0xFF9CB2)
        case .slate: return AppTheme.dynamic(light: 0x626A78, dark: 0xA6B0BF)
        }
    }
}
