import Foundation

// MARK: - Enums

enum TransactionType: String, Codable, CaseIterable, Identifiable, Hashable {
    case transferIn = "TRANSFER_IN"
    case sellout = "SELLOUT"
    case returned = "RETURNED"
    case transferOut = "TRANSFER_OUT"
    case unknown = "UNKNOWN"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transferIn: return "在库"
        case .sellout: return "已售"
        case .returned: return "退货"
        case .transferOut: return "出库"
        case .unknown: return "未知"
        }
    }

    var detailTitle: String {
        switch self {
        case .transferIn: return "入库"
        case .sellout: return "销售"
        case .returned: return "退货"
        case .transferOut: return "出库"
        case .unknown: return "未知"
        }
    }

    var rawDisplayName: String {
        switch self {
        case .transferIn: return "TRANSFER_IN"
        case .sellout: return "SELLOUT"
        case .returned: return "RETURNED"
        case .transferOut: return "TRANSFER_OUT"
        case .unknown: return "UNKNOWN"
        }
    }

    static func parse(_ raw: String) -> TransactionType {
        let value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .uppercased()
        if value == "TRANSFER_IN" || value == "TRANSFERIN" || value == "IN" { return .transferIn }
        if value == "SELLOUT" || value == "SELL_OUT" || value == "SOLD" { return .sellout }
        if value == "RETURNED" || value == "RETURN" || value == "RETURNS" { return .returned }
        if value == "TRANSFER_OUT" || value == "TRANSFEROUT" || value == "OUT" { return .transferOut }
        return .unknown
    }
}

enum ItemCondition: String, Codable, CaseIterable, Identifiable, Hashable {
    case good = "GOOD"
    case demo = "DEMO"
    case defective = "DEFECTIVE"
    case unknown = "UNKNOWN"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .good: return "良品"
        case .demo: return "展示机"
        case .defective: return "残次品"
        case .unknown: return "未知"
        }
    }

    var rawDisplayName: String {
        switch self {
        case .good: return "GOOD"
        case .demo: return "DEMO"
        case .defective: return "DEFECTIVE"
        case .unknown: return "UNKNOWN"
        }
    }

    static func parse(_ raw: String) -> ItemCondition {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value == "GOOD" { return .good }
        if value == "DEMO" { return .demo }
        if value == "DEFECTIVE" || value == "DEFECT" { return .defective }
        return .unknown
    }
}

// MARK: - System tags

enum SystemTag {
    static let noRecordSaleName = "无记录销售"
    static let noRecordSaleColorIndex = 4

    static func isNoRecordSale(_ tag: Tag) -> Bool {
        tag.name.compare(noRecordSaleName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

// MARK: - Item

struct InventoryItem: Identifiable, Hashable {
    var id: String { serialNumber }

    var serialNumber: String
    var transactionType: TransactionType
    var mpn: String
    var lob: String
    var subLOB: String
    var color: String
    var capacity: String
    var transferInDate: Date?
    var selloutDate: Date?
    var returnedDate: Date?
    var transferOutDate: Date?
    var createdAt: Date?
    var storeID: String
    var condition: ItemCondition
    var presentInLatestEOH: Bool
    var updatedAt: Date
    var tags: [Tag]

    var hasNoRecordSaleTag: Bool {
        tags.contains(where: { SystemTag.isNoRecordSale($0) })
    }

    /// Physically in inventory, independent of condition or user tags.
    /// DEMO/DEFECTIVE units still count as in stock until sold or transferred out.
    var isInInventory: Bool {
        switch transactionType {
        case .returned:
            return true
        case .transferIn:
            return presentInLatestEOH
        case .sellout, .transferOut, .unknown:
            return false
        }
    }

    var isStock: Bool {
        if hasNoRecordSaleTag {
            return false
        }
        switch transactionType {
        case .returned:
            // LOG exports often omit Condition. A returned item is treated as
            // sellable unless the data explicitly marks it DEMO/DEFECTIVE.
            return condition == .good || condition == .unknown
        case .transferIn:
            return presentInLatestEOH && condition == .good
        case .sellout, .transferOut, .unknown:
            return false
        }
    }

    var hasSale: Bool {
        transactionType == .sellout || selloutDate != nil
    }

    var displayModel: String {
        subLOB.isEmpty ? "未指定型号" : subLOB
    }

    var displayCategory: String {
        lob.isEmpty ? "未分类" : lob
    }

    var displayColor: String {
        color.isEmpty ? "—" : color
    }

    var displayCapacity: String {
        capacity.isEmpty ? "—" : capacity
    }

    var displayMPN: String {
        mpn.isEmpty ? "—" : mpn
    }

    /// Latest event produced by this record. Sold/out items sort by their
    /// latest sale/return/transfer-out time instead of the original inbound time.
    var latestEventDate: Date? {
        [transferInDate, selloutDate, returnedDate, transferOutDate, createdAt]
            .compactMap { $0 }
            .max()
    }

    var eventDate: Date? {
        latestEventDate
    }

    /// Start of this record's inventory lifecycle.
    var lifecycleStartDate: Date? {
        [transferInDate, returnedDate, transferOutDate, selloutDate, createdAt]
            .compactMap { $0 }
            .min()
    }

    /// End of the inventory lifecycle. Open-ended for items still in inventory.
    var lifecycleEndDate: Date? {
        switch transactionType {
        case .sellout:
            return selloutDate ?? latestEventDate
        case .transferOut:
            return transferOutDate ?? latestEventDate
        case .returned, .transferIn:
            return nil
        case .unknown:
            return latestEventDate
        }
    }

    /// Intervals in which the unit was actually in inventory. A sold-then-returned
    /// unit produces two intervals, so the gap between sale and return is not
    /// incorrectly treated as stocked time.
    var inventoryIntervals: [(start: Date, end: Date?)] {
        var events: [(date: Date, type: TransactionType)] = []
        if let date = transferInDate { events.append((date, .transferIn)) }
        if let date = selloutDate { events.append((date, .sellout)) }
        if let date = returnedDate { events.append((date, .returned)) }
        if let date = transferOutDate { events.append((date, .transferOut)) }
        if events.isEmpty {
            if let date = latestEventDate {
                return [(date, nil)]
            }
            return []
        }
        events.sort { $0.date < $1.date }

        var result: [(start: Date, end: Date?)] = []
        var openStart: Date?
        for event in events {
            switch event.type {
            case .transferIn, .returned:
                if let start = openStart {
                    result.append((start, event.date))
                }
                openStart = event.date
            case .sellout, .transferOut:
                if let start = openStart {
                    result.append((start, event.date))
                    openStart = nil
                } else {
                    result.append((event.date, event.date))
                }
            case .unknown:
                break
            }
        }
        if let start = openStart {
            result.append((start, nil))
        }
        return result
    }

    func overlapsRecordRange(_ range: DateRangeFilter) -> Bool {
        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: range.start)
        let rangeEndDay = calendar.startOfDay(for: range.end)
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: rangeEndDay) ?? range.end
        return inventoryIntervals.contains { interval in
            let end = interval.end ?? Date()
            let lower = min(interval.start, end)
            let upper = max(interval.start, end)
            return lower < rangeEnd && upper >= rangeStart
        }
    }

    /// Inventory days:
    /// - sold item: sale time − transfer-in time
    /// - transferred-out item: transfer-out time − transfer-in time
    /// - all other unsold items: current time − transfer-in time
    /// Rounded up, minimum 1 day. Returns nil when there is no transfer-in date.
    func stockDays(asOf now: Date = Date()) -> Int? {
        guard let transferInDate = transferInDate else { return nil }
        let end: Date
        switch transactionType {
        case .sellout:
            end = selloutDate ?? now
        case .transferOut:
            end = transferOutDate ?? now
        case .transferIn, .returned, .unknown:
            end = now
        }
        let seconds = max(0, end.timeIntervalSince(transferInDate))
        return max(1, Int(ceil(seconds / 86_400.0)))
    }

    var stockDaysBasisText: String {
        switch transactionType {
        case .sellout: return "按销售时间"
        case .transferOut: return "按出库时间"
        case .transferIn, .returned, .unknown: return "按当前时间"
        }
    }

    static var legacyOutSalesCutoff: Date {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.timeZone = TimeZone.current
        components.year = 2024
        components.month = 8
        components.day = 23
        components.hour = 23
        components.minute = 59
        components.second = 59
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    func isLegacyOutSale(enabled: Bool) -> Bool {
        guard enabled, transactionType == .transferOut, let date = transferOutDate else { return false }
        return date <= Self.legacyOutSalesCutoff
    }

    func saleDate(legacyOutAsSales: Bool) -> Date? {
        if transactionType == .sellout { return selloutDate }
        if isLegacyOutSale(enabled: legacyOutAsSales) { return transferOutDate }
        return nil
    }

    var searchableText: String {
        var parts: [String] = [
            serialNumber,
            transactionType.rawDisplayName,
            transactionType.title,
            mpn,
            lob,
            subLOB,
            color,
            capacity,
            storeID,
            condition.rawDisplayName,
            condition.title,
            presentInLatestEOH ? "当前库存" : "历史记录",
            transferInDate.map { DateFormatter.gbMediumDate.string(from: $0) } ?? "",
            selloutDate.map { DateFormatter.gbMediumDate.string(from: $0) } ?? "",
            returnedDate.map { DateFormatter.gbMediumDate.string(from: $0) } ?? "",
            transferOutDate.map { DateFormatter.gbMediumDate.string(from: $0) } ?? "",
            transferInDate.map { DateFormatter.gbDateTime.string(from: $0) } ?? "",
            selloutDate.map { DateFormatter.gbDateTime.string(from: $0) } ?? "",
            returnedDate.map { DateFormatter.gbDateTime.string(from: $0) } ?? "",
            transferOutDate.map { DateFormatter.gbDateTime.string(from: $0) } ?? ""
        ]
        parts.append(contentsOf: tags.map { $0.name })
        return parts.joined(separator: " ").folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }

    func matchesSearch(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = searchableText
        let tokens = trimmed
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { haystack.contains(String($0)) }
    }
}

// MARK: - Tag

struct Tag: Identifiable, Hashable {
    var id: Int64
    var name: String
    var colorIndex: Int
    var itemCount: Int

    var color: TagColor {
        TagColor.allCases[abs(Int(colorIndex)) % TagColor.allCases.count]
    }
}

enum TagColor: Int, CaseIterable {
    case blue
    case violet
    case teal
    case amber
    case rose
    case slate

    var foreground: String {
        switch self {
        case .blue: return "1B5FCE"
        case .violet: return "7248C8"
        case .teal: return "127D70"
        case .amber: return "9B6817"
        case .rose: return "B33A5B"
        case .slate: return "5E6470"
        }
    }
}

// MARK: - Quick filters & overview

enum InventoryQuickScope: String, Equatable {
    case stock
    case sales3
    case sales7
    case custom
}

enum OverviewSection: String, CaseIterable, Identifiable {
    case stockOverview
    case categories
    case sales3
    case sales7
    case monthSales
    case monthInbound

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stockOverview: return "库存总览"
        case .categories: return "类别库存"
        case .sales3: return "三天销量"
        case .sales7: return "七天销量"
        case .monthSales: return "本月销量"
        case .monthInbound: return "本月入库"
        }
    }

    var subtitle: String {
        switch self {
        case .stockOverview: return "可售库存、当前 EOH、已售与最近导入"
        case .categories: return "按产品类别统计当前可售库存"
        case .sales3: return "最近 3 个自然日的销售件数"
        case .sales7: return "最近 7 个自然日的销售件数"
        case .monthSales: return "本月内发生的销售件数"
        case .monthInbound: return "本月内入库的件数"
        }
    }

    var symbolName: String {
        switch self {
        case .stockOverview: return "chart.pie.fill"
        case .categories: return "square.grid.2x2.fill"
        case .sales3: return "calendar.badge.clock"
        case .sales7: return "calendar.badge.plus"
        case .monthSales: return "cart.fill"
        case .monthInbound: return "tray.and.arrow.down.fill"
        }
    }
}

enum SerialScanParser {
    /// Apple retail serial barcodes are prefixed with S. Only those are accepted;
    /// the prefix is removed before the value is put into the search field.
    static func normalizedSerial(from code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1, trimmed.uppercased().hasPrefix("S") else { return nil }
        let serial = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        return serial.isEmpty ? nil : serial
    }
}

// MARK: - Sorting

enum InventorySort: String, CaseIterable, Identifiable {
    case createdDescending
    case createdAscending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createdDescending: return "最新记录：从新到旧"
        case .createdAscending: return "最新记录：从旧到新"
        }
    }

    var shortTitle: String {
        switch self {
        case .createdDescending: return "从新到旧"
        case .createdAscending: return "从旧到新"
        }
    }

    var symbolName: String {
        switch self {
        case .createdDescending: return "arrow.down"
        case .createdAscending: return "arrow.up"
        }
    }

    func sorted(_ items: [InventoryItem]) -> [InventoryItem] {
        items.sorted { lhs, rhs in
            switch (lhs.eventDate, rhs.eventDate) {
            case let (left?, right?):
                if left == right { return lhs.serialNumber < rhs.serialNumber }
                return self == .createdDescending ? left > right : left < right
            case (nil, nil):
                return lhs.serialNumber < rhs.serialNumber
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }
    }
}

// MARK: - Filters

struct DateRangeFilter: Equatable {
    var start: Date
    var end: Date

    func contains(_ date: Date?) -> Bool {
        guard let date = date else { return false }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: start)
        let startOfEndDay = calendar.startOfDay(for: end)
        guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: startOfEndDay) else {
            return date >= startOfDay && date <= end
        }
        return date >= startOfDay && date < endExclusive
    }

    func overlaps(start itemStart: Date, end itemEnd: Date) -> Bool {
        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: start)
        let rangeEndDay = calendar.startOfDay(for: end)
        guard let rangeEnd = calendar.date(byAdding: .day, value: 1, to: rangeEndDay) else {
            return itemStart <= end && itemEnd >= start
        }
        return itemStart < rangeEnd && itemEnd >= rangeStart
    }

    var summary: String {
        let calendar = Calendar.current
        if calendar.isDate(start, inSameDayAs: end) {
            return DateFormatter.gbMediumDate.string(from: start)
        }
        return "\(DateFormatter.gbShortDate.string(from: start)) – \(DateFormatter.gbShortDate.string(from: end))"
    }
}

struct InventoryFilter: Equatable {
    var statuses: Set<String> = []
    var conditions: Set<String> = []
    var lobs: Set<String> = []
    var subLOBs: Set<String> = []
    var colors: Set<String> = []
    var capacities: Set<String> = []
    var tagIDs: Set<Int64> = []
    var transferInRange: DateRangeFilter?
    var selloutRange: DateRangeFilter?
    /// Complete-record date range. It matches records whose inventory lifecycle
    /// overlaps the selected days, regardless of which event type falls inside.
    var recordRange: DateRangeFilter?
    var inStockOnly: Bool = false
    var goodOnly: Bool = false
    var excludeDemoAndNoRecord: Bool = false

    static var defaultInventory: InventoryFilter {
        var filter = InventoryFilter()
        filter.inStockOnly = true
        filter.goodOnly = true
        filter.excludeDemoAndNoRecord = true
        return filter
    }

    var isDefaultScope: Bool {
        inStockOnly && goodOnly && excludeDemoAndNoRecord &&
            activeFacetCount == 0 &&
            transferInRange == nil &&
            selloutRange == nil &&
            recordRange == nil
    }

    var isEmpty: Bool {
        activeFacetCount == 0
    }

    var activeFacetCount: Int {
        var count = 0
        if !statuses.isEmpty { count += 1 }
        if !conditions.isEmpty { count += 1 }
        if !lobs.isEmpty { count += 1 }
        if !subLOBs.isEmpty { count += 1 }
        if !colors.isEmpty { count += 1 }
        if !capacities.isEmpty { count += 1 }
        if !tagIDs.isEmpty { count += 1 }
        if transferInRange != nil { count += 1 }
        if selloutRange != nil { count += 1 }
        if recordRange != nil { count += 1 }
        return count
    }

    func matches(_ item: InventoryItem, legacyOutAsSales: Bool = false) -> Bool {
        if inStockOnly && !item.isInInventory { return false }
        if goodOnly && item.condition != .good { return false }
        if excludeDemoAndNoRecord && (item.condition == .demo || item.hasNoRecordSaleTag) { return false }
        if !statuses.isEmpty {
            let rawMatch = statuses.contains(item.transactionType.rawValue)
            let legacySaleMatch = statuses.contains(TransactionType.sellout.rawValue) &&
                item.isLegacyOutSale(enabled: legacyOutAsSales)
            if !rawMatch && !legacySaleMatch { return false }
        }
        if !conditions.isEmpty && !conditions.contains(item.condition.rawValue) { return false }
        if !lobs.isEmpty && !lobs.contains(item.displayCategory) { return false }
        if !subLOBs.isEmpty && !subLOBs.contains(item.displayModel) { return false }
        if !colors.isEmpty && !colors.contains(item.displayColor) { return false }
        if !capacities.isEmpty && !capacities.contains(item.displayCapacity) { return false }
        if !tagIDs.isEmpty {
            let itemTagIDs = Set(item.tags.map { $0.id })
            if itemTagIDs.isDisjoint(with: tagIDs) { return false }
        }
        if let range = transferInRange, !range.contains(item.transferInDate) { return false }
        if let range = selloutRange, !range.contains(item.saleDate(legacyOutAsSales: legacyOutAsSales)) { return false }
        if let range = recordRange, !item.overlapsRecordRange(range) { return false }
        return true
    }

    mutating func clear() {
        self = InventoryFilter()
    }
}

// MARK: - Filter options

struct FilterOption: Identifiable, Hashable {
    var value: String
    var label: String
    var count: Int
    var id: String { value }
}

struct TagFilterOption: Identifiable, Hashable {
    var id: Int64
    var name: String
    var count: Int
    var colorIndex: Int
}

struct FilterOptions {
    var statuses: [FilterOption] = []
    var conditions: [FilterOption] = []
    var lobs: [FilterOption] = []
    var subLOBs: [FilterOption] = []
    var colors: [FilterOption] = []
    var capacities: [FilterOption] = []
    var tags: [TagFilterOption] = []

    static func make(items: [InventoryItem], allTags: [Tag]) -> FilterOptions {
        func options(_ values: [(String, String)]) -> [FilterOption] {
            var counts: [String: Int] = [:]
            var labels: [String: String] = [:]
            for (value, label) in values {
                counts[value, default: 0] += 1
                labels[value] = label
            }
            return counts.map { value, count in
                FilterOption(value: value, label: labels[value] ?? value, count: count)
            }.sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }
        }

        var optionCounts: [String: Int] = [:]
        var tagCounts: [Int64: Int] = [:]

        for item in items {
            optionCounts[item.transactionType.rawValue, default: 0] += 1
            optionCounts["condition:" + item.condition.rawValue, default: 0] += 1
            optionCounts["lob:" + item.displayCategory, default: 0] += 1
            optionCounts["sub:" + item.displayModel, default: 0] += 1
            optionCounts["color:" + item.displayColor, default: 0] += 1
            optionCounts["capacity:" + item.displayCapacity, default: 0] += 1
            for tag in item.tags { tagCounts[tag.id, default: 0] += 1 }
        }

        func counted(_ prefix: String) -> [FilterOption] {
            optionCounts.compactMap { key, count -> FilterOption? in
                guard key.hasPrefix(prefix) else { return nil }
                let value = String(key.dropFirst(prefix.count))
                return FilterOption(value: value, label: value, count: count)
            }.sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }
        }

        var result = FilterOptions()
        result.statuses = TransactionType.allCases.filter { $0 != .unknown }.map {
            FilterOption(
                value: $0.rawValue,
                label: $0.title + " · " + $0.rawDisplayName,
                count: optionCounts[$0.rawValue] ?? 0
            )
        }
        result.conditions = ItemCondition.allCases.map {
            FilterOption(
                value: $0.rawValue,
                label: $0.title,
                count: optionCounts["condition:" + $0.rawValue] ?? 0
            )
        }.filter { $0.count > 0 }
        result.lobs = counted("lob:")
        result.subLOBs = counted("sub:")
        result.colors = counted("color:")
        result.capacities = counted("capacity:").sorted {
            $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
        result.tags = allTags.map {
            TagFilterOption(id: $0.id, name: $0.name, count: tagCounts[$0.id] ?? 0, colorIndex: $0.colorIndex)
        }.filter { $0.count > 0 }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return result
    }
}

// MARK: - Store & import reports

struct StoreSummary: Identifiable, Equatable {
    var id: String { storeID }

    var storeID: String
    var fileURL: URL
    var itemCount: Int
    var stockCount: Int
    var soldCount: Int
    var tagCount: Int
    var lastImportAt: Date?
    var lastEOHImportAt: Date?
    var lastLOGImportAt: Date?
    var fileSize: Int64

    var displayName: String { "Store \(storeID)" }
    var fileName: String { "\(storeID).ngbd" }
}

enum ImportKind: String {
    case eoh = "EOH"
    case log = "LOG"

    var title: String {
        switch self {
        case .eoh: return "现有库存"
        case .log: return "销售记录"
        }
    }
}

struct StoreImportResult: Identifiable, Equatable {
    var id: String { storeID }

    var storeID: String
    var eohRows: Int
    var logRows: Int
    var returnedRows: Int
    var transferOutRows: Int
    var newItems: Int
    var updatedItems: Int
    var totalItems: Int
    var stockCount: Int
    var createdDatabase: Bool
    var databaseFileName: String
    var earliestRecordDate: Date?
    var latestRecordDate: Date?

    var recordDateRangeText: String {
        guard let earliest = earliestRecordDate, let latest = latestRecordDate else {
            return "无日期记录"
        }
        let calendar = Calendar.current
        if calendar.isDate(earliest, inSameDayAs: latest) {
            return DateFormatter.gbMediumDate.string(from: earliest)
        }
        return "\(DateFormatter.gbMediumDate.string(from: earliest)) – \(DateFormatter.gbMediumDate.string(from: latest))"
    }
}

struct ImportReport: Identifiable, Equatable {
    var id = UUID()
    var importedAt: Date
    var files: [String]
    var results: [StoreImportResult]
    var warnings: [String]
}

struct AppAlert: Identifiable {
    var id = UUID()
    var title: String
    var message: String
}

// MARK: - String convenience

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}
