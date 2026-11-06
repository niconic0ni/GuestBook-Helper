import Foundation

enum InventoryImportError: LocalizedError {
    case noValidFiles
    case allStoresFailed([String])

    var errorDescription: String? {
        switch self {
        case .noValidFiles:
            return "没有找到可导入的 xlsx。文件名中需包含 EOH（现有库存）或 LOG（销售记录）。"
        case .allStoresFailed(let warnings):
            return "导入失败。\n" + warnings.joined(separator: "\n")
        }
    }
}

final class InventoryImporter {
    private let databaseStore: DatabaseStore

    init(databaseStore: DatabaseStore) {
        self.databaseStore = databaseStore
    }

    func importFiles(_ urls: [URL], now: Date = Date()) throws -> ImportReport {
        var warnings: [String] = []
        var processedFileNames: [String] = []
        var groups: [String: StoreImportGroup] = [:]

        for url in urls {
            guard let kind = InventorySpreadsheetParser.importKind(forFileAt: url) else {
                warnings.append("已跳过“\(url.lastPathComponent)”：文件名中需要包含 EOH 或 LOG。")
                continue
            }
            do {
                let parsed = try InventorySpreadsheetParser.parse(fileURL: url, kind: kind)
                processedFileNames.append(parsed.fileName)
                warnings.append(contentsOf: parsed.warnings)
                for row in parsed.rows {
                    var group = groups[row.storeID] ?? StoreImportGroup(storeID: row.storeID)
                    switch kind {
                    case .eoh:
                        group.eohRows.append(row)
                        group.eohFiles.insert(parsed.fileName)
                    case .log:
                        group.logRows.append(row)
                        group.logFiles.insert(parsed.fileName)
                    }
                    groups[row.storeID] = group
                }
            } catch {
                warnings.append("“\(url.lastPathComponent)”导入失败：\(error.localizedDescription)")
            }
        }

        guard !processedFileNames.isEmpty else {
            throw InventoryImportError.noValidFiles
        }

        var results: [StoreImportResult] = []
        for storeID in groups.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            guard let group = groups[storeID] else { continue }
            let existed = databaseStore.databaseExists(forStoreID: storeID)
            do {
                if existed {
                    _ = try? databaseStore.createSnapshot(forStoreID: storeID, reason: "导入报表")
                }
                let database = try databaseStore.openStore(storeID)
                defer { database.close() }
                let stats = try database.applyBatch(
                    eohRows: group.eohRows,
                    logRows: group.logRows,
                    eohSourceFiles: group.eohFiles.sorted(),
                    logSourceFiles: group.logFiles.sorted(),
                    now: now
                )
                let allRows = group.eohRows + group.logRows
                let dates = allRows.compactMap { $0.date }
                results.append(StoreImportResult(
                    storeID: storeID,
                    eohRows: group.eohRows.count,
                    logRows: group.logRows.count,
                    returnedRows: allRows.filter { $0.transactionType == .returned }.count,
                    transferOutRows: allRows.filter { $0.transactionType == .transferOut }.count,
                    newItems: stats.newItems,
                    updatedItems: stats.updatedItems,
                    totalItems: stats.totalItems,
                    stockCount: stats.stockCount,
                    createdDatabase: !existed,
                    databaseFileName: "\(storeID).ngbd",
                    earliestRecordDate: dates.min(),
                    latestRecordDate: dates.max()
                ))
            } catch {
                warnings.append("商店 \(storeID) 导入失败：\(error.localizedDescription)")
                if !existed {
                    _ = databaseStore.deleteStore(storeID)
                }
            }
        }

        guard !results.isEmpty else {
            throw InventoryImportError.allStoresFailed(warnings)
        }

        return ImportReport(
            importedAt: now,
            files: processedFileNames,
            results: results,
            warnings: warnings
        )
    }
}

private struct StoreImportGroup {
    var storeID: String
    var eohRows: [SpreadsheetRow] = []
    var logRows: [SpreadsheetRow] = []
    var eohFiles: Set<String> = []
    var logFiles: Set<String> = []
}
