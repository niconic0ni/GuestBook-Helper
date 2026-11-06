import Foundation
import SQLite3

var checks = 0
var failures: [String] = []

func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    if !condition() {
        failures.append(name)
        print("FAIL  \(name)")
    } else {
        print("ok    \(name)")
    }
}

func makeTempBase() -> URL {
    let base = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("guestbook-verify-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
    return base
}

let fm = FileManager.default
let sampleEOH = URL(fileURLWithPath: "Fixtures/Inventory_EOH_Export_2026-11-03.xlsx")
let sampleLOG = URL(fileURLWithPath: "Fixtures/Inventory_LOG_Export_2026-11-03.xlsx")

// MARK: - Parsing

check(InventorySpreadsheetParser.normalizedStoreID("0000000.0") == "0000000", "Store ID 去掉 .0")
check(InventorySpreadsheetParser.normalizedStoreID("Store 0000000") == "0000000", "Store ID 提取数字")
check(InventorySpreadsheetParser.importKind(forFileAt: URL(fileURLWithPath: "X_EOH_2026.xlsx")) == .eoh, "识别 EOH 文件名")
check(InventorySpreadsheetParser.importKind(forFileAt: URL(fileURLWithPath: "x_log_2026.xlsx")) == .log, "识别 LOG 文件名")
check(TransactionType.parse("RETURNED") == .returned, "识别 RETURNED 状态")
check(TransactionType.returned.title == "退货", "RETURNED 中文为退货")
check(TransactionType.parse("TRANSFER_OUT") == .transferOut, "识别 TRANSFER_OUT 状态")
check(TransactionType.transferOut.title == "出库", "TRANSFER_OUT 中文为出库")
check(SerialScanParser.normalizedSerial(from: "SD5612W1JQ1") == "D5612W1JQ1", "扫码去除开头的 S")
check(SerialScanParser.normalizedSerial(from: "  s D5612W1JQ1  ") == "D5612W1JQ1", "扫码兼容小写与空白")
check(SerialScanParser.normalizedSerial(from: "D5612W1JQ1") == nil, "扫码拒绝非 S 开头条码")
check(SerialScanParser.normalizedSerial(from: "S") == nil, "扫码拒绝空序列号")
check(SerialScanParser.normalizedSerial(from: "SHYJ7G032WD") == "HYJ7G032WD", "实物条码 SHYJ7G032WD 去除 S 后为 HYJ7G032WD")
check(OverviewSection.allCases.count == 6, "总览包含 6 个可配置模块")
check(Set(OverviewSection.allCases.map { $0.title }).count == 6, "总览模块标题唯一")

do {
    let calendar = Calendar(identifier: .gregorian)
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = TimeZone.current
    components.year = 2026
    components.month = 11
    components.day = 3
    components.hour = 15
    components.minute = 37
    components.second = 5
    if let date = calendar.date(from: components) {
        check(DateFormatter.gbDateTime.string(from: date) == "2026-11-03 15:37:05", "日期格式包含年月日时分秒")
    } else {
        check(false, "日期格式包含年月日时分秒")
    }
}

if let parsedDate = ExcelDateParser.parse("46297.74213539352") {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: parsedDate)
    check(components.year == 2026 && components.month == 10 && components.day == 2 && components.hour == 17 && components.minute == 48,
          "Excel 日期转换保持本地时间")
} else {
    check(false, "Excel 日期转换")
}

// MARK: - Main sample import

let base = makeTempBase()
let databaseStore = DatabaseStore(baseURL: base)
let importer = InventoryImporter(databaseStore: databaseStore)
do {
    let report = try importer.importFiles([sampleEOH, sampleLOG])
    check(report.results.count == 1, "示例文件只生成一个 Store 数据库")
    check(report.results.first?.storeID == "0000000", "数据库文件名为 Store ID")
    check(report.results.first?.eohRows == 58, "EOH 读取 58 行")
    check(report.results.first?.logRows == 92, "LOG 读取 92 行")
    check(report.results.first?.stockCount == 40, "导入报告库存为 40")
    check(report.results.first?.returnedRows == 0, "示例导入无 RETURNED 行")
    check(report.results.first?.transferOutRows == 0, "示例导入无 TRANSFER_OUT 行")
    check(report.results.first?.earliestRecordDate != nil && report.results.first?.latestRecordDate != nil, "导入报告包含记录日期范围")
    check(report.results.first?.recordDateRangeText.contains("2024") == true, "日期范围覆盖 2024 年 EOH 记录")

    check(databaseStore.allStoreIDs() == ["0000000"], "数据库目录中只有一个 0000000.ngbd")
    let dbURL = databaseStore.fileURL(forStoreID: "0000000")
    check(dbURL.lastPathComponent == "0000000.ngbd", "文件后缀为 .ngbd")
    let header = try Data(contentsOf: dbURL).prefix(16)
    check(header == Data("SQLite format 3\u{0}".utf8), ".ngbd 是 SQLite 数据库")

    let db = try databaseStore.openStore("0000000")
    var items = try db.fetchItems()
    check(items.count == 108, "合并后共 108 条条目")
    check(items.filter { $0.isStock }.count == 40, "示例可售库存为 40（良品 + 最新 EOH / 退货）")
    check(items.filter { $0.transactionType == .sellout }.count == 50, "已售条目 50")
    check(items.filter { $0.condition == .demo }.count == 18, "展示机 18")
    check(items.filter { $0.condition == .unknown }.count == 50, "LOG-only 条目状态未知 50")

    let byLOB = Dictionary(grouping: items.filter { $0.isStock }, by: { $0.lob }).mapValues { $0.count }
    check(byLOB["iPhone"] == 23, "iPhone 在库 23")
    check(byLOB["iPad"] == 9, "iPad 在库 9")
    check(byLOB["AirPods"] == 5, "AirPods 在库 5")
    check(byLOB["Watch"] == 3, "Watch 在库 3")

    let sortedDesc = InventorySort.createdDescending.sorted(items)
    let sortedAsc = InventorySort.createdAscending.sorted(items)
    check(sortedDesc.first?.latestEventDate ?? .distantPast >= sortedDesc.last?.latestEventDate ?? .distantFuture, "最新记录时间倒序")
    check(sortedAsc.first?.latestEventDate ?? .distantFuture <= sortedAsc.last?.latestEventDate ?? .distantPast, "最新记录时间正序")

    var stockFilter = InventoryFilter()
    stockFilter.statuses = [TransactionType.transferIn.rawValue]
    stockFilter.conditions = [ItemCondition.good.rawValue]
    check(items.filter { stockFilter.matches($0) }.count == 40, "筛选：在库 + 良品 = 40")

    let defaultInventoryFilter = InventoryFilter.defaultInventory
    check(defaultInventoryFilter.inStockOnly, "库存页默认启用仅在库")
    check(defaultInventoryFilter.goodOnly, "库存页默认启用仅良品")
    check(defaultInventoryFilter.excludeDemoAndNoRecord, "库存页默认排除展示机与无记录销售")
    check(defaultInventoryFilter.activeFacetCount == 0, "默认库存范围不显示为额外筛选条件")
    check(items.filter { defaultInventoryFilter.matches($0) }.count == 40, "默认筛选只显示 40 条在库良品")
    check(items.filter { defaultInventoryFilter.matches($0) }.allSatisfy { $0.isStock }, "默认筛选排除已售与出库条目")
    let statusOptions = FilterOptions.make(items: items, allTags: try db.fetchTags()).statuses
    check(statusOptions.contains(where: { $0.value == TransactionType.returned.rawValue }), "库存状态筛选始终包含退货")

    var soldFilter = InventoryFilter()
    soldFilter.statuses = [TransactionType.sellout.rawValue]
    check(items.filter { soldFilter.matches($0) }.count == 50, "筛选：SELLOUT = 50")

    var lobFilter = InventoryFilter()
    lobFilter.lobs = ["iPhone"]
    lobFilter.capacities = ["512GB"]
    let lobResult = items.filter { lobFilter.matches($0) }
    check(!lobResult.isEmpty && lobResult.allSatisfy { $0.lob == "iPhone" && $0.capacity == "512GB" }, "筛选：类别 + 容量")

    var searchResult = items.filter { $0.matchesSearch("D5612W1JQ1") }
    check(searchResult.count == 1 && searchResult.first?.serialNumber == "D5612W1JQ1", "搜索：序列号")

    searchResult = items.filter { $0.matchesSearch("iPhone 18 Pro 银色 512GB") }
    check(searchResult.contains(where: { $0.serialNumber == "D5612W1JQ1" }), "搜索：多个关键词 AND")

    let calendar = Calendar.current
    if let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)),
       let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31)) {
        var dateFilter = InventoryFilter()
        dateFilter.recordRange = DateRangeFilter(start: start, end: end)
        let dateResult = items.filter { dateFilter.matches($0) }
        check(!dateResult.isEmpty, "筛选：记录日期区间有结果")
        check(dateResult.allSatisfy { $0.overlapsRecordRange(DateRangeFilter(start: start, end: end)) }, "筛选：记录日期按完整生命周期重叠")
        check(dateResult.contains(where: { $0.transactionType == .sellout }), "记录日期区间包含已售历史记录")
        check(dateResult.contains(where: { $0.transactionType == .transferIn }), "记录日期区间包含在库记录")
    } else {
        check(false, "筛选：记录日期区间")
    }

    // Tags
    let tag = try db.createTag(named: "已验机")
    let duplicate = try db.createTag(named: "已验机")
    check(tag.id == duplicate.id, "标签名称大小写/重复去重")
    guard let firstStock = items.first(where: { $0.isStock }) else {
        fatalError("没有库存条目")
    }
    try db.setTags(serialNumber: firstStock.serialNumber, tagIDs: [tag.id])
    items = try db.fetchItems()
    let tagged = items.first(where: { $0.serialNumber == firstStock.serialNumber })
    check(tagged?.tags.contains(where: { $0.name == "已验机" }) == true, "标签写入条目")
    check(items.filter { $0.matchesSearch("已验机") }.count == 1, "搜索包含自定义标签")
    var tagFilter = InventoryFilter()
    tagFilter.tagIDs = [tag.id]
    check(items.filter { tagFilter.matches($0) }.count == 1, "筛选：自定义标签")

    let systemTag = try db.fetchTags().first(where: { SystemTag.isNoRecordSale($0) })
    check(systemTag != nil, "无记录销售系统标签自动创建")
    if let systemTag = systemTag {
        try db.setTags(serialNumber: firstStock.serialNumber, tagIDs: [tag.id, systemTag.id])
        items = try db.fetchItems()
        let marked = items.first(where: { $0.serialNumber == firstStock.serialNumber })
        check(marked?.hasNoRecordSaleTag == true, "无记录销售标签已写入条目")
        check(marked?.isStock == false, "无记录销售条目不纳入库存")
        check(items.filter { $0.isStock }.count == 39, "无记录销售使库存从 40 降为 39")
        let markedSummary = try db.summary()
        check(markedSummary.stockCount == 39, "数据库摘要排除无记录销售条目")
        try db.setTags(serialNumber: firstStock.serialNumber, tagIDs: [tag.id])
        items = try db.fetchItems()
        let restoredSummary = try db.summary()
        check(restoredSummary.stockCount == 40, "移除无记录销售标签后库存恢复")
    }
    db.close()

    // Reimport: stock and tags preserved
    _ = try importer.importFiles([sampleEOH, sampleLOG])
    let db2 = try databaseStore.openStore("0000000")
    let reimported = try db2.fetchItems()
    check(reimported.filter { $0.isStock }.count == 40, "再次导入后库存仍为 40")
    check(reimported.filter { $0.matchesSearch("已验机") }.count == 1, "再次导入后标签保留")
    check(reimported.count == 108, "再次导入不会重复创建条目")

    let exportDir = makeTempBase()
    let exportItems = Array(reimported.filter { $0.transactionType == .sellout }.prefix(3))
    let exportURL = try LogXLSXExporter.writeFile(items: exportItems, storeID: "0000000", directory: exportDir)
    let exportData = try Data(contentsOf: exportURL)
    check(exportData.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]), "LOG 导出是有效 ZIP 容器")
    let exportWorkbook = try XLSXWorkbook(data: exportData)
    let exportRawRows = try exportWorkbook.readRows()
    check(exportRawRows.first == LogXLSXExporter.headerRow, "LOG 导出表头与导入格式一致")
    let parsedExport = try InventorySpreadsheetParser.parse(fileURL: exportURL, kind: .log)
    check(parsedExport.rows.count == 3, "LOG 导出行数正确")
    check(parsedExport.rows.allSatisfy { $0.transactionType == .sellout }, "LOG 导出保留交易状态")
    if let originalDate = exportItems.first?.selloutDate, let parsedDate = parsedExport.rows.first?.date {
        check(abs(originalDate.timeIntervalSince(parsedDate)) < 1, "LOG 导出的日期可原样读回")
    } else {
        check(false, "LOG 导出的日期可原样读回")
    }
    db2.close()
} catch {
    check(false, "示例导入流程：\(error.localizedDescription)")
}

// MARK: - Multi store split

let multiBase = makeTempBase()
let multiStore = DatabaseStore(baseURL: multiBase)
let multiImporter = InventoryImporter(databaseStore: multiStore)
let multiEOH = URL(fileURLWithPath: "Fixtures/Inventory_EOH_MultiStore.xlsx")
let multiLOG = URL(fileURLWithPath: "Fixtures/Inventory_LOG_MultiStore.xlsx")
do {
    let report = try multiImporter.importFiles([multiEOH, multiLOG])
    check(report.results.count == 2, "多 Store 文件拆分为两个数据库")
    check(Set(multiStore.allStoreIDs()) == Set(["111", "222"]), "数据库文件名来自各自 Store ID")
    let db111 = try multiStore.openStore("111")
    let items111 = try db111.fetchItems()
    check(items111.count == 3, "Store 111 有 3 条条目")
    check(items111.allSatisfy { $0.storeID == "111" }, "Store 111 数据库只包含 111 的条目")
    check(items111.filter { $0.isStock }.count == 1, "Store 111 在库 1")
    check(items111.filter { $0.transactionType == .sellout }.count == 1, "Store 111 已售 1")
    db111.close()
    let db222 = try multiStore.openStore("222")
    let items222 = try db222.fetchItems()
    check(items222.count == 3, "Store 222 有 3 条条目")
    check(items222.allSatisfy { $0.storeID == "222" }, "Store 222 数据库只包含 222 的条目")
    check(items222.filter { $0.isStock }.count == 1, "Store 222 在库 1")
    check(items222.filter { $0.transactionType == .sellout }.count == 1, "Store 222 已售 1")
    db222.close()
} catch {
    check(false, "多 Store 拆分：\(error.localizedDescription)")
}

// MARK: - RETURNED status and schema migration

let returnedBase = makeTempBase()
let returnedStore = DatabaseStore(baseURL: returnedBase)
let returnedImporter = InventoryImporter(databaseStore: returnedStore)
let returnedEOH = URL(fileURLWithPath: "Fixtures/Inventory_EOH_Returned.xlsx")
let returnedLOG = URL(fileURLWithPath: "Fixtures/Inventory_LOG_Returned.xlsx")
do {
    let report = try returnedImporter.importFiles([returnedEOH, returnedLOG])
    check(report.results.count == 1, "RETURNED 文件只生成一个数据库")
    check(report.results.first?.stockCount == 4, "RETURNED 导入报告库存为 4")
    check(report.results.first?.returnedRows == 5, "RETURNED 导入报告退货行数 5")
    check(report.results.first?.transferOutRows == 0, "RETURNED 导入报告无出库行")
    check(report.results.first?.earliestRecordDate != nil && report.results.first?.latestRecordDate != nil, "RETURNED 导入报告含日期范围")
    let db = try returnedStore.openStore("333")
    let items = try db.fetchItems()
    let summary = try db.summary()
    check(items.count == 8, "RETURNED 测试共 8 条条目")
    check(items.filter { $0.transactionType == .returned }.count == 5, "RETURNED 状态条目 5 条")
    check(items.filter { $0.isStock }.count == 4, "RETURNED 计入可售库存（GOOD）")
    check(summary.stockCount == 4, "数据库摘要库存统计包含 RETURNED")
    check(summary.soldCount == 1, "RETURNED 不改变已售计数")

    let returnedInEOH = items.first(where: { $0.serialNumber == "R2SERIAL0002" })
    check(returnedInEOH?.transactionType == .returned && returnedInEOH?.isStock == true, "EOH 中 RETURNED + GOOD 计入库存")
    let returnedDemo = items.first(where: { $0.serialNumber == "R3SERIAL0003" })
    check(returnedDemo?.transactionType == .returned && returnedDemo?.isStock == false, "RETURNED + DEMO 不计入库存")
    let returnedAfterSale = items.first(where: { $0.serialNumber == "R5SERIAL0005" })
    check(returnedAfterSale?.transactionType == .returned, "SELLOUT 后 RETURNED 为最新状态")
    check(returnedAfterSale?.returnedDate != nil, "RETURNED 保存退货日期")
    check(returnedAfterSale?.isStock == true, "退货后重新计入库存")
    let returnedOnlyLog = items.first(where: { $0.serialNumber == "R6SERIAL0006" })
    check(returnedOnlyLog?.transactionType == .returned && returnedOnlyLog?.presentInLatestEOH == false, "LOG 中的 RETURNED 可为最新 EOH 之外的退货")
    check(returnedOnlyLog?.isStock == true, "最新 EOH 之外的 GOOD 退货仍计入库存")
    let transferOnlyLog = items.first(where: { $0.serialNumber == "R8SERIAL0008" })
    check(transferOnlyLog?.transactionType == .transferIn && transferOnlyLog?.isStock == false, "非最新 EOH 的 TRANSFER_IN 不计入库存")

    var returnedFilter = InventoryFilter()
    returnedFilter.statuses = [TransactionType.returned.rawValue]
    check(items.filter { returnedFilter.matches($0) }.count == 5, "筛选：RETURNED 状态")
    check(items.filter { $0.matchesSearch("退货") }.count == 5, "搜索：退货状态")

    let returnedExportDir = makeTempBase()
    let filteredReturned = items.filter { returnedFilter.matches($0) }
    let returnedExportURL = try LogXLSXExporter.writeFile(items: filteredReturned, storeID: "333", directory: returnedExportDir)
    let parsedReturnedExport = try InventorySpreadsheetParser.parse(fileURL: returnedExportURL, kind: .log)
    check(parsedReturnedExport.rows.count == 5, "LOG 导出只包含筛选后的条目")
    check(parsedReturnedExport.rows.allSatisfy { $0.transactionType == .returned }, "LOG 导出保留 RETURNED 状态")
    db.close()
} catch {
    check(false, "RETURNED 导入流程：\(error.localizedDescription)")
}

// Existing v1 databases must migrate without losing the file.
let migrationBase = makeTempBase()
let migrationURL = migrationBase.appendingPathComponent("333.ngbd")
do {
    var handle: OpaquePointer?
    if sqlite3_open(migrationURL.path, &handle) == SQLITE_OK, let handle = handle {
        let oldSchema = """
        CREATE TABLE items (
            serial_number TEXT PRIMARY KEY,
            transaction_type TEXT NOT NULL,
            mpn TEXT NOT NULL DEFAULT '',
            lob TEXT NOT NULL DEFAULT '',
            sub_lob TEXT NOT NULL DEFAULT '',
            color TEXT NOT NULL DEFAULT '',
            capacity TEXT NOT NULL DEFAULT '',
            transfer_in_date REAL,
            sellout_date REAL,
            created_date REAL,
            store_id TEXT NOT NULL,
            condition TEXT NOT NULL DEFAULT 'UNKNOWN',
            present_in_latest_eoh INTEGER NOT NULL DEFAULT 0,
            first_imported_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        INSERT INTO items VALUES('MIGRATE1','TRANSFER_IN','MPN','iPhone','iPhone 17','白色','256GB',NULL,NULL,NULL,'333','GOOD',1,0,0);
        """
        sqlite3_exec(handle, oldSchema, nil, nil, nil)
        sqlite3_close(handle)
    }
    let migrated = try StoreDatabase(fileURL: migrationURL, storeID: "333")
    let migratedItems = try migrated.fetchItems()
    check(migratedItems.first?.serialNumber == "MIGRATE1", "旧版 .ngbd 数据可读取")
    check(migratedItems.first?.returnedDate == nil, "旧版 .ngbd 自动增加 returned_date")
    let migratedTags = try migrated.fetchTags()
    check(migratedTags.contains(where: { SystemTag.isNoRecordSale($0) }), "旧版 .ngbd 自动创建无记录销售标签")
    check(migratedItems.first?.transferOutDate == nil, "旧版 .ngbd 自动增加 transfer_out_date")
    migrated.close()

    var verifyHandle: OpaquePointer?
    if sqlite3_open(migrationURL.path, &verifyHandle) == SQLITE_OK, let verifyHandle = verifyHandle {
        var statement: OpaquePointer?
        var hasReturnedColumn = false
        var hasTransferOutColumn = false
        if sqlite3_prepare_v2(verifyHandle, "PRAGMA table_info(items);", -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let name = sqlite3_column_text(statement, 1) {
                    let column = String(cString: name)
                    if column == "returned_date" { hasReturnedColumn = true }
                    if column == "transfer_out_date" { hasTransferOutColumn = true }
                }
            }
        }
        sqlite3_finalize(statement)
        sqlite3_close(verifyHandle)
        check(hasReturnedColumn, "schema migration adds returned_date column")
        check(hasTransferOutColumn, "schema migration adds transfer_out_date column")
    } else {
        check(false, "schema migration verification")
    }
} catch {
    check(false, "schema migration: \(error.localizedDescription)")
}

// MARK: - Actual-style LOG without Condition

let noConditionBase = makeTempBase()
let noConditionStore = DatabaseStore(baseURL: noConditionBase)
let noConditionImporter = InventoryImporter(databaseStore: noConditionStore)
let noConditionURL = URL(fileURLWithPath: "Fixtures/Inventory_LOG_ReturnedNoCondition.xlsx")
do {
    let report = try noConditionImporter.importFiles([noConditionURL])
    check(report.results.first?.logRows == 2, "无 Condition 的 LOG 正常读取 RETURNED 与 TRANSFER_OUT")
    check(report.results.first?.returnedRows == 1, "无 Condition LOG 的 RETURNED 计数")
    check(report.results.first?.transferOutRows == 1, "无 Condition LOG 的 TRANSFER_OUT 计数")
    check(report.results.first?.stockCount == 1, "无 Condition 的 RETURNED 计入库存")
    check(report.warnings.isEmpty, "TRANSFER_OUT 不再产生无法识别的警告")
    let db = try noConditionStore.openStore("444")
    let items = try db.fetchItems()
    let item = items.first(where: { $0.serialNumber == "U1SERIAL0001" })
    check(item?.condition == .unknown, "LOG-only RETURNED 的 Condition 为未知")
    check(item?.transactionType == .returned && item?.isStock == true, "LOG-only RETURNED 不因 Condition 未知而丢失库存")
    let transferOutItem = items.first(where: { $0.serialNumber == "U2SERIAL0002" })
    check(transferOutItem?.transactionType == .transferOut, "TRANSFER_OUT 状态正确入库")
    check(transferOutItem?.isStock == false, "TRANSFER_OUT 不计入库存")
    var outFilter = InventoryFilter()
    outFilter.statuses = [TransactionType.transferOut.rawValue]
    check(items.filter { outFilter.matches($0) }.count == 1, "筛选：TRANSFER_OUT 状态")
    let noConditionSummary = try db.summary()
    check(noConditionSummary.stockCount == 1, "LOG-only RETURNED 数据库摘要库存为 1")
    db.close()
} catch {
    check(false, "无 Condition LOG：\(error.localizedDescription)")
}

// MARK: - Stock days

func testItem(
    serial: String,
    transactionType: TransactionType,
    transferIn: Date?,
    sellout: Date? = nil,
    returned: Date? = nil,
    transferOut: Date? = nil,
    condition: ItemCondition = .good,
    presentInEOH: Bool = true,
    tags: [Tag] = []
) -> InventoryItem {
    InventoryItem(
        serialNumber: serial,
        transactionType: transactionType,
        mpn: "MPN",
        lob: "iPhone",
        subLOB: "iPhone 17",
        color: "白色",
        capacity: "256GB",
        transferInDate: transferIn,
        selloutDate: sellout,
        returnedDate: returned,
        transferOutDate: transferOut,
        createdAt: transferIn,
        storeID: "999",
        condition: condition,
        presentInLatestEOH: presentInEOH,
        updatedAt: transferIn ?? Date(timeIntervalSince1970: 0),
        tags: tags
    )
}

let dayCalendar = Calendar(identifier: .gregorian)
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var components = DateComponents()
    components.calendar = dayCalendar
    components.timeZone = TimeZone.current
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return dayCalendar.date(from: components)!
}

let start = date(2026, 1, 1, 0, 0, 0)
do {
    let soldSameDay = testItem(serial: "SD1", transactionType: .sellout, transferIn: start, sellout: date(2026, 1, 1, 12, 0, 0))
    check(soldSameDay.stockDays(asOf: date(2026, 2, 1)) == 1, "售出不足一天按 1 天")
    let soldTwoAndHalf = testItem(serial: "SD2", transactionType: .sellout, transferIn: start, sellout: date(2026, 1, 3, 12, 0, 0))
    check(soldTwoAndHalf.stockDays(asOf: date(2026, 2, 1)) == 3, "售出条目按销售时间向上取整")
    let unsold = testItem(serial: "SD3", transactionType: .transferIn, transferIn: start)
    check(unsold.stockDays(asOf: date(2026, 1, 2, 1, 0, 0)) == 2, "未售出条目按当前时间向上取整")
    let out = testItem(serial: "SD4", transactionType: .transferOut, transferIn: start, transferOut: date(2026, 1, 2, 1, 0, 0))
    check(out.stockDays(asOf: date(2026, 2, 1)) == 2, "出库条目按出库时间计算")
    let noInbound = testItem(serial: "SD5", transactionType: .transferOut, transferIn: nil, transferOut: date(2026, 1, 2))
    check(noInbound.stockDays(asOf: date(2026, 2, 1)) == nil, "无入库日期时库存天数为空")
}

// MARK: - Latest event sorting / record range / split scopes

let sortStart = date(2026, 1, 1)
let soldLate = testItem(serial: "SORT-SOLD", transactionType: .sellout, transferIn: sortStart, sellout: date(2026, 1, 20))
let outMid = testItem(serial: "SORT-OUT", transactionType: .transferOut, transferIn: sortStart, transferOut: date(2026, 1, 10))
let stockEarly = testItem(serial: "SORT-STOCK", transactionType: .transferIn, transferIn: sortStart)
let returnedLatest = testItem(serial: "SORT-RETURN", transactionType: .returned, transferIn: sortStart, returned: date(2026, 1, 25))
let sortedByLatest = InventorySort.createdDescending.sorted([stockEarly, soldLate, outMid, returnedLatest])
check(sortedByLatest.map { $0.serialNumber } == ["SORT-RETURN", "SORT-SOLD", "SORT-OUT", "SORT-STOCK"], "已售/出库按最新事件时间排序")
check(soldLate.latestEventDate == date(2026, 1, 20), "已售条目的最新时间为销售时间")
check(outMid.latestEventDate == date(2026, 1, 10), "出库条目的最新时间为出库时间")

let jan15 = DateRangeFilter(start: date(2026, 1, 15), end: date(2026, 1, 20))
let march = DateRangeFilter(start: date(2026, 3, 1), end: date(2026, 3, 31))
check(soldLate.overlapsRecordRange(jan15), "日期范围命中在库期间售出的记录")
check(!soldLate.overlapsRecordRange(march), "已售记录在售出后不落入后续日期范围")
check(returnedLatest.overlapsRecordRange(march), "退货记录仍视为在库并命中后续日期")
let soldThenReturned = testItem(serial: "SORT-RETURNED-SOLD", transactionType: .returned, transferIn: date(2026, 1, 1), sellout: date(2026, 1, 10), returned: date(2026, 1, 20))
let saleReturnGap = DateRangeFilter(start: date(2026, 1, 12), end: date(2026, 1, 15))
check(!soldThenReturned.overlapsRecordRange(saleReturnGap), "售出后退货的间隔期不算在库")
check(soldThenReturned.overlapsRecordRange(DateRangeFilter(start: date(2026, 1, 8), end: date(2026, 1, 10))), "售出期间的记录仍命中销售所在日期")
check(soldThenReturned.overlapsRecordRange(DateRangeFilter(start: date(2026, 1, 25), end: date(2026, 1, 26))), "退货后重新命中在库日期")
check(!outMid.overlapsRecordRange(march), "出库记录在出库后不落入后续日期范围")

let tagNoRecord = Tag(id: 999, name: SystemTag.noRecordSaleName, colorIndex: SystemTag.noRecordSaleColorIndex, itemCount: 1)
let scopedGood = testItem(serial: "SCOPE-GOOD", transactionType: .transferIn, transferIn: sortStart)
let scopedDemo = testItem(serial: "SCOPE-DEMO", transactionType: .transferIn, transferIn: sortStart, condition: .demo)
let scopedTagged = testItem(serial: "SCOPE-TAG", transactionType: .transferIn, transferIn: sortStart, tags: [tagNoRecord])
let scopedSold = testItem(serial: "SCOPE-SOLD", transactionType: .sellout, transferIn: sortStart, sellout: date(2026, 1, 5))
let scopeItems = [scopedGood, scopedDemo, scopedTagged, scopedSold]
var inStockFilter = InventoryFilter()
inStockFilter.inStockOnly = true
check(scopeItems.filter { inStockFilter.matches($0) }.count == 3, "仅在库与良品可分开筛选")
var goodFilter = InventoryFilter()
goodFilter.goodOnly = true
check(scopeItems.filter { goodFilter.matches($0) }.count == 3, "仅良品独立生效")
var excludeFilter = InventoryFilter()
excludeFilter.excludeDemoAndNoRecord = true
let excluded = scopeItems.filter { excludeFilter.matches($0) }
check(excluded.count == 2 && !excluded.contains(where: { $0.serialNumber == "SCOPE-DEMO" || $0.serialNumber == "SCOPE-TAG" }), "排除展示机与无记录销售独立生效")
check(scopedDemo.isInInventory && scopedGood.isInInventory && !scopedSold.isInInventory, "在库状态与 Condition 解耦")

// MARK: - Legacy out sales, snapshots and ngbd merge

let legacyCutoff = date(2024, 8, 23, 23, 59, 59)
let legacyOut = testItem(serial: "LEGACY-OUT", transactionType: .transferOut, transferIn: date(2024, 1, 1), transferOut: legacyCutoff)
let newerOut = testItem(serial: "NEWER-OUT", transactionType: .transferOut, transferIn: date(2024, 1, 1), transferOut: date(2024, 8, 24))
check(legacyOut.isLegacyOutSale(enabled: true), "2024-08-23 及之前的出库可视为销量")
check(legacyOut.isLegacyOutSale(enabled: true) && legacyOut.saleDate(legacyOutAsSales: true) == legacyCutoff, "老出库的销售日期使用出库时间")
check(!newerOut.isLegacyOutSale(enabled: true), "2024-08-24 之后的出库不视为销量")
check(!legacyOut.isLegacyOutSale(enabled: false), "关闭开关后老出库不视为销量")
var legacySaleFilter = InventoryFilter()
legacySaleFilter.statuses = [TransactionType.sellout.rawValue]
check(legacySaleFilter.matches(legacyOut, legacyOutAsSales: true), "销售状态筛选包含老出库")
check(!legacySaleFilter.matches(legacyOut, legacyOutAsSales: false), "关闭开关后销售状态筛选不包含老出库")
legacySaleFilter.selloutRange = DateRangeFilter(start: legacyCutoff, end: legacyCutoff)
check(legacySaleFilter.matches(legacyOut, legacyOutAsSales: true), "销售日期筛选包含老出库")
check(!legacySaleFilter.matches(newerOut, legacyOutAsSales: true), "销售日期筛选不包含截止日之后的出库")

do {
    let legacyBase = makeTempBase()
    let legacyStore = DatabaseStore(baseURL: legacyBase)
    let legacyDB = try legacyStore.openStore("LEGACY")
    var legacyItem = legacyOut
    legacyItem.storeID = "LEGACY"
    try legacyDB.upsert(legacyItem)
    legacyDB.close()
    let rawSummary = try legacyStore.summary(forStoreID: "LEGACY")
    let convertedSummary = try legacyStore.summary(forStoreID: "LEGACY", legacyOutAsSales: true)
    check(rawSummary?.soldCount == 0, "数据库摘要默认不计老出库")
    check(convertedSummary?.soldCount == 1, "数据库摘要开关开启后计入老出库")
} catch {
    check(false, "数据库摘要老出库销量：\(error.localizedDescription)")
}

do {
    let snapshotBase = makeTempBase()
    let snapshotStore = DatabaseStore(baseURL: snapshotBase)
    var snapshotItem = testItem(serial: "SNAP-A", transactionType: .transferIn, transferIn: date(2026, 1, 1))
    snapshotItem.storeID = "SNAP"
    let snapshotDB = try snapshotStore.openStore("SNAP")
    try snapshotDB.upsert(snapshotItem)
    snapshotDB.close()

    let first = try snapshotStore.createSnapshot(forStoreID: "SNAP", reason: "测试快照一")
    check(first != nil, "创建数据库快照")
    check(snapshotStore.snapshots(forStoreID: "SNAP").count == 1, "快照列表记录新快照")

    var secondItem = testItem(serial: "SNAP-B", transactionType: .transferIn, transferIn: date(2026, 1, 2))
    secondItem.storeID = "SNAP"
    let snapshotDB2 = try snapshotStore.openStore("SNAP")
    try snapshotDB2.upsert(secondItem)
    snapshotDB2.close()
    _ = try snapshotStore.createSnapshot(forStoreID: "SNAP", reason: "测试快照二")

    if let first = first {
        try snapshotStore.restoreSnapshot(first, forStoreID: "SNAP")
        let restored = try snapshotStore.openStore("SNAP")
        let restoredItems = try restored.fetchItems()
        restored.close()
        check(restoredItems.count == 1 && restoredItems.first?.serialNumber == "SNAP-A", "恢复快照回到旧数据")
    } else {
        check(false, "恢复快照回到旧数据")
    }

    for index in 0..<3 {
        let db = try snapshotStore.openStore("SNAP")
        var item = testItem(serial: "SNAP-X\(index)", transactionType: .transferIn, transferIn: date(2026, 1, 10 + index))
        item.storeID = "SNAP"
        try db.upsert(item)
        db.close()
        _ = try snapshotStore.createSnapshot(forStoreID: "SNAP", reason: "测试快照 \(index)")
    }
    check(snapshotStore.snapshots(forStoreID: "SNAP").count <= 3, "快照最多保留最近三次")
} catch {
    check(false, "快照创建、恢复与三次上限：\(error.localizedDescription)")
}

do {
    let mergeBase = makeTempBase()
    let mergeStore = DatabaseStore(baseURL: mergeBase)
    var targetA = testItem(serial: "MERGE-A", transactionType: .transferIn, transferIn: date(2026, 2, 1))
    targetA.storeID = "MERGE"
    let targetDB = try mergeStore.openStore("MERGE")
    try targetDB.upsert(targetA)
    targetDB.close()

    let sourceURL = mergeBase.appendingPathComponent("MERGE.ngbd")
    try FileManager.default.copyItem(at: mergeStore.fileURL(forStoreID: "MERGE"), to: sourceURL)

    var targetB = testItem(serial: "MERGE-B", transactionType: .transferIn, transferIn: date(2026, 2, 2))
    targetB.storeID = "MERGE"
    let targetDB2 = try mergeStore.openStore("MERGE")
    try targetDB2.upsert(targetB)
    targetDB2.close()

    let sourceDB = try StoreDatabase(fileURL: sourceURL, storeID: "MERGE")
    let targetDB3 = try mergeStore.openStore("MERGE")
    try targetDB3.merge(from: sourceDB)
    let merged = try targetDB3.fetchItems()
    sourceDB.close()
    targetDB3.close()
    check(merged.count == 2 && Set(merged.map { $0.serialNumber }) == ["MERGE-A", "MERGE-B"], "同名 .ngbd 合并条目")

    let importedID = try mergeStore.importDatabaseFile(from: sourceURL, mergeExisting: true)
    check(importedID == "MERGE", ".ngbd 导入返回正确 Store ID")
    check(!mergeStore.snapshots(forStoreID: "MERGE").isEmpty, ".ngbd 合并前自动创建快照")

    let newSourceURL = mergeBase.appendingPathComponent("NEWDB.ngbd")
    try FileManager.default.copyItem(at: mergeStore.fileURL(forStoreID: "MERGE"), to: newSourceURL)
    let newID = try mergeStore.importDatabaseFile(from: newSourceURL, mergeExisting: false)
    check(newID == "NEWDB" && mergeStore.databaseExists(forStoreID: "NEWDB"), "导入新的同名 .ngbd 数据库文件")
} catch {
    check(false, "同名 .ngbd 合并与导入：\(error.localizedDescription)")
}

// MARK: - Summary

print("")
print("检查 \(checks) 项，失败 \(failures.count) 项。")
if !failures.isEmpty {
    print("失败项：")
    for failure in failures { print("- \(failure)") }
    exit(1)
}
