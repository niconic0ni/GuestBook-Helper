import Foundation

// MARK: - Spreadsheet row

struct SpreadsheetRow: Equatable {
    var serialNumber: String
    var transactionType: TransactionType
    var mpn: String
    var lob: String
    var subLOB: String
    var color: String
    var capacity: String
    var date: Date?
    var storeID: String
    var condition: ItemCondition
    var sourceRow: Int
}

struct ParsedSpreadsheet {
    var fileName: String
    var kind: ImportKind
    var rows: [SpreadsheetRow]
    var warnings: [String]
}

enum SpreadsheetImportError: LocalizedError {
    case unreadable(String)
    case unknownFileName(String)
    case noImportableRows(String)
    case storeIDMissing(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "无法读取文件：\(name)"
        case .unknownFileName(let name): return "文件名“\(name)”中需要包含 EOH 或 LOG。"
        case .noImportableRows(let name): return "“\(name)”中没有可导入的有效条目。"
        case .storeIDMissing(let name): return "“\(name)”中的 Store ID 无效。"
        }
    }
}

// MARK: - Parser

enum InventorySpreadsheetParser {
    enum Column: String, CaseIterable {
        case serialNumber
        case transactionType
        case mpn
        case lob
        case subLOB
        case color
        case capacity
        case date
        case storeID
        case condition

        var displayName: String {
            switch self {
            case .serialNumber: return "Serial Number"
            case .transactionType: return "Transaction Type"
            case .mpn: return "MPN"
            case .lob: return "LOB"
            case .subLOB: return "Sub LOB"
            case .color: return "Color"
            case .capacity: return "Capacity"
            case .date: return "Date of Creation"
            case .storeID: return "Store ID"
            case .condition: return "Condition"
            }
        }

        var aliases: [String] {
            switch self {
            case .serialNumber: return ["serial number", "serial no", "serial"]
            case .transactionType: return ["transaction type", "transaction"]
            case .mpn: return ["mpn", "part number"]
            case .lob: return ["lob", "line of business"]
            case .subLOB: return ["sub lob", "sub-lob", "sublob", "sub category"]
            case .color: return ["color", "colour"]
            case .capacity: return ["capacity"]
            case .date: return ["date of creation", "creation date", "date"]
            case .storeID: return ["store id", "storeid", "store"]
            case .condition: return ["condition", "product condition"]
            }
        }
    }

    static func importKind(forFileAt url: URL) -> ImportKind? {
        let name = url.deletingPathExtension().lastPathComponent.uppercased()
        if name.contains("EOH") { return .eoh }
        if name.contains("LOG") { return .log }
        return nil
    }

    static func parse(fileURL: URL, kind: ImportKind) throws -> ParsedSpreadsheet {
        let fileName = fileURL.lastPathComponent
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SpreadsheetImportError.unreadable(fileName)
        }
        let workbook: XLSXWorkbook
        do {
            workbook = try XLSXWorkbook(data: data)
        } catch {
            throw SpreadsheetImportError.unreadable("\(fileName)（\(error.localizedDescription)）")
        }
        let rows: [[String]]
        do {
            rows = try workbook.readRows()
        } catch {
            throw SpreadsheetImportError.unreadable("\(fileName)（\(error.localizedDescription)）")
        }
        guard let headerIndex = findHeaderRow(in: rows) else {
            throw XLSXError.missingHeaders(["Serial Number", "Transaction Type", "Store ID"])
        }
        let header = rows[headerIndex]
        var indices: [Column: Int] = [:]
        let canonicalHeader = header.map { canonical($0) }
        for column in Column.allCases {
            if let index = canonicalHeader.firstIndex(where: { candidate in
                column.aliases.contains(candidate)
            }) {
                indices[column] = index
            }
        }

        var required: [Column] = [.serialNumber, .transactionType, .mpn, .lob, .subLOB, .color, .capacity, .date, .storeID]
        if kind == .eoh { required.append(.condition) }
        let missing = required.filter { indices[$0] == nil }
        if !missing.isEmpty {
            throw XLSXError.missingHeaders(missing.map { $0.displayName })
        }

        var parsed: [SpreadsheetRow] = []
        var warnings: [String] = []

        for rowIndex in (headerIndex + 1)..<rows.count {
            let row = rows[rowIndex]
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            let sourceRow = rowIndex + 1
            func value(_ column: Column) -> String {
                guard let index = indices[column], index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let serial = value(.serialNumber)
            guard !serial.isEmpty else {
                warnings.append("第 \(sourceRow) 行缺少 Serial Number，已跳过。")
                continue
            }
            let rawTransaction = value(.transactionType)
            let transaction = TransactionType.parse(rawTransaction)
            guard transaction != .unknown else {
                let shown = rawTransaction.isEmpty ? "空值" : "“\(rawTransaction)”"
                warnings.append("第 \(sourceRow) 行的 Transaction Type \(shown) 无法识别，已跳过。")
                continue
            }
            guard let storeID = normalizedStoreID(value(.storeID)) else {
                warnings.append("第 \(sourceRow) 行的 Store ID 无效，已跳过。")
                continue
            }
            let rawDate = value(.date)
            let date = ExcelDateParser.parse(rawDate)
            if date == nil && !rawDate.isEmpty {
                warnings.append("第 \(sourceRow) 行的 Date of Creation 无法解析，日期将留空。")
            }
            let condition = ItemCondition.parse(value(.condition))
            if kind == .eoh && condition == .unknown {
                warnings.append("第 \(sourceRow) 行的 Condition 无法识别，将标记为未知。")
            }
            parsed.append(SpreadsheetRow(
                serialNumber: serial,
                transactionType: transaction,
                mpn: value(.mpn),
                lob: value(.lob),
                subLOB: value(.subLOB),
                color: value(.color),
                capacity: value(.capacity),
                date: date,
                storeID: storeID,
                condition: condition,
                sourceRow: sourceRow
            ))
        }

        guard !parsed.isEmpty else {
            throw SpreadsheetImportError.noImportableRows(fileName)
        }
        return ParsedSpreadsheet(fileName: fileName, kind: kind, rows: parsed, warnings: warnings)
    }

    static func normalizedStoreID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let numeric = trimmed.replacingOccurrences(of: ",", with: "")
        if let value = Double(numeric), value.isFinite, value >= 0 {
            let integer = Int64(value.rounded(.towardZero))
            if integer > 0 { return String(integer) }
        }
        let digits = trimmed.filter { $0.isNumber }
        guard !digits.isEmpty, let integer = Int64(digits), integer > 0 else { return nil }
        return String(integer)
    }

    private static func findHeaderRow(in rows: [[String]]) -> Int? {
        let limit = min(rows.count, 20)
        for index in 0..<limit {
            let values = rows[index].map { canonical($0) }
            if values.contains("serial number") && values.contains("transaction type") && values.contains("store id") {
                return index
            }
        }
        return nil
    }

    private static func canonical(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Date parsing

enum ExcelDateParser {
    static func parse(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let serial = Double(value.replacingOccurrences(of: ",", with: ".")), serial > 0, serial < 2_958_466 {
            return date(fromExcelSerial: serial)
        }

        if value.contains("T") {
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) { return date }
        }

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    static func date(fromExcelSerial serial: Double) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.calendar = calendar
        // Excel serial dates have no time zone. Use today's UTC offset instead of
        // the historical local-mean-time offset Calendars use for 1899.
        let fixedOffset = TimeZone.current.secondsFromGMT()
        components.timeZone = TimeZone(secondsFromGMT: fixedOffset) ?? TimeZone(secondsFromGMT: 0)!
        components.year = 1899
        components.month = 12
        components.day = 30
        let base = calendar.date(from: components) ?? Date(timeIntervalSince1970: -2_209_161_600)
        // Excel's 1900 leap-year bug: serials below 60 are one day ahead.
        let adjustment: Double = serial < 60 ? 1 : 0
        return base.addingTimeInterval((serial + adjustment) * 86_400)
    }

    private static let formats: [String] = [
        "yyyy-MM-dd HH:mm:ss.SSS",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy/MM/dd HH:mm",
        "yyyy/MM/dd",
        "yyyy年M月d日 HH:mm:ss",
        "yyyy年M月d日",
        "M/d/yy HH:mm:ss",
        "M/d/yy",
        "M/d/yyyy HH:mm:ss",
        "M/d/yyyy"
    ]
}
