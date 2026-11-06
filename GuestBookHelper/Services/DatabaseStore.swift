import Foundation

struct DatabaseSnapshot: Identifiable, Codable, Equatable {
    var id: String
    var storeID: String
    var fileName: String
    var reason: String
    var createdAt: Date
}

final class DatabaseStore {
    let rootURL: URL
    let storesURL: URL
    let snapshotsURL: URL

    init(baseURL: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let base = baseURL ?? documents
        rootURL = base.appendingPathComponent("GuestBook", isDirectory: true)
        storesURL = rootURL.appendingPathComponent("Stores", isDirectory: true)
        snapshotsURL = rootURL.appendingPathComponent("Snapshots", isDirectory: true)
        createDirectoriesIfNeeded()
    }

    private func createDirectoriesIfNeeded() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: storesURL.path) {
            try? fileManager.createDirectory(at: storesURL, withIntermediateDirectories: true, attributes: nil)
        }
        if !fileManager.fileExists(atPath: snapshotsURL.path) {
            try? fileManager.createDirectory(at: snapshotsURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    func fileURL(forStoreID storeID: String) -> URL {
        storesURL.appendingPathComponent("\(storeID).ngbd", isDirectory: false)
    }

    func databaseExists(forStoreID storeID: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(forStoreID: storeID).path)
    }

    func allStoreIDs() -> [String] {
        createDirectoriesIfNeeded()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: storesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "ngbd" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }

    func openStore(_ storeID: String) throws -> StoreDatabase {
        createDirectoriesIfNeeded()
        return try StoreDatabase(fileURL: fileURL(forStoreID: storeID), storeID: storeID)
    }

    func summaries(legacyOutAsSales: Bool = false) -> [StoreSummary] {
        var result: [StoreSummary] = []
        for storeID in allStoreIDs() {
            guard let database = try? openStore(storeID) else { continue }
            defer { database.close() }
            if let summary = try? database.summary(legacyOutAsSales: legacyOutAsSales) {
                result.append(summary)
            }
        }
        return result.sorted { lhs, rhs in
            let left = lhs.lastImportAt ?? .distantPast
            let right = rhs.lastImportAt ?? .distantPast
            if left != right { return left > right }
            return lhs.storeID.localizedStandardCompare(rhs.storeID) == .orderedAscending
        }
    }

    func summary(forStoreID storeID: String, legacyOutAsSales: Bool = false) -> StoreSummary? {
        guard let database = try? openStore(storeID) else { return nil }
        defer { database.close() }
        return try? database.summary(legacyOutAsSales: legacyOutAsSales)
    }

    @discardableResult
    func deleteStore(_ storeID: String) -> Bool {
        let fileManager = FileManager.default
        let fileURL = self.fileURL(forStoreID: storeID)
        var removed = false
        for suffix in ["", "-journal", "-wal", "-shm"] {
            let path = fileURL.path + suffix
            if fileManager.fileExists(atPath: path) {
                try? fileManager.removeItem(atPath: path)
                removed = true
            }
        }
        try? fileManager.removeItem(at: snapshotDirectory(forStoreID: storeID))
        return removed
    }

    // MARK: - Snapshots

    private func snapshotDirectory(forStoreID storeID: String) -> URL {
        snapshotsURL.appendingPathComponent(storeID, isDirectory: true)
    }

    private func manifestURL(forStoreID storeID: String) -> URL {
        snapshotDirectory(forStoreID: storeID).appendingPathComponent("manifest.json")
    }

    func snapshots(forStoreID storeID: String) -> [DatabaseSnapshot] {
        guard let data = try? Data(contentsOf: manifestURL(forStoreID: storeID)),
              let decoded = try? JSONDecoder().decode([DatabaseSnapshot].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func writeSnapshots(_ snapshots: [DatabaseSnapshot], forStoreID storeID: String) throws {
        let dir = snapshotDirectory(forStoreID: storeID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        let data = try JSONEncoder().encode(snapshots)
        try data.write(to: manifestURL(forStoreID: storeID), options: .atomic)
    }

    @discardableResult
    func createSnapshot(forStoreID storeID: String, reason: String, keep maximum: Int = 3) throws -> DatabaseSnapshot? {
        let fileManager = FileManager.default
        let databaseURL = fileURL(forStoreID: storeID)
        guard fileManager.fileExists(atPath: databaseURL.path) else { return nil }
        let dir = snapshotDirectory(forStoreID: storeID)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

        let now = Date()
        let id = "\(Int(now.timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8))"
        let fileName = "snapshot-\(id).ngbd"
        let snapshotURL = dir.appendingPathComponent(fileName)
        try fileManager.copyItem(at: databaseURL, to: snapshotURL)

        var entries = snapshots(forStoreID: storeID)
        entries.insert(DatabaseSnapshot(id: id, storeID: storeID, fileName: fileName, reason: reason, createdAt: now), at: 0)
        entries.sort { $0.createdAt > $1.createdAt }
        if entries.count > maximum {
            let removed = entries.suffix(from: maximum)
            for entry in removed {
                try? fileManager.removeItem(at: dir.appendingPathComponent(entry.fileName))
            }
            entries = Array(entries.prefix(maximum))
        }
        try writeSnapshots(entries, forStoreID: storeID)
        return entries.first
    }

    func restoreSnapshot(_ snapshot: DatabaseSnapshot, forStoreID storeID: String) throws {
        let fileManager = FileManager.default
        let dir = snapshotDirectory(forStoreID: storeID)
        let source = dir.appendingPathComponent(snapshot.fileName)
        guard fileManager.fileExists(atPath: source.path) else {
            throw DatabaseError.openFailed("快照文件不存在")
        }
        _ = try createSnapshot(forStoreID: storeID, reason: "回退前自动备份")

        let destination = fileURL(forStoreID: storeID)
        let temp = storesURL.appendingPathComponent(".restore-\(UUID().uuidString).ngbd")
        try fileManager.copyItem(at: source, to: temp)
        for suffix in ["-journal", "-wal", "-shm"] {
            try? fileManager.removeItem(atPath: destination.path + suffix)
        }
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temp)
        } else {
            try fileManager.moveItem(at: temp, to: destination)
        }
    }

    // MARK: - .ngbd import

    func importDatabaseFile(from url: URL, mergeExisting: Bool) throws -> String {
        let fileManager = FileManager.default
        let storeID = InventorySpreadsheetParser.normalizedStoreID(url.deletingPathExtension().lastPathComponent) ?? ""
        let normalizedID = storeID.isEmpty ? url.deletingPathExtension().lastPathComponent : storeID
        let destination = fileURL(forStoreID: normalizedID)
        guard url.standardizedFileURL != destination.standardizedFileURL else {
            throw DatabaseError.openFailed("不能导入应用内正在使用的同名数据库")
        }
        guard let header = try? Data(contentsOf: url).prefix(16),
              header == Data("SQLite format 3\u{0}".utf8) else {
            throw DatabaseError.openFailed("不是有效的 .ngbd / SQLite 数据库文件")
        }

        let exists = fileManager.fileExists(atPath: destination.path)
        if exists && !mergeExisting {
            return normalizedID
        }

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).ngbd")
        try fileManager.copyItem(at: url, to: temp)
        defer { try? fileManager.removeItem(at: temp) }

        if exists {
            _ = try createSnapshot(forStoreID: normalizedID, reason: "合并数据库")
            let source = try StoreDatabase(fileURL: temp, storeID: normalizedID)
            defer { source.close() }
            let target = try openStore(normalizedID)
            defer { target.close() }
            do {
                try target.merge(from: source)
            } catch {
                throw error
            }
        } else {
            for suffix in ["-journal", "-wal", "-shm"] {
                try? fileManager.removeItem(atPath: destination.path + suffix)
            }
            try fileManager.copyItem(at: temp, to: destination)
            let database = try openStore(normalizedID)
            database.close()
        }
        return normalizedID
    }

    func totalDatabaseBytes() -> Int64 {
        var total: Int64 = 0
        for storeID in allStoreIDs() {
            let path = fileURL(forStoreID: storeID).path
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attributes[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }
}
