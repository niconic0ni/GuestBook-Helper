import SwiftUI
import UIKit

struct OverviewView: View {
    @EnvironmentObject private var state: AppState
    var onOpenInventory: () -> Void

    @State private var showCustomize = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                if state.activeStore == nil {
                    emptyState
                } else {
                    if state.isOverviewSectionVisible(.stockOverview) {
                        stockCard
                    }

                    if hasVisibleMetrics {
                        metricsSection
                    }

                    if state.isOverviewSectionVisible(.categories) {
                        categoriesSection
                    }

                    if allSectionsHidden {
                        hiddenState
                    }
                }
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 96)
        }
        .background(Color.clear)
        .sheet(isPresented: $showCustomize) {
            OverviewCustomizeSheet()
                .environmentObject(state)
        }
        .onAppear {
            #if DEBUG
            if DebugLaunchOptions.route == "overview-customize" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showCustomize = true
                }
            }
            #endif
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SectionKicker(text: "Overview")
                Text("总览")
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .foregroundColor(AppTheme.ink)
                Text(state.activeStore.map { "商店 \($0.storeID) · 本地数据" } ?? "导入库存后查看经营数据")
                    .font(.system(size: 11.5))
                    .foregroundColor(AppTheme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: { showCustomize = true }) {
                HStack(spacing: 5) {
                    Image(systemName: SFSymbol.available("slider.horizontal.3", fallback: "line.3.horizontal.decrease"))
                        .font(.system(size: 11, weight: .semibold))
                    Text("自定义")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundColor(AppTheme.ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AppTheme.surfaceMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(AppTheme.line.opacity(0.9), lineWidth: 0.7)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var stockCard: some View {
        InventoryHeroCard(
            storeID: state.activeStoreID ?? "",
            stockCount: state.stockCount,
            currentCount: state.currentItemCount,
            soldCount: state.soldCount,
            totalCount: state.items.count,
            lastImportAt: state.activeStore?.lastImportAt,
            categoryCount: state.stockCountsByCategory.count
        )
    }

    private var hasVisibleMetrics: Bool {
        visibleMetrics.count > 0
    }

    private var visibleMetrics: [OverviewSection] {
        [.sales3, .sales7, .monthSales, .monthInbound].filter { state.isOverviewSectionVisible($0) }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("经营指标")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundColor(AppTheme.ink)
                Text("按日期统计")
                    .font(.system(size: 10.5))
                    .foregroundColor(AppTheme.tertiary)
                Spacer()
            }
            .padding(.horizontal, 2)

            VStack(spacing: 10) {
                ForEach(0..<metricRows.count, id: \.self) { index in
                    HStack(spacing: 10) {
                        ForEach(metricRows[index]) { section in
                            metricCard(section)
                        }
                        if metricRows[index].count == 1 {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 112)
                        }
                    }
                }
            }
        }
    }

    private var metricRows: [[OverviewSection]] {
        var rows: [[OverviewSection]] = []
        var current: [OverviewSection] = []
        for section in visibleMetrics {
            current.append(section)
            if current.count == 2 {
                rows.append(current)
                current = []
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    private func metricCard(_ section: OverviewSection) -> some View {
        let value: Int
        switch section {
        case .sales3: value = state.salesCount3Days
        case .sales7: value = state.salesCount7Days
        case .monthSales: value = state.salesCountThisMonth
        case .monthInbound: value = state.inboundCountThisMonth
        default: value = 0
        }
        let color = metricColor(section)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: SFSymbol.available(section.symbolName, fallback: "chart.bar.fill"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(color)
                }
                Spacer()
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundColor(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("件")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(AppTheme.tertiary)
            }
            Text(section.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(AppTheme.ink)
                .lineLimit(1)
            Text(section.subtitle)
                .font(.system(size: 8.8))
                .foregroundColor(AppTheme.tertiary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 112, alignment: .top)
        .padding(13)
        .surfaceCard(cornerRadius: 17)
    }

    private func metricColor(_ section: OverviewSection) -> Color {
        switch section {
        case .sales3: return AppTheme.accent
        case .sales7: return AppTheme.success
        case .monthSales: return AppTheme.gold
        case .monthInbound: return AppTheme.warning
        default: return AppTheme.accent
        }
    }

    private var categoriesSection: some View {
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
                            selectCategory(entry.category)
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

    private func selectCategory(_ category: String) {
        var newFilter = InventoryFilter.defaultInventory
        newFilter.lobs = [category]
        state.applyFilter(newFilter)
        withAnimation(.easeInOut(duration: 0.2)) {
            onOpenInventory()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var allSectionsHidden: Bool {
        OverviewSection.allCases.allSatisfy { !state.isOverviewSectionVisible($0) }
    }

    private var hiddenState: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(AppTheme.tertiary)
            Text("总览内容已全部隐藏")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundColor(AppTheme.ink)
            Text("可以选择要在总览显示的数据模块。")
                .font(.system(size: 11.5))
                .foregroundColor(AppTheme.secondary)
            Button("自定义显示内容") { showCustomize = true }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .surfaceCard(cornerRadius: 20)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 80, height: 80)
                Image(systemName: SFSymbol.available("chart.pie.fill", fallback: "chart.bar.fill"))
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(AppTheme.accent)
            }
            Text("还没有可统计的数据")
                .font(.system(size: 23, weight: .semibold, design: .serif))
                .foregroundColor(AppTheme.ink)
            Text("前往“数据库”导入 EOH / LOG 报表后，总览会自动显示库存与销量。")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Button(action: { state.requestImport() }) {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.arrow.down")
                    Text("导入 xlsx 报表")
                }
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .surfaceCard(cornerRadius: 22)
    }
}

struct OverviewCustomizeSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("显示内容"), footer: Text("开关仅影响总览页面，不会改变库存或筛选条件。")) {
                    ForEach(OverviewSection.allCases) { section in
                        Button(action: { state.toggleOverviewSection(section) }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(AppTheme.surfaceMuted)
                                        .frame(width: 30, height: 30)
                                    Image(systemName: SFSymbol.available(section.symbolName, fallback: "chart.bar.fill"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppTheme.secondary)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(section.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppTheme.ink)
                                    Text(section.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.tertiary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: state.isOverviewSectionVisible(section) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 19))
                                    .foregroundColor(state.isOverviewSectionVisible(section) ? AppTheme.accent : AppTheme.lineStrong)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Section {
                    Button("全部显示") { state.showAllOverviewSections() }
                    Button("全部隐藏") { state.hideAllOverviewSections() }
                        .foregroundColor(AppTheme.danger)
                }
            }
            .listStyle(GroupedListStyle())
            .gbInlineTitle("自定义总览")
            .navigationBarItems(trailing: Button("完成") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
