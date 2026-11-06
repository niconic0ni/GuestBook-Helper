import SwiftUI

private enum InventorySheet: Identifiable {
    case item(InventoryItem)
    case filter
    case export(URL)
    case barcode(InventoryItem)

    var id: String {
        switch self {
        case .item(let item): return "item-\(item.serialNumber)"
        case .filter: return "filter"
        case .export(let url): return "export-\(url.path)"
        case .barcode(let item): return "barcode-\(item.serialNumber)"
        }
    }
}

struct InventoryHomeView: View {
    @EnvironmentObject private var state: AppState

    @State private var activeSheet: InventorySheet?
    @State private var showSortSheet = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                if state.activeStore == nil {
                    onboarding
                } else {
                    quickFilterRow
                    recordsSection
                    records
                    footer
                }
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 96)
        }
        .background(Color.clear)
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .actionSheet(isPresented: $showSortSheet) {
            ActionSheet(
                title: Text("排序方式"),
                buttons: InventorySort.allCases.map { sort in
                    .default(Text(sort.title)) { state.sortOrder = sort }
                } + [.cancel(Text("取消"))]
            )
        }
        .onAppear(perform: handleDebugRoute)
    }

    private func exportCurrentResults() {
        Keyboard.dismiss()
        guard let storeID = state.activeStoreID else { return }
        do {
            let url = try LogXLSXExporter.writeFile(items: state.visibleItems, storeID: storeID)
            activeSheet = .export(url)
        } catch {
            state.alert = AppAlert(title: "无法导出 LOG", message: error.localizedDescription)
        }
    }

    private func handleDebugRoute() {
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            switch DebugLaunchOptions.route {
            case "filter":
                activeSheet = .filter
            case "detail":
                if let item = state.visibleItems.first { activeSheet = .item(item) }
            case "barcode":
                if let item = state.visibleItems.first { activeSheet = .barcode(item) }
            case "sales3":
                state.applyQuickScope(.sales3)
            case "sales7":
                state.applyQuickScope(.sales7)
            case "no-record-sale":
                if let item = state.visibleItems.first(where: { $0.isStock }) {
                    state.toggleNoRecordSaleTag(serialNumber: item.serialNumber)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        if let current = state.item(withSerial: item.serialNumber) {
                            activeSheet = .item(current)
                        }
                    }
                }
            default:
                break
            }
        }
        #endif
    }

    @ViewBuilder
    private func sheetContent(for sheet: InventorySheet) -> some View {
        switch sheet {
        case .item(let item):
            InventoryDetailSheet(serialNumber: item.serialNumber)
                .environmentObject(state)
        case .filter:
            FilterSheetView()
                .environmentObject(state)
        case .export(let url):
            ActivityView(activityItems: [url])
        case .barcode(let item):
            NavigationView {
                BarcodeView(serialNumber: item.serialNumber)
                    .environmentObject(state)
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }

    // MARK: - Onboarding

    private var onboarding: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 34)
            ZStack {
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 92, height: 92)
                Image(systemName: SFSymbol.available("tray.and.arrow.down.fill", fallback: "folder.fill"))
                    .font(.system(size: 35, weight: .medium))
                    .foregroundColor(AppTheme.accent)
            }
            VStack(spacing: 8) {
                Text("还没有库存数据库")
                    .font(.system(size: 25, weight: .semibold, design: .serif))
                    .foregroundColor(AppTheme.ink)
                Text("导入文件名含 EOH 的库存清单和含 LOG 的销售记录。\n应用会按 Store ID 自动生成独立的 .ngbd 数据库。")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            VStack(spacing: 10) {
                Button(action: { state.requestImport() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                        Text("导入 xlsx 报表")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)

            HStack(spacing: 18) {
                onboardingTip("EOH", "当前库存")
                onboardingTip("LOG", "销售与入库记录")
                onboardingTip(".ngbd", "每店一库")
            }
            .padding(.top, 6)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
    }

    private func onboardingTip(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.ink)
            Text(detail)
                .font(.system(size: 9.5))
                .foregroundColor(AppTheme.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.surfaceMuted)
        )
    }

    // MARK: - Categories

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("按产品类别")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundColor(AppTheme.ink)
                Text("在库数量")
                    .font(.system(size: 10.5))
                    .foregroundColor(AppTheme.tertiary)
                Spacer()
                if !state.stockItems.isEmpty {
                    Text("\(state.stockCount) 件")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(AppTheme.accent)
                }
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(state.allCategories, id: \.category) { entry in
                        CategoryCard(
                            category: entry.category,
                            count: stockCount(for: entry.category),
                            isSelected: state.filter.lobs.contains(entry.category)
                        ) {
                            toggleCategory(entry.category)
                        }
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
        }
    }

    private func stockCount(for category: String) -> Int {
        state.stockCountsByCategory.first(where: { $0.category == category })?.count ?? 0
    }

    private func toggleCategory(_ category: String) {
        Keyboard.dismiss()
        withAnimation(.easeInOut(duration: 0.2)) {
            if state.filter.lobs.contains(category) {
                state.filter.lobs.remove(category)
            } else {
                state.filter.lobs = [category]
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Quick filters

    private var quickScopeCaption: String {
        switch state.quickScope {
        case .stock: return "默认仅显示在库良品"
        case .sales3, .sales7: return "快速查看近期销售"
        case .custom: return "自定义筛选"
        }
    }

    private var quickFilterRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("快捷筛选")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundColor(AppTheme.ink)
                Spacer()
                Text(quickScopeCaption)
                    .font(.system(size: 9.5))
                    .foregroundColor(AppTheme.tertiary)
            }
            .padding(.horizontal, 2)

            HStack(spacing: 8) {
                quickFilterButton(
                    title: "在库良品",
                    symbol: "shippingbox.fill",
                    fallbackSymbol: "cube.box.fill",
                    isSelected: state.quickScope == .stock,
                    scope: .stock
                )
                quickFilterButton(
                    title: "3天销售",
                    symbol: "calendar",
                    fallbackSymbol: "calendar",
                    isSelected: state.quickScope == .sales3,
                    scope: .sales3
                )
                quickFilterButton(
                    title: "7天销售",
                    symbol: "calendar",
                    fallbackSymbol: "calendar",
                    isSelected: state.quickScope == .sales7,
                    scope: .sales7
                )
            }
        }
    }

    private func quickFilterButton(
        title: String,
        symbol: String,
        fallbackSymbol: String,
        isSelected: Bool,
        scope: InventoryQuickScope
    ) -> some View {
        Button(action: {
            Keyboard.dismiss()
            withAnimation(.easeInOut(duration: 0.2)) {
                state.applyQuickScope(scope)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            HStack(spacing: 5) {
                Image(systemName: SFSymbol.available(symbol, fallback: fallbackSymbol))
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(isSelected ? AppTheme.accent : AppTheme.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? AppTheme.accentSoft : AppTheme.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.55) : AppTheme.line.opacity(0.9), lineWidth: 0.8)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Records

    private var recordsSection: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.isSearching ? "搜索结果" : "库存条目")
                        .font(.system(size: 21, weight: .semibold, design: .serif))
                        .foregroundColor(AppTheme.ink)
                    Text(recordsSubtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(AppTheme.secondary)
                }
                Spacer(minLength: 6)
                Button(action: { activeSheet = .filter }) {
                    HStack(spacing: 5) {
                        Image(systemName: SFSymbol.available("line.3.horizontal.decrease", fallback: "slider.horizontal.3"))
                            .font(.system(size: 11, weight: .semibold))
                        Text("筛选")
                            .font(.system(size: 12, weight: .semibold))
                        if state.filter.activeFacetCount > 0 {
                            Text("\(state.filter.activeFacetCount)")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Circle().fill(AppTheme.accent))
                        }
                    }
                }
                .buttonStyle(QuietButtonStyle())

                sortControl

                Button(action: exportCurrentResults) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(state.visibleItems.isEmpty ? AppTheme.tertiary : AppTheme.ink)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppTheme.surfaceMuted)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.line.opacity(0.9), lineWidth: 0.7)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(state.visibleItems.isEmpty)
                .accessibility(label: Text("导出当前筛选结果为 xlsx 销售记录"))
            }

            if state.isSearching || state.hasActiveFilter {
                activeFilterBar
            }
        }
    }

    private var recordsSubtitle: String {
        let visible = state.visibleItems.count
        if state.isSearching || state.hasActiveFilter {
            return "显示 \(visible) / \(state.items.count) 条"
        }
        if state.filter.isDefaultScope {
            return "\(visible) 条 · 默认在库良品"
        }
        return "显示 \(visible) / \(state.items.count) 条"
    }

    @ViewBuilder
    private var sortControl: some View {
        if #available(iOS 14.0, *) {
            Menu {
                ForEach(InventorySort.allCases) { sort in
                    Button(action: { state.sortOrder = sort }) {
                        HStack {
                            Text(sort.title)
                            if state.sortOrder == sort {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                sortLabel
            }
        } else {
            Button(action: { showSortSheet = true }) {
                sortLabel
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var sortLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 10.5, weight: .semibold))
            Text(state.sortOrder.shortTitle)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(AppTheme.ink)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(AppTheme.line.opacity(0.9), lineWidth: 0.7)
        )
    }

    private var activeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if state.isSearching {
                    FilterChip(title: "“\(state.searchText.trimmed)”", onRemove: {
                        state.searchText = ""
                    })
                }
                ForEach(filterChips) { chip in
                    FilterChip(title: chip.title, onRemove: chip.remove)
                }
                if state.hasActiveFilter {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) { state.resetFilter() }
                    }) {
                        Text("清除筛选")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.accent)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var filterChips: [HomeFilterChip] {
        var chips: [HomeFilterChip] = []
        let filter = state.filter

        for value in filter.statuses.sorted() {
            let title = TransactionType(rawValue: value)?.title ?? value
            chips.append(HomeFilterChip(id: "status-\(value)", title: title) {
                state.filter.statuses.remove(value)
            })
        }
        for value in filter.conditions.sorted() {
            let title = ItemCondition(rawValue: value)?.title ?? value
            chips.append(HomeFilterChip(id: "condition-\(value)", title: title) {
                state.filter.conditions.remove(value)
            })
        }
        for value in filter.lobs.sorted() {
            chips.append(HomeFilterChip(id: "lob-\(value)", title: value) {
                state.filter.lobs.remove(value)
            })
        }
        for value in filter.subLOBs.sorted() {
            chips.append(HomeFilterChip(id: "sub-\(value)", title: value) {
                state.filter.subLOBs.remove(value)
            })
        }
        for value in filter.colors.sorted() {
            chips.append(HomeFilterChip(id: "color-\(value)", title: value) {
                state.filter.colors.remove(value)
            })
        }
        for value in filter.capacities.sorted() {
            chips.append(HomeFilterChip(id: "cap-\(value)", title: value) {
                state.filter.capacities.remove(value)
            })
        }
        for id in filter.tagIDs.sorted() {
            let name = state.allTags.first(where: { $0.id == id })?.name ?? "标签"
            chips.append(HomeFilterChip(id: "tag-\(id)", title: name) {
                state.filter.tagIDs.remove(id)
            })
        }
        if let range = filter.recordRange {
            chips.append(HomeFilterChip(id: "record-range", title: "记录 \(range.summary)") {
                state.filter.recordRange = nil
            })
        }
        if let range = filter.selloutRange {
            chips.append(HomeFilterChip(id: "sellout-range", title: "销售 \(range.summary)") {
                state.filter.selloutRange = nil
            })
        }
        return chips
    }

    @ViewBuilder
    private var records: some View {
        if state.items.isEmpty {
            EmptyStateView(
                symbol: "tray.and.arrow.down",
                title: "数据库为空",
                message: "导入最新的 EOH 与 LOG 报表后，条目会显示在这里。"
            )
            .surfaceCard(cornerRadius: 20)
        } else if state.visibleItems.isEmpty {
            VStack(spacing: 14) {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "没有匹配的条目",
                    message: state.isSearching ? "试试更短的关键词，或清除筛选条件。" : "调整筛选条件后再试。"
                )
                HStack(spacing: 9) {
                    if state.isSearching {
                        Button("清除搜索") {
                            state.searchText = ""
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                    Button("清除筛选") {
                        withAnimation(.easeInOut(duration: 0.2)) { state.resetFilter() }
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                .padding(.bottom, 22)
            }
            .frame(maxWidth: .infinity)
            .surfaceCard(cornerRadius: 20)
        } else {
            VStack(spacing: 9) {
                ForEach(state.visibleItems) { item in
                    Button(action: {
                        Keyboard.dismiss()
                        activeSheet = .item(item)
                    }) {
                        InventoryRowView(item: item)
                    }
                    .buttonStyle(PressableCardButtonStyle())
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 9))
                Text("本地 .ngbd 数据库 · 不上传任何数据")
                    .font(.system(size: 10))
            }
            .foregroundColor(AppTheme.tertiary)
            if let store = state.activeStore {
                Text("\(store.fileName) · \(store.fileSize.gbFileSize)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.tertiary.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

private struct HomeFilterChip: Identifiable {
    var id: String
    var title: String
    var remove: () -> Void
}

// MARK: - Hero

struct InventoryHeroCard: View {
    var storeID: String
    var stockCount: Int
    var currentCount: Int
    var soldCount: Int
    var totalCount: Int
    var lastImportAt: Date?
    var categoryCount: Int

    private var progress: CGFloat {
        guard currentCount > 0 else { return 0 }
        return min(1, CGFloat(stockCount) / CGFloat(currentCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(AppTheme.success)
                        .frame(width: 5, height: 5)
                    Text("STORE \(storeID)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundColor(.white.opacity(0.62))
                }
                Spacer()
                Text("LIVE DATABASE")
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.52))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.white.opacity(0.07))
                    )
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.6)
                    )
            }

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("可售库存")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.55))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(stockCount)")
                            .font(.system(size: 66, weight: .semibold, design: .serif))
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text("件")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.48))
                    }
                    Text("良品且非 SELLOUT · 含退货")
                        .font(.system(size: 9.5))
                        .foregroundColor(.white.opacity(0.38))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                StockRing(progress: progress, stock: stockCount, total: currentCount)
                    .frame(width: 94, height: 94)
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.7)

            HStack(spacing: 0) {
                heroStat("当前 EOH", "\(currentCount)")
                heroDivider
                heroStat("已售记录", "\(soldCount)")
                heroDivider
                heroStat("全部条目", "\(totalCount)")
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("最近导入")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.34))
                    Text(lastImportAt.map { DateFormatter.gbDateTime.string(from: $0) } ?? "—")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.66))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
            }
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x1A1C23), Color(hex: 0x090A0E)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RadialGradient(
                    colors: [AppTheme.accent.opacity(0.32), Color.clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 300
                )
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.7)
            }
        )
        .shadow(color: Color.black.opacity(0.22), radius: 24, x: 0, y: 14)
    }

    private var heroDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 0.6, height: 22)
            .padding(.horizontal, 12)
    }

    private func heroStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(.white.opacity(0.34))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.82))
        }
    }
}

struct StockRing: View {
    var progress: CGFloat
    var stock: Int
    var total: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.09), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    AngularGradient(
                        colors: [AppTheme.accent.opacity(0.45), AppTheme.accent, Color(hex: 0x8FD0FF)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.7), value: progress)
            VStack(spacing: 1) {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundColor(.white)
                Text("\(stock) / \(total)")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.42))
            }
        }
    }
}

// MARK: - Category card

struct CategoryCard: View {
    var category: String
    var count: Int
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.categorySoftColor(category))
                            .frame(width: 33, height: 33)
                        Image(systemName: AppTheme.categorySymbol(category))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.categoryColor(category))
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.accent)
                    }
                }
                Spacer(minLength: 10)
                Text("\(count)")
                    .font(.system(size: 31, weight: .semibold, design: .serif))
                    .foregroundColor(AppTheme.ink)
                Text(category)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(AppTheme.ink)
                    .lineLimit(1)
                Text("件在库")
                    .font(.system(size: 9.5))
                    .foregroundColor(AppTheme.tertiary)
            }
            .padding(13)
            .frame(width: 122, height: 128, alignment: .leading)
            .surfaceCard(cornerRadius: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.7) : Color.clear, lineWidth: 1.1)
            )
        }
        .buttonStyle(PressableCardButtonStyle())
    }
}
