import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DatabaseError: LocalizedError {
    case openFailed(String)
    case sqlFailed(String)
    case invalidDatabase(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "无法打开数据库：\(message)"
        case .sqlFailed(let message): return "数据库操作失败：\(message)"
        case .invalidDatabase(let message): return "数据库文件无效：\(message)"
        }
    }
}

struct BatchApplyStats {
    var newItems: Int
    var updatedItems: Int
    var totalItems: Int
    var stockCount: Int
}

struct ImportHistoryEntry: Identifiable {
    var id: Int64
    var kind: String
    var fileName: String
    var importedAt: Date
    var rowCount: Int
}

final class StoreDatabase {
    let storeID: String
    let fileURL: URL
    private var db: OpaquePointer?

    init(fileURL: URL, storeID: String) throws {
        self.fileURL = fileURL
        self.storeID = storeID
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(fileURL.path, &handle, flags, nil)
        guard result == SQLITE_OK, let opened = handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
            if let handle = handle { sqlite3_close(handle) }
            throw DatabaseError.openFailed(message)
        }
        db = opened
        sqlite3_busy_timeout(opened, 3_000)
        do {
            try execute("PRAGMA foreign_keys = ON;")
            try execute("PRAGMA journal_mode = DELETE;")
            try execute("PRAGMA synchronous = FULL;")
            try migrate()
        } catch {
            sqlite3_close(opened)
            db = nil
            throw error
        }
    }

    deinit {
        close()
    }

    func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    // MARK: - Schema

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS items (
            serial_number TEXT PRIMARY KEY,
            transaction_type TEXT NOT NULL,
            mpn TEXT NOT NULL DEFAULT '',
            lob TEXT NOT NULL DEFAULT '',
            sub_lob TEXT NOT NULL DEFAULT '',
            color TEXT NOT NULL DEFAULT '',
            capacity TEXT NOT NULL DEFAULT '',
            transfer_in_date REAL,
            sellout_date REAL,
            returned_date REAL,
            transfer_out_date REAL,
            created_date REAL,
            store_id TEXT NOT NULL,
            condition TEXT NOT NULL DEFAULT 'UNKNOWN',
            present_in_latest_eoh INTEGER NOT NULL DEFAULT 0,
            first_imported_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_items_lob ON items(lob);
        CREATE INDEX IF NOT EXISTS idx_items_condition ON items(condition);
        CREATE INDEX IF NOT EXISTS idx_items_transaction ON items(transaction_type);
        CREATE INDEX IF NOT EXISTS idx_items_transfer_date ON items(transfer_in_date);
        CREATE INDEX IF NOT EXISTS idx_items_sellout_date ON items(sellout_date);
        CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL COLLATE NOCASE UNIQUE,
            color_index INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS item_tags (
            serial_number TEXT NOT NULL,
            tag_id INTEGER NOT NULL,
            PRIMARY KEY (serial_number, tag_id),
            FOREIGN KEY (serial_number) REFERENCES items(serial_number) ON DELETE CASCADE,
            FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_item_tags_tag ON item_tags(tag_id);
        CREATE TABLE IF NOT EXISTS import_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            file_name TEXT NOT NULL,
            imported_at REAL NOT NULL,
            row_count INTEGER NOT NULL,
            detail TEXT NOT NULL DEFAULT ''
        );
        """)
        try execute("INSERT OR IGNORE INTO tags(name, color_index, created_at) VALUES('\(SystemTag.noRecordSaleName)', \(SystemTag.noRecordSaleColorIndex), 0);")
        let columns = tableColumns("items")
        if !columns.contains("returned_date") {
            try execute("ALTER TABLE items ADD COLUMN returned_date REAL;")
        }
        if !columns.contains("transfer_out_date") {
            try execute("ALTER TABLE items ADD COLUMN transfer_out_date REAL;")
        }
        try execute("CREATE INDEX IF NOT EXISTS idx_items_returned_date ON items(returned_date);")
        try execute("CREATE INDEX IF NOT EXISTS idx_items_transfer_out_date ON items(transfer_out_date);")
        setMeta("schema_version", "3")
        if metaValue(for: "store_id") == nil {
            setMeta("store_id", storeID)
        }
    }

    private func tableColumns(_ table: String) -> Set<String> {
        guard let statement = try? prepare("PRAGMA table_info(\(table));") else { return [] }
        defer { finalize(statement) }
        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            columns.insert(text(statement, 1))
        }
        return columns
    }

    private func requireDB() throws -> OpaquePointer {
        guard let db = db else { throw DatabaseError.invalidDatabase("连接已关闭") }
        return db
    }

    private func execute(_ sql: String) throws {
        let handle = try requireDB()
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "未知 SQL 错误"
            if let errorMessage = errorMessage { sqlite3_free(errorMessage) }
            throw DatabaseError.sqlFailed(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        let handle = try requireDB()
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &statement, nil) != SQLITE_OK {
            throw DatabaseError.sqlFailed(String(cString: sqlite3_errmsg(handle)))
        }
        guard let statement = statement else {
            throw DatabaseError.sqlFailed("无法创建 SQL 语句")
        }
        return statement
    }

    private func finalize(_ statement: OpaquePointer?) {
        if let statement = statement { sqlite3_finalize(statement) }
    }

    private func bindText(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value = value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindDate(_ statement: OpaquePointer, _ index: Int32, _ value: Date?) {
        if let value = value {
            sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private func date(_ statement: OpaquePointer, _ index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    // MARK: - Metadata

    func metaValue(for key: String) -> String? {
        guard let statement = try? prepare("SELECT value FROM meta WHERE key = ? LIMIT 1;") else { return nil }
        defer { finalize(statement) }
        bindText(statement, 1, key)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(statement, 0)
    }

    private func setMeta(_ key: String, _ value: String) {
        guard let statement = try? prepare("""
        INSERT INTO meta(key, value) VALUES(?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;
        """) else { return }
        defer { finalize(statement) }
        bindText(statement, 1, key)
        bindText(statement, 2, value)
        _ = sqlite3_step(statement)
    }

    private func metaDate(_ key: String) -> Date? {
        guard let raw = metaValue(for: key), let value = Double(raw) else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    // MARK: - Reading

    func fetchItems() throws -> [InventoryItem] {
        var items = try fetchItemsRaw()
        var tagsBySerial: [String: [Tag]] = [:]
        let statement = try prepare("""
        SELECT it.serial_number, t.id, t.name, t.color_index
        FROM item_tags it
        JOIN tags t ON t.id = it.tag_id
        ORDER BY t.name COLLATE NOCASE ASC;
        """)
        defer { finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            let serial = text(statement, 0)
            let tag = Tag(
                id: sqlite3_column_int64(statement, 1),
                name: text(statement, 2),
                colorIndex: Int(sqlite3_column_int(statement, 3)),
                itemCount: 0
            )
            tagsBySerial[serial, default: []].append(tag)
        }
        for index in items.indices {
            items[index].tags = tagsBySerial[items[index].serialNumber] ?? []
        }
        return items
    }

    func fetchItemsRaw() throws -> [InventoryItem] {
        let statement = try prepare("""
        SELECT serial_number, transaction_type, mpn, lob, sub_lob, color, capacity,
               transfer_in_date, sellout_date, returned_date, transfer_out_date, created_date, store_id, condition,
               present_in_latest_eoh, updated_at
        FROM items
        ORDER BY COALESCE(created_date, updated_at) DESC, serial_number ASC;
        """)
        defer { finalize(statement) }
        var items: [InventoryItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let item = InventoryItem(
                serialNumber: text(statement, 0),
                transactionType: TransactionType(rawValue: text(statement, 1)) ?? .unknown,
                mpn: text(statement, 2),
                lob: text(statement, 3),
                subLOB: text(statement, 4),
                color: text(statement, 5),
                capacity: text(statement, 6),
                transferInDate: date(statement, 7),
                selloutDate: date(statement, 8),
                returnedDate: date(statement, 9),
                transferOutDate: date(statement, 10),
                createdAt: date(statement, 11),
                storeID: text(statement, 12),
                condition: ItemCondition(rawValue: text(statement, 13)) ?? .unknown,
                presentInLatestEOH: sqlite3_column_int(statement, 14) == 1,
                updatedAt: date(statement, 15) ?? Date(timeIntervalSince1970: 0),
                tags: []
            )
            items.append(item)
        }
        return items
    }

    func fetchTags() throws -> [Tag] {
        let statement = try prepare("""
        SELECT t.id, t.name, t.color_index, COUNT(it.serial_number)
        FROM tags t
        LEFT JOIN item_tags it ON it.tag_id = t.id
        GROUP BY t.id, t.name, t.color_index
        ORDER BY t.name COLLATE NOCASE ASC;
        """)
        defer { finalize(statement) }
        var tags: [Tag] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            tags.append(Tag(
                id: sqlite3_column_int64(statement, 0),
                name: text(statement, 1),
                colorIndex: Int(sqlite3_column_int(statement, 2)),
                itemCount: Int(sqlite3_column_int(statement, 3))
            ))
        }
        return tags
    }

    func importHistory(limit: Int = 20) -> [ImportHistoryEntry] {
        guard let statement = try? prepare("""
        SELECT id, kind, file_name, imported_at, row_count
        FROM import_history ORDER BY imported_at DESC LIMIT ?;
        """) else { return [] }
        defer { finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))
        var entries: [ImportHistoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            entries.append(ImportHistoryEntry(
                id: sqlite3_column_int64(statement, 0),
                kind: text(statement, 1),
                fileName: text(statement, 2),
                importedAt: date(statement, 3) ?? Date(),
                rowCount: Int(sqlite3_column_int(statement, 4))
            ))
        }
        return entries
    }

    private static var stockPredicate: String {
        """
        NOT EXISTS (
            SELECT 1 FROM item_tags it
            JOIN tags t ON t.id = it.tag_id
            WHERE it.serial_number = items.serial_number
              AND t.name COLLATE NOCASE = '\(SystemTag.noRecordSaleName)'
        )
        AND (
            (transaction_type = 'RETURNED' AND condition IN ('GOOD', 'UNKNOWN'))
            OR (transaction_type = 'TRANSFER_IN' AND condition = 'GOOD' AND present_in_latest_eoh = 1)
        )
        """
    }

    func summary(legacyOutAsSales: Bool = false) throws -> StoreSummary {
        func scalarInt(_ sql: String) -> Int {
            guard let statement = try? prepare(sql) else { return 0 }
            defer { finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(statement, 0))
        }
        let itemCount = scalarInt("SELECT COUNT(*) FROM items;")
        let stockCount = scalarInt("SELECT COUNT(*) FROM items WHERE \(Self.stockPredicate);")
        let soldCount: Int
        if legacyOutAsSales {
            let cutoff = InventoryItem.legacyOutSalesCutoff.timeIntervalSince1970
            soldCount = scalarInt("SELECT COUNT(*) FROM items WHERE transaction_type = 'SELLOUT' OR (transaction_type = 'TRANSFER_OUT' AND transfer_out_date IS NOT NULL AND transfer_out_date <= \(cutoff));")
        } else {
            soldCount = scalarInt("SELECT COUNT(*) FROM items WHERE transaction_type = 'SELLOUT';")
        }
        let tagCount = scalarInt("SELECT COUNT(*) FROM tags;")
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return StoreSummary(
            storeID: storeID,
            fileURL: fileURL,
            itemCount: itemCount,
            stockCount: stockCount,
            soldCount: soldCount,
            tagCount: tagCount,
            lastImportAt: metaDate("last_import_at"),
            lastEOHImportAt: metaDate("last_eoh_import_at"),
            lastLOGImportAt: metaDate("last_log_import_at"),
            fileSize: size
        )
    }

    // MARK: - Import

    func applyBatch(
        eohRows: [SpreadsheetRow],
        logRows: [SpreadsheetRow],
        eohSourceFiles: [String],
        logSourceFiles: [String],
        now: Date = Date()
    ) throws -> BatchApplyStats {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            if !eohRows.isEmpty {
                try execute("UPDATE items SET present_in_latest_eoh = 0;")
            }
            var existing = Dictionary(uniqueKeysWithValues: try fetchItemsRaw().map { ($0.serialNumber, $0) })
            let existingSerials = Set(existing.keys)
            var touchedSerials = Set<String>()
            var mergedItems: [String: InventoryItem] = [:]

            for row in eohRows {
                var item = existing[row.serialNumber] ?? Self.emptyItem(serial: row.serialNumber, storeID: storeID, now: now)
                Self.merge(&item, with: row, kind: .eoh, now: now)
                existing[row.serialNumber] = item
                mergedItems[row.serialNumber] = item
                touchedSerials.insert(row.serialNumber)
            }
            for row in logRows {
                var item = existing[row.serialNumber] ?? Self.emptyItem(serial: row.serialNumber, storeID: storeID, now: now)
                Self.merge(&item, with: row, kind: .log, now: now)
                existing[row.serialNumber] = item
                mergedItems[row.serialNumber] = item
                touchedSerials.insert(row.serialNumber)
            }

            for serial in touchedSerials {
                guard let item = mergedItems[serial] else { continue }
                try upsert(item)
            }

            let newCount = touchedSerials.subtracting(existingSerials).count
            let updatedCount = touchedSerials.count - newCount
            let total = try count("SELECT COUNT(*) FROM items;")
            let stock = try count("SELECT COUNT(*) FROM items WHERE \(Self.stockPredicate);")

            setMeta("store_id", storeID)
            setMeta("last_import_at", String(now.timeIntervalSince1970))
            if !eohRows.isEmpty {
                setMeta("last_eoh_import_at", String(now.timeIntervalSince1970))
            }
            if !logRows.isEmpty {
                setMeta("last_log_import_at", String(now.timeIntervalSince1970))
            }
            let allSources = Array(Set(eohSourceFiles + logSourceFiles)).sorted()
            setMeta("last_source_files", allSources.joined(separator: ", "))

            if !eohRows.isEmpty {
                try recordHistory(kind: "EOH", fileNames: eohSourceFiles, importedAt: now, rowCount: eohRows.count)
            }
            if !logRows.isEmpty {
                try recordHistory(kind: "LOG", fileNames: logSourceFiles, importedAt: now, rowCount: logRows.count)
            }
            try execute("COMMIT;")
            return BatchApplyStats(newItems: newCount, updatedItems: updatedCount, totalItems: total, stockCount: stock)
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func recordHistory(kind: String, fileNames: [String], importedAt: Date, rowCount: Int) throws {
        let statement = try prepare("INSERT INTO import_history(kind, file_name, imported_at, row_count, detail) VALUES(?, ?, ?, ?, ?);")
        defer { finalize(statement) }
        bindText(statement, 1, kind)
        bindText(statement, 2, fileNames.joined(separator: ", "))
        bindDate(statement, 3, importedAt)
        sqlite3_bind_int(statement, 4, Int32(rowCount))
        bindText(statement, 5, "\(rowCount) 行")
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.sqlFailed(String(cString: sqlite3_errmsg(try requireDB())))
        }
    }

    private func count(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func emptyItem(serial: String, storeID: String, now: Date) -> InventoryItem {
        InventoryItem(
            serialNumber: serial,
            transactionType: .unknown,
            mpn: "",
            lob: "",
            subLOB: "",
            color: "",
            capacity: "",
            transferInDate: nil,
            selloutDate: nil,
            returnedDate: nil,
            transferOutDate: nil,
            createdAt: nil,
            storeID: storeID,
            condition: .unknown,
            presentInLatestEOH: false,
            updatedAt: now,
            tags: []
        )
    }

    private static func merge(_ item: inout InventoryItem, with row: SpreadsheetRow, kind: ImportKind, now: Date) {
        item.serialNumber = row.serialNumber
        item.storeID = row.storeID
        if let value = row.mpn.nilIfEmpty { item.mpn = value }
        if let value = row.lob.nilIfEmpty { item.lob = value }
        if let value = row.subLOB.nilIfEmpty { item.subLOB = value }
        if let value = row.color.nilIfEmpty { item.color = value }
        if let value = row.capacity.nilIfEmpty { item.capacity = value }
        if row.condition != .unknown { item.condition = row.condition }

        switch kind {
        case .eoh:
            item.presentInLatestEOH = true
            if let date = row.date {
                switch row.transactionType {
                case .transferIn:
                    item.transferInDate = Self.later(item.transferInDate, date)
                case .sellout:
                    item.selloutDate = Self.later(item.selloutDate, date)
                case .returned:
                    item.returnedDate = Self.later(item.returnedDate, date)
                case .transferOut:
                    item.transferOutDate = Self.later(item.transferOutDate, date)
                case .unknown:
                    break
                }
            }
            // The latest EOH snapshot is authoritative for items it contains.
            if row.transactionType != .unknown {
                item.transactionType = row.transactionType
            }
        case .log:
            if let date = row.date {
                switch row.transactionType {
                case .transferIn:
                    item.transferInDate = Self.later(item.transferInDate, date)
                case .sellout:
                    item.selloutDate = Self.later(item.selloutDate, date)
                case .returned:
                    item.returnedDate = Self.later(item.returnedDate, date)
                case .transferOut:
                    item.transferOutDate = Self.later(item.transferOutDate, date)
                case .unknown:
                    break
                }
                if let latest = Self.latestStatus(for: item) {
                    item.transactionType = latest
                }
            } else if row.transactionType != .unknown && item.transactionType == .unknown {
                item.transactionType = row.transactionType
            }
        }
        item.createdAt = item.transferInDate ?? item.returnedDate ?? item.transferOutDate ?? item.selloutDate
        item.updatedAt = now
    }

    private static func latestStatus(for item: InventoryItem) -> TransactionType? {
        let candidates: [(type: TransactionType, date: Date, priority: Int)] = [
            (item.transferInDate.map { (.transferIn, $0, 1) }),
            (item.returnedDate.map { (.returned, $0, 2) }),
            (item.transferOutDate.map { (.transferOut, $0, 3) }),
            (item.selloutDate.map { (.sellout, $0, 0) })
        ].compactMap { $0 }
        guard let latest = candidates.max(by: { lhs, rhs in
            if lhs.date == rhs.date { return lhs.priority < rhs.priority }
            return lhs.date < rhs.date
        }) else { return nil }
        return latest.type
    }

    private static func later(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs = lhs else { return rhs }
        return max(lhs, rhs)
    }

    func upsert(_ item: InventoryItem) throws {
        let statement = try prepare("""
        INSERT INTO items(
            serial_number, transaction_type, mpn, lob, sub_lob, color, capacity,
            transfer_in_date, sellout_date, returned_date, transfer_out_date, created_date, store_id, condition,
            present_in_latest_eoh, first_imported_at, updated_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(serial_number) DO UPDATE SET
            transaction_type = excluded.transaction_type,
            mpn = excluded.mpn,
            lob = excluded.lob,
            sub_lob = excluded.sub_lob,
            color = excluded.color,
            capacity = excluded.capacity,
            transfer_in_date = excluded.transfer_in_date,
            sellout_date = excluded.sellout_date,
            returned_date = excluded.returned_date,
            transfer_out_date = excluded.transfer_out_date,
            created_date = excluded.created_date,
            store_id = excluded.store_id,
            condition = excluded.condition,
            present_in_latest_eoh = excluded.present_in_latest_eoh,
            updated_at = excluded.updated_at;
        """)
        defer { finalize(statement) }
        bindText(statement, 1, item.serialNumber)
        bindText(statement, 2, item.transactionType.rawValue)
        bindText(statement, 3, item.mpn)
        bindText(statement, 4, item.lob)
        bindText(statement, 5, item.subLOB)
        bindText(statement, 6, item.color)
        bindText(statement, 7, item.capacity)
        bindDate(statement, 8, item.transferInDate)
        bindDate(statement, 9, item.selloutDate)
        bindDate(statement, 10, item.returnedDate)
        bindDate(statement, 11, item.transferOutDate)
        bindDate(statement, 12, item.createdAt)
        bindText(statement, 13, item.storeID)
        bindText(statement, 14, item.condition.rawValue)
        sqlite3_bind_int(statement, 15, item.presentInLatestEOH ? 1 : 0)
        sqlite3_bind_double(statement, 16, item.updatedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 17, item.updatedAt.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.sqlFailed(String(cString: sqlite3_errmsg(try requireDB())))
        }
    }

    // MARK: - Merge

    func merge(from source: StoreDatabase) throws {
        let targetItems = try fetchItems()
        let sourceItems = try source.fetchItems()
        let targetTags = try fetchTags()
        let sourceTags = try source.fetchTags()

        var targetTagsByName: [String: Tag] = [:]
        for tag in targetTags {
            targetTagsByName[tag.name.lowercased()] = tag
        }
        var sourceTagMap: [Int64: Int64] = [:]
        for tag in sourceTags {
            let key = tag.name.lowercased()
            if let existing = targetTagsByName[key] {
                sourceTagMap[tag.id] = existing.id
            } else {
                let created = try createTag(named: tag.name)
                targetTagsByName[key] = created
                sourceTagMap[tag.id] = created.id
            }
        }

        let targetBySerial = Dictionary(uniqueKeysWithValues: targetItems.map { ($0.serialNumber, $0) })
        for sourceItem in sourceItems {
            let existing = targetBySerial[sourceItem.serialNumber]
            var merged = existing ?? sourceItem
            if let existing = existing {
                if merged.mpn.isEmpty { merged.mpn = sourceItem.mpn }
                if merged.lob.isEmpty { merged.lob = sourceItem.lob }
                if merged.subLOB.isEmpty { merged.subLOB = sourceItem.subLOB }
                if merged.color.isEmpty { merged.color = sourceItem.color }
                if merged.capacity.isEmpty { merged.capacity = sourceItem.capacity }
                if merged.condition == .unknown { merged.condition = sourceItem.condition }
                if merged.createdAt == nil { merged.createdAt = sourceItem.createdAt }
                merged.transferInDate = newest(merged.transferInDate, sourceItem.transferInDate)
                merged.selloutDate = newest(merged.selloutDate, sourceItem.selloutDate)
                merged.returnedDate = newest(merged.returnedDate, sourceItem.returnedDate)
                merged.transferOutDate = newest(merged.transferOutDate, sourceItem.transferOutDate)
                merged.presentInLatestEOH = merged.presentInLatestEOH || sourceItem.presentInLatestEOH
                merged.updatedAt = max(merged.updatedAt, sourceItem.updatedAt)
                if let sourceLatest = sourceItem.latestEventDate,
                   let targetLatest = existing.latestEventDate,
                   sourceLatest > targetLatest {
                    merged.transactionType = sourceItem.transactionType
                }
            }
            merged.storeID = storeID
            merged.tags = []
            try upsert(merged)

            var tagIDs = Set((existing?.tags ?? []).map { $0.id })
            for sourceTag in sourceItem.tags {
                if let mapped = sourceTagMap[sourceTag.id] {
                    tagIDs.insert(mapped)
                }
            }
            try setTags(serialNumber: merged.serialNumber, tagIDs: tagIDs)
        }
    }

    private func newest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        [lhs, rhs].compactMap { $0 }.max()
    }

    // MARK: - Tags

    @discardableResult
    func createTag(named rawName: String) throws -> Tag {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw DatabaseError.sqlFailed("标签名称不能为空") }
        let limited = String(name.prefix(24))
        let existing = try findTag(named: limited)
        if let existing = existing { return existing }
        let nextColor = (try? count("SELECT COUNT(*) FROM tags;")) ?? 0
        let statement = try prepare("INSERT INTO tags(name, color_index, created_at) VALUES(?, ?, ?);")
        defer { finalize(statement) }
        bindText(statement, 1, limited)
        sqlite3_bind_int(statement, 2, Int32(nextColor % TagColor.allCases.count))
        bindDate(statement, 3, Date())
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.sqlFailed(String(cString: sqlite3_errmsg(try requireDB())))
        }
        let id = sqlite3_last_insert_rowid(try requireDB())
        return Tag(id: id, name: limited, colorIndex: nextColor % TagColor.allCases.count, itemCount: 0)
    }

    func findTag(named name: String) throws -> Tag? {
        let statement = try prepare("SELECT id, name, color_index FROM tags WHERE name = ? COLLATE NOCASE LIMIT 1;")
        defer { finalize(statement) }
        bindText(statement, 1, name)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Tag(
            id: sqlite3_column_int64(statement, 0),
            name: text(statement, 1),
            colorIndex: Int(sqlite3_column_int(statement, 2)),
            itemCount: 0
        )
    }

    func setTags(serialNumber: String, tagIDs: Set<Int64>) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let delete = try prepare("DELETE FROM item_tags WHERE serial_number = ?;")
            bindText(delete, 1, serialNumber)
            guard sqlite3_step(delete) == SQLITE_DONE else {
                finalize(delete)
                throw DatabaseError.sqlFailed(String(cString: sqlite3_errmsg(try requireDB())))
            }
            finalize(delete)
            for id in tagIDs.sorted() {
                let insert = try prepare("INSERT OR IGNORE INTO item_tags(serial_number, tag_id) VALUES(?, ?);")
                bindText(insert, 1, serialNumber)
                sqlite3_bind_int64(insert, 2, id)
                guard sqlite3_step(insert) == SQLITE_DONE else {
                    finalize(insert)
                    throw DatabaseError.sqlFailed(String(cString: sqlite3_errmsg(try requireDB())))
                }
                finalize(insert)
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func renameTag(id: Int64, newName: String) throws {
        let name = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !name.isEmpty else { throw DatabaseError.sqlFailed("标签名称不能为空") }
        let statement = try prepare("UPDATE tags SET name = ? WHERE id = ?;")
        defer { finalize(statement) }
        bindText(statement, 1, name)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.sqlFailed(String(cString: sqlite3_errmsg(try requireDB())))
        }
    }

    func deleteTag(id: Int64) throws {
        let check = try prepare("SELECT name FROM tags WHERE id = ?;")
        defer { finalize(check) }
        sqlite3_bind_int64(check, 1, id)
        if sqlite3_step(check) == SQLITE_ROW {
            let name = text(check, 0)
            if name.compare(SystemTag.noRecordSaleName, options: .caseInsensitive) == .orderedSame {
                throw DatabaseError.sqlFailed("“\(SystemTag.noRecordSaleName)”是系统标签，不能删除。")
            }
        }
        let statement = try prepare("DELETE FROM tags WHERE id = ?;")
        defer { finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.sqlFailed(String(cString: sqlite3_errmsg(try requireDB())))
        }
    }
}
