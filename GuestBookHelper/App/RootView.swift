import SwiftUI

enum MainTab: Hashable {
    case overview
    case inventory
    case stores
    case settings
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedTab: MainTab = .overview

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                AppHeader(onManageStores: { selectedTab = .stores })

                TabView(selection: $selectedTab) {
                    OverviewView(onOpenInventory: { selectedTab = .inventory })
                        .tabItem {
                            Image(systemName: SFSymbol.available("square.grid.2x2.fill", fallback: "square.grid.2x2"))
                            Text("总览")
                        }
                        .tag(MainTab.overview)

                    InventoryHomeView()
                        .tabItem {
                            Image(systemName: "cube.box.fill")
                            Text("库存")
                        }
                        .tag(MainTab.inventory)

                    StoresView()
                        .tabItem {
                            Image(systemName: "tray.full.fill")
                            Text("数据库")
                        }
                        .tag(MainTab.stores)

                    SettingsView()
                        .tabItem {
                            Image(systemName: "gear")
                            Text("设置")
                        }
                        .tag(MainTab.settings)
                }
                .accentColor(AppTheme.accent)
            }

            if state.isBusy {
                BusyOverlayView(title: state.busyTitle, detail: state.busyDetail)
            }

            if let report = state.importReport {
                ImportReportOverlay(
                    report: report,
                    onClose: { state.dismissImportReport() },
                    onOpenDatabases: {
                        state.dismissImportReport()
                        selectedTab = .stores
                    }
                )
            }

            if let conflict = state.databaseImportConflict {
                DatabaseImportConflictOverlay(
                    conflict: conflict,
                    onMerge: { state.resolveDatabaseImport(merge: true) },
                    onSkip: { state.resolveDatabaseImport(merge: false) }
                )
                .zIndex(30)
            }
        }
        .sheet(isPresented: $state.showImportPicker) {
            SpreadsheetDocumentPicker(isPresented: $state.showImportPicker) { urls in
                state.enqueueImport(urls)
            }
        }
        .alert(item: $state.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
        .onReceive(state.$searchText) { text in
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               selectedTab != .inventory {
                selectedTab = .inventory
            }
        }
        .onAppear {
            Keyboard.dismiss()
            #if DEBUG
            if DebugLaunchOptions.forceDark { state.setAppearance(.dark) }
            if DebugLaunchOptions.forceLight { state.setAppearance(.light) }
            if DebugLaunchOptions.seedTags {
                state.seedDebugTagsIfNeeded()
            }
            if let search = DebugLaunchOptions.searchText {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    state.searchText = search
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                switch DebugLaunchOptions.route {
                case "stores", "store-detail":
                    selectedTab = .stores
                case "settings", "tag-manager":
                    selectedTab = .settings
                case "overview", "overview-customize":
                    selectedTab = .overview
                case "inventory", "filter", "detail", "barcode", "no-record-sale", "sales3", "sales7":
                    selectedTab = .inventory
                case "returned-search":
                    selectedTab = .inventory
                    state.filter = InventoryFilter()
                    state.searchText = "退货"
                case "out-search":
                    selectedTab = .inventory
                    state.filter = InventoryFilter()
                    state.searchText = "出库"
                default:
                    break
                }
            }
            #endif
        }
    }
}
