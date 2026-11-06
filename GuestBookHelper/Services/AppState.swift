import Foundation
import UIKit

struct DatabaseImportConflict: Identifiable {
    let id = UUID()
    let url: URL
    let storeID: String
}

final class AppState: ObservableObject {
    // MARK: - Persistence keys

    private enum Keys {
        static let appearance = "gb.appearance"
        static let sort = "gb.sort"
        static let activeStore = "gb.activeStoreID"
        static let overviewHidden = "gb.overview.hiddenSections"
        static let legacyOutAsSales = "gb.legacyOutAsSales"
    }

    private let defaults = UserDefaults.standard
    let databaseStore: DatabaseStore
    private let importer: InventoryImporter
    private var pendingImportURLs: [URL] = []
    private var databaseImportQueue: [URL] = []
    private var isProcessingDatabaseImports = false

    // MARK: - Published state

    @Published var stores: [StoreSummary] = []
    @Published var activeStoreID: String?
    @Published var items: [InventoryItem] = []
    @Published var allTags: [Tag] = []
    @Published var filterOptions = FilterOptions()
    @Published var searchText: String = ""
    @Published var filter = InventoryFilter.defaultInventory
    @Published var quickScope: InventoryQuickScope = .stock
    @Published var legacyOutAsSales: Bool {
        didSet {
            defaults.set(legacyOutAsSales, forKey: Keys.legacyOutAsSales)
            reloadStoreList(preferredStoreID: activeStoreID)
        }
    }
    @Published var overviewHiddenSections: Set<String> {
        didSet {
            defaults.set(Array(overviewHiddenSections), forKey: Keys.overviewHidden)
        }
    }
    @Published var sortOrder: InventorySort {
        didSet { defaults.set(sortOrder.rawValue, forKey: Keys.sort) }
    }
    @Published var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            onAppearanceChange?(appearance.userInterfaceStyle)
        }
    }
    @Published var isBusy: Bool = false
    @Published var busyTitle: String = ""
    @Published var busyDetail: String = ""
    @Published var importReport: ImportReport?
    @Published var alert: AppAlert?
    @Published var showImportPicker: Bool = false
    @Published var databaseImportConflict: DatabaseImportConflict?

    var onAppearanceChange: ((UIUserInterfaceStyle) -> Void)?

    // MARK: - Init

    init(databaseStore: DatabaseStore? = nil) {
        let store = databaseStore ?? DatabaseStore()
        self.databaseStore = store
        self.importer = InventoryImporter(databaseStore: store)
        let savedAppearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: Keys.appearance) ?? "") ?? .system
        self.appearance = savedAppearance
        self.sortOrder = InventorySort(rawValue: UserDefaults.standard.string(forKey: Keys.sort) ?? "") ?? .createdDescending
        self.activeStoreID = UserDefaults.standard.string(forKey: Keys.activeStore)
        self.overviewHiddenSections = Set(UserDefaults.standard.stringArray(forKey: Keys.overviewHidden) ?? [])
        self.legacyOutAsSales = UserDefaults.standard.bool(forKey: Keys.legacyOutAsSales)
        bootstrap()
    }

    private func bootstrap() {
        let summaries = databaseStore.summaries(legacyOutAsSales: legacyOutAsSales)
        stores = summaries
        if let activeStoreID = activeStoreID,
           let summary = summaries.first(where: { $0.storeID == activeStoreID }) {
            self.activeStoreID = summary.storeID
            loadStoreData(resetFilter: false)
        } else if let first = summaries.first {
            activeStoreID = first.storeID
            defaults.set(first.storeID, forKey: Keys.activeStore)
            loadStoreData(resetFilter: false)
        } else {
            activeStoreID = nil
            items = []
            allTags = []
            filterOptions = FilterOptions()
        }
    }

    // MARK: - Derived data

    var activeStore: StoreSummary? {
        guard let activeStoreID = activeStoreID else { return nil }
        return stores.first(where: { $0.storeID == activeStoreID })
    }

    var stockItems: [InventoryItem] {
        items.filter { $0.isStock }
    }

    var stockCount: Int {
        stockItems.count
    }

    var stockCountsByCategory: [(category: String, count: Int)] {
        let grouped = Dictionary(grouping: stockItems, by: { $0.displayCategory })
        return grouped.map { (category: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.category.localizedStandardCompare(rhs.category) == .orderedAscending
            }
    }

    var allCategories: [(category: String, count: Int)] {
        let grouped = Dictionary(grouping: items, by: { $0.displayCategory })
        return grouped.map { (category: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                let leftStock = stockCountsByCategory.first(where: { $0.category == lhs.category })?.count ?? 0
                let rightStock = stockCountsByCategory.first(where: { $0.category == rhs.category })?.count ?? 0
                if leftStock != rightStock { return leftStock > rightStock }
                return lhs.category.localizedStandardCompare(rhs.category) == .orderedAscending
            }
    }

    var currentItemCount: Int {
        items.filter { $0.presentInLatestEOH }.count
    }

    var soldCount: Int {
        items.filter { item in
            item.transactionType == .sellout || item.isLegacyOutSale(enabled: legacyOutAsSales)
        }.count
    }

    var goodCount: Int {
        items.filter { $0.condition == .good }.count
    }

    var demoCount: Int {
        items.filter { $0.condition == .demo }.count
    }

    var defectiveCount: Int {
        items.filter { $0.condition == .defective }.count
    }

    var salesCount3Days: Int {
        salesCount(inLastDays: 3)
    }

    var salesCount7Days: Int {
        salesCount(inLastDays: 7)
    }

    var salesCountThisMonth: Int {
        guard let interval = Calendar.current.dateInterval(of: .month, for: Date()) else { return 0 }
        return items.filter { item in
            guard let date = item.saleDate(legacyOutAsSales: legacyOutAsSales) else { return false }
            return interval.contains(date)
        }.count
    }

    var inboundCountThisMonth: Int {
        guard let interval = Calendar.current.dateInterval(of: .month, for: Date()) else { return 0 }
        return items.filter { item in
            guard let date = item.transferInDate else { return false }
            return interval.contains(date)
        }.count
    }

    var visibleItems: [InventoryItem] {
        let filtered = items.filter { item in
            filter.matches(item, legacyOutAsSales: legacyOutAsSales) && item.matchesSearch(searchText)
        }
        return sortOrder.sorted(filtered)
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasActiveFilter: Bool {
        !filter.isEmpty
    }

    var storageBytes: Int64 {
        databaseStore.totalDatabaseBytes()
    }

    func tagsForItem(_ item: InventoryItem) -> [Tag] {
        item.tags
    }

    // MARK: - Loading

    func selectStore(_ storeID: String) {
        guard storeID != activeStoreID else { return }
        activeStoreID = storeID
        defaults.set(storeID, forKey: Keys.activeStore)
        loadStoreData(resetFilter: true)
    }

    func reloadStoreData(preserveFilters: Bool = true) {
        loadStoreData(resetFilter: !preserveFilters)
    }

    private func loadStoreData(resetFilter: Bool) {
        guard let storeID = activeStoreID else {
            items = []
            allTags = []
            filterOptions = FilterOptions()
            return
        }
        do {
            let database = try databaseStore.openStore(storeID)
            defer { database.close() }
            let loadedItems = try database.fetchItems()
            let loadedTags = try database.fetchTags()
            items = loadedItems
            allTags = loadedTags
            filterOptions = FilterOptions.make(items: loadedItems, allTags: loadedTags)
            if resetFilter {
                filter = InventoryFilter.defaultInventory
                quickScope = .stock
            } else {
                let tagIDs = Set(loadedTags.map { $0.id })
                filter.tagIDs = filter.tagIDs.intersection(tagIDs)
            }
            if let index = stores.firstIndex(where: { $0.storeID == storeID }),
               let summary = try? database.summary(legacyOutAsSales: legacyOutAsSales) {
                stores[index] = summary
            }
        } catch {
            alert = AppAlert(title: "读取数据库失败", message: error.localizedDescription)
        }
    }

    func reloadStoreList(preferredStoreID: String? = nil) {
        let summaries = databaseStore.summaries(legacyOutAsSales: legacyOutAsSales)
        stores = summaries
        let preferred = preferredStoreID ?? activeStoreID
        if let preferred = preferred, summaries.contains(where: { $0.storeID == preferred }) {
            activeStoreID = preferred
        } else {
            activeStoreID = summaries.first?.storeID
        }
        if let activeStoreID = activeStoreID {
            defaults.set(activeStoreID, forKey: Keys.activeStore)
        } else {
            defaults.removeObject(forKey: Keys.activeStore)
        }
        loadStoreData(resetFilter: preferred == nil)
    }

    // MARK: - Appearance

    func setAppearance(_ newValue: AppAppearance) {
        guard appearance != newValue else { return }
        appearance = newValue
    }

    // MARK: - Import

    func requestImport() {
        guard !isBusy else { return }
        showImportPicker = true
    }

    /// Entry point for files arriving from the system share sheet / "Open in".
    /// If an import is already running, queue the URLs and process them after it.
    func enqueueImport(_ urls: [URL]) {
        let accepted = urls.filter { $0.isFileURL }
        guard !accepted.isEmpty else { return }
        let databaseURLs = accepted.filter { $0.pathExtension.lowercased() == "ngbd" }
        let spreadsheetURLs = accepted.filter { $0.pathExtension.lowercased() != "ngbd" }

        if !spreadsheetURLs.isEmpty {
            if isBusy || isProcessingDatabaseImports || !databaseURLs.isEmpty || !databaseImportQueue.isEmpty {
                pendingImportURLs.append(contentsOf: spreadsheetURLs)
            } else {
                importFiles(spreadsheetURLs)
            }
        }
        if !databaseURLs.isEmpty {
            databaseImportQueue.append(contentsOf: databaseURLs)
            processNextDatabaseImport()
        }
    }

    func resolveDatabaseImport(merge: Bool) {
        guard let conflict = databaseImportConflict else { return }
        guard databaseImportQueue.first?.standardizedFileURL == conflict.url.standardizedFileURL else {
            databaseImportConflict = nil
            processNextDatabaseImport()
            return
        }
        databaseImportQueue.removeFirst()
        databaseImportConflict = nil
        if merge {
            performDatabaseImport(conflict.url, storeID: conflict.storeID)
        }
        processNextDatabaseImport()
    }

    private func processNextDatabaseImport() {
        guard databaseImportConflict == nil, !isBusy, !isProcessingDatabaseImports else { return }
        guard let url = databaseImportQueue.first else {
            isProcessingDatabaseImports = false
            drainPendingImports()
            return
        }
        let raw = url.deletingPathExtension().lastPathComponent
        let normalized = InventorySpreadsheetParser.normalizedStoreID(raw) ?? ""
        let storeID = normalized.isEmpty ? raw : normalized
        if databaseStore.databaseExists(forStoreID: storeID) {
            databaseImportConflict = DatabaseImportConflict(url: url, storeID: storeID)
            return
        }
        databaseImportQueue.removeFirst()
        isProcessingDatabaseImports = true
        performDatabaseImport(url, storeID: storeID)
        isProcessingDatabaseImports = false
        processNextDatabaseImport()
    }

    private func performDatabaseImport(_ url: URL, storeID: String) {
        isBusy = true
        busyTitle = "正在导入数据库"
        busyDetail = url.lastPathComponent
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
            isBusy = false
            busyTitle = ""
            busyDetail = ""
        }
        do {
            _ = try databaseStore.importDatabaseFile(from: url, mergeExisting: databaseStore.databaseExists(forStoreID: storeID))
            reloadStoreList(preferredStoreID: storeID)
            alert = AppAlert(title: "数据库已导入", message: "\(storeID).ngbd 已准备好使用。")
        } catch {
            alert = AppAlert(title: "数据库导入失败", message: error.localizedDescription)
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty, !isBusy else { return }
        isBusy = true
        busyTitle = "正在导入报表"
        busyDetail = urls.map { $0.lastPathComponent }.joined(separator: " · ")
        let importer = self.importer
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try importer.importFiles(urls) }
            DispatchQueue.main.async {
                self.finishImport(result)
            }
        }
    }

    private func finishImport(_ result: Result<ImportReport, Error>) {
        isBusy = false
        switch result {
        case .success(let report):
            let preferred = report.results.first?.storeID
            reloadStoreList(preferredStoreID: preferred)
            importReport = report
        case .failure(let error):
            alert = AppAlert(title: "导入失败", message: error.localizedDescription)
        }
        processNextDatabaseImport()
        drainPendingImports()
    }

    private func drainPendingImports() {
        guard !isBusy,
              !isProcessingDatabaseImports,
              databaseImportQueue.isEmpty,
              !pendingImportURLs.isEmpty else { return }
        let urls = pendingImportURLs
        pendingImportURLs.removeAll()
        importReport = nil
        DispatchQueue.main.async {
            self.importFiles(urls)
        }
    }

    func dismissImportReport() {
        importReport = nil
    }

    // MARK: - Stores

    func deleteStore(_ storeID: String) {
        guard !isBusy else { return }
        let wasActive = activeStoreID == storeID
        _ = databaseStore.deleteStore(storeID)
        if wasActive {
            activeStoreID = nil
            items = []
            allTags = []
            filterOptions = FilterOptions()
        }
        let remaining = databaseStore.summaries(legacyOutAsSales: legacyOutAsSales)
        stores = remaining
        if let activeStoreID = activeStoreID,
           remaining.contains(where: { $0.storeID == activeStoreID }) {
            loadStoreData(resetFilter: false)
        } else if let first = remaining.first {
            activeStoreID = first.storeID
            defaults.set(first.storeID, forKey: Keys.activeStore)
            loadStoreData(resetFilter: true)
        } else {
            activeStoreID = nil
            defaults.removeObject(forKey: Keys.activeStore)
            items = []
            allTags = []
            filterOptions = FilterOptions()
        }
    }

    func exportURL(for storeID: String) -> URL {
        databaseStore.fileURL(forStoreID: storeID)
    }

    // MARK: - Tags

    @discardableResult
    func createTag(named name: String) -> Tag? {
        guard let activeStoreID = activeStoreID else { return nil }
        do {
            _ = try? databaseStore.createSnapshot(forStoreID: activeStoreID, reason: "修改标签")
            let database = try databaseStore.openStore(activeStoreID)
            defer { database.close() }
            let tag = try database.createTag(named: name)
            allTags = try database.fetchTags()
            filterOptions = FilterOptions.make(items: items, allTags: allTags)
            return tag
        } catch {
            alert = AppAlert(title: "无法创建标签", message: error.localizedDescription)
            return nil
        }
    }

    func toggleNoRecordSaleTag(serialNumber: String) {
        guard let item = item(withSerial: serialNumber) else { return }
        let systemTag: Tag
        if let existing = allTags.first(where: { SystemTag.isNoRecordSale($0) }) {
            systemTag = existing
        } else if let created = createTag(named: SystemTag.noRecordSaleName) {
            systemTag = created
        } else {
            return
        }
        var tagIDs = Set(item.tags.map { $0.id })
        if tagIDs.contains(systemTag.id) {
            tagIDs.remove(systemTag.id)
        } else {
            tagIDs.insert(systemTag.id)
        }
        saveTags(serialNumber: serialNumber, tagIDs: tagIDs)
    }

    func saveTags(serialNumber: String, tagIDs: Set<Int64>) {
        guard let activeStoreID = activeStoreID else { return }
        guard let item = item(withSerial: serialNumber),
              Set(item.tags.map { $0.id }) != tagIDs else { return }
        do {
            _ = try? databaseStore.createSnapshot(forStoreID: activeStoreID, reason: "修改标签")
            let database = try databaseStore.openStore(activeStoreID)
            defer { database.close() }
            try database.setTags(serialNumber: serialNumber, tagIDs: tagIDs)
        } catch {
            alert = AppAlert(title: "无法保存标签", message: error.localizedDescription)
            return
        }
        loadStoreData(resetFilter: false)
    }

    func renameTag(id: Int64, newName: String) {
        guard let activeStoreID = activeStoreID else { return }
        do {
            _ = try? databaseStore.createSnapshot(forStoreID: activeStoreID, reason: "重命名标签")
            let database = try databaseStore.openStore(activeStoreID)
            defer { database.close() }
            try database.renameTag(id: id, newName: newName)
        } catch {
            alert = AppAlert(title: "无法重命名标签", message: error.localizedDescription)
            return
        }
        loadStoreData(resetFilter: false)
    }

    func deleteTag(id: Int64) {
        guard let activeStoreID = activeStoreID else { return }
        do {
            _ = try? databaseStore.createSnapshot(forStoreID: activeStoreID, reason: "删除标签")
            let database = try databaseStore.openStore(activeStoreID)
            defer { database.close() }
            try database.deleteTag(id: id)
        } catch {
            alert = AppAlert(title: "无法删除标签", message: error.localizedDescription)
            return
        }
        filter.tagIDs.remove(id)
        loadStoreData(resetFilter: false)
    }

    func restoreSnapshot(_ snapshot: DatabaseSnapshot) {
        do {
            try databaseStore.restoreSnapshot(snapshot, forStoreID: snapshot.storeID)
            reloadStoreList(preferredStoreID: snapshot.storeID)
        } catch {
            alert = AppAlert(title: "无法恢复快照", message: error.localizedDescription)
        }
    }

    func item(withSerial serialNumber: String) -> InventoryItem? {
        items.first(where: { $0.serialNumber == serialNumber })
    }

    func applyFilter(_ newFilter: InventoryFilter) {
        filter = newFilter
        if newFilter.isDefaultScope {
            quickScope = .stock
        } else {
            quickScope = .custom
        }
    }

    func applyQuickScope(_ scope: InventoryQuickScope) {
        switch scope {
        case .stock:
            filter = InventoryFilter.defaultInventory
            quickScope = .stock
        case .sales3:
            applySalesQuickFilter(days: 3, scope: .sales3)
        case .sales7:
            applySalesQuickFilter(days: 7, scope: .sales7)
        case .custom:
            break
        }
    }

    private func applySalesQuickFilter(days: Int, scope: InventoryQuickScope) {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) ?? startOfToday
        var newFilter = InventoryFilter()
        newFilter.inStockOnly = false
        newFilter.goodOnly = false
        newFilter.excludeDemoAndNoRecord = false
        newFilter.statuses = [TransactionType.sellout.rawValue]
        newFilter.selloutRange = DateRangeFilter(start: start, end: now)
        filter = newFilter
        quickScope = scope
    }

    func resetFilter() {
        filter = InventoryFilter.defaultInventory
        quickScope = .stock
    }

    func applyScannedSerial(_ serial: String) {
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        filter = InventoryFilter()
        quickScope = .custom
        searchText = trimmed
        Keyboard.dismiss()
    }

    // MARK: - Overview customization

    func isOverviewSectionVisible(_ section: OverviewSection) -> Bool {
        !overviewHiddenSections.contains(section.rawValue)
    }

    func toggleOverviewSection(_ section: OverviewSection) {
        if overviewHiddenSections.contains(section.rawValue) {
            overviewHiddenSections.remove(section.rawValue)
        } else {
            overviewHiddenSections.insert(section.rawValue)
        }
    }

    func showAllOverviewSections() {
        overviewHiddenSections.removeAll()
    }

    func hideAllOverviewSections() {
        overviewHiddenSections = Set(OverviewSection.allCases.map { $0.rawValue })
    }

    private func salesCount(inLastDays days: Int) -> Int {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday),
              let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return 0 }
        return items.filter { item in
            guard let date = item.saleDate(legacyOutAsSales: legacyOutAsSales) else { return false }
            return date >= start && date < end
        }.count
    }

    func allFilterOptionTags() -> [TagFilterOption] {
        filterOptions.tags
    }

    #if DEBUG
    func seedDebugTagsIfNeeded() {
        guard activeStoreID != nil, allTags.isEmpty else { return }
        let names = ["已验机", "待调拨", "展示品"]
        var created: [Tag] = []
        for name in names {
            if let tag = createTag(named: name) { created.append(tag) }
        }
        guard created.count >= 2 else { return }
        let candidates = visibleItems.prefix(9)
        for (index, item) in candidates.enumerated() {
            var ids = Set<Int64>()
            ids.insert(created[index % created.count].id)
            if index % 3 == 0 { ids.insert(created[(index + 1) % created.count].id) }
            saveTags(serialNumber: item.serialNumber, tagIDs: ids)
        }
    }
    #endif
}
