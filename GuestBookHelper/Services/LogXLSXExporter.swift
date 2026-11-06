import Foundation

struct LogExportRow {
    var serialNumber: String
    var transactionType: TransactionType
    var mpn: String
    var lob: String
    var subLOB: String
    var color: String
    var capacity: String
    var date: Date?
    var storeID: String
}

enum LogExportError: LocalizedError {
    case noRows
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRows: return "当前筛选结果为空，没有可导出的 LOG 记录。"
        case .writeFailed(let message): return "导出 LOG 失败：\(message)"
        }
    }
}

enum LogXLSXExporter {
    static let headerRow = [
        "Serial Number",
        "Transaction Type",
        "MPN",
        "LOB",
        "Sub LOB",
        "Color",
        "Capacity",
        "Date of Creation",
        "Store ID"
    ]

    // MARK: - Public API

    static func rows(from items: [InventoryItem]) -> [LogExportRow] {
        items.compactMap { item -> LogExportRow? in
            guard item.transactionType != .unknown else { return nil }
            let date: Date?
            switch item.transactionType {
            case .transferIn:
                date = item.transferInDate ?? item.createdAt
            case .sellout:
                date = item.selloutDate ?? item.createdAt
            case .returned:
                date = item.returnedDate ?? item.createdAt
            case .transferOut:
                date = item.transferOutDate ?? item.createdAt
            case .unknown:
                date = nil
            }
            return LogExportRow(
                serialNumber: item.serialNumber,
                transactionType: item.transactionType,
                mpn: item.mpn,
                lob: item.lob,
                subLOB: item.subLOB,
                color: item.color,
                capacity: item.capacity,
                date: date,
                storeID: item.storeID
            )
        }
    }

    static func writeFile(items: [InventoryItem], storeID: String, directory: URL? = nil) throws -> URL {
        let rows = rows(from: items)
        guard !rows.isEmpty else { throw LogExportError.noRows }
        let data = try workbookData(rows: rows)
        let targetDirectory = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("GuestBookExports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true, attributes: nil)
            let stamp = DateFormatter.gbFileStamp.string(from: Date())
            var url = targetDirectory.appendingPathComponent("Inventory_LOG_Export_\(storeID)_\(stamp).xlsx")
            if FileManager.default.fileExists(atPath: url.path) {
                url = targetDirectory.appendingPathComponent("Inventory_LOG_Export_\(storeID)_\(stamp)-\(UUID().uuidString.prefix(4)).xlsx")
            }
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw LogExportError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Workbook

    private static func workbookData(rows: [LogExportRow]) throws -> Data {
        let sheet = worksheetXML(rows: rows)
        let files: [(String, Data)] = [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(rootRelationshipsXML.utf8)),
            ("docProps/app.xml", Data(appPropertiesXML.utf8)),
            ("docProps/core.xml", Data(corePropertiesXML.utf8)),
            ("xl/workbook.xml", Data(workbookXML.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRelationshipsXML.utf8)),
            ("xl/styles.xml", Data(stylesXML.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheet.utf8))
        ]
        let entries = files.map { StoredZipWriter.Entry(name: $0.0, data: $0.1) }
        return StoredZipWriter.archive(entries)
    }

    private static func worksheetXML(rows: [LogExportRow]) -> String {
        let lastRow = rows.count + 1
        var sheetRows: [String] = []
        var headerCells: [String] = []
        for (index, title) in headerRow.enumerated() {
            let reference = "\(columnName(index))1"
            headerCells.append(textCell(reference: reference, value: title, style: 2))
        }
        sheetRows.append("<row r=\"1\">\(headerCells.joined())</row>")

        for (rowIndex, row) in rows.enumerated() {
            let excelRow = rowIndex + 2
            var cells: [String] = []
            let values = [
                row.serialNumber,
                row.transactionType.rawValue,
                row.mpn,
                row.lob,
                row.subLOB,
                row.color,
                row.capacity
            ]
            for (column, value) in values.enumerated() {
                cells.append(textCell(reference: "\(columnName(column))\(excelRow)", value: value))
            }
            if let date = row.date {
                let serial = excelSerial(from: date)
                cells.append("<c r=\"H\(excelRow)\" s=\"1\"><v>\(String(serial))</v></c>")
            }
            cells.append(textCell(reference: "I\(excelRow)", value: row.storeID))
            sheetRows.append("<row r=\"\(excelRow)\">\(String(cells.joined()))</row>")
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <dimension ref="A1:I\(lastRow)"/>
        <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
        <sheetFormatPr defaultRowHeight="15"/>
        <cols>
        <col min="1" max="1" width="20" customWidth="1"/>
        <col min="2" max="2" width="18" customWidth="1"/>
        <col min="3" max="3" width="16" customWidth="1"/>
        <col min="4" max="4" width="12" customWidth="1"/>
        <col min="5" max="5" width="26" customWidth="1"/>
        <col min="6" max="6" width="18" customWidth="1"/>
        <col min="7" max="7" width="12" customWidth="1"/>
        <col min="8" max="8" width="22" customWidth="1"/>
        <col min="9" max="9" width="14" customWidth="1"/>
        </cols>
        <sheetData>\(sheetRows.joined())</sheetData>
        <autoFilter ref="A1:I\(lastRow)"/>
        </worksheet>
        """
    }

    private static func textCell(reference: String, value: String, style: Int? = nil) -> String {
        let styleAttribute = style.map { " s=\"\($0)\"" } ?? ""
        guard !value.isEmpty else { return "<c r=\"\(reference)\"\(styleAttribute)/>" }
        return "<c r=\"\(reference)\" t=\"inlineStr\"\(styleAttribute)><is><t xml:space=\"preserve\">\(xmlEscape(value))</t></is></c>"
    }

    private static func columnName(_ index: Int) -> String {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "I"]
        return index < letters.count ? letters[index] : "A"
    }

    private static func excelSerial(from date: Date) -> Double {
        let localOffset = Double(TimeZone.current.secondsFromGMT(for: date))
        return date.timeIntervalSince1970 / 86_400.0 + 25_569.0 + localOffset / 86_400.0
    }

    private static func xmlEscape(_ value: String) -> String {
        var filtered = ""
        filtered.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            if scalar.value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t" {
                continue
            }
            filtered.unicodeScalars.append(scalar)
        }
        return filtered
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Package XML

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
    <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
    </Types>
    """

    private static let rootRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
    <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
    </Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
    <workbookPr date1904="false"/>
    <bookViews><workbookView activeTab="0"/></bookViews>
    <sheets><sheet name="库存记录导出" sheetId="1" r:id="rId1"/></sheets>
    </workbook>
    """

    private static let workbookRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd hh:mm:ss"/></numFmts>
    <fonts count="2">
    <font><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><name val="Calibri"/></font>
    </fonts>
    <fills count="2">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    </fills>
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
    </cellXfs>
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """

    private static let appPropertiesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
    <Application>GuestBook Helper</Application>
    </Properties>
    """

    private static var corePropertiesXML: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = formatter.string(from: Date())
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <dc:creator>GuestBook Helper</dc:creator>
        <cp:lastModifiedBy>GuestBook Helper</cp:lastModifiedBy>
        <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>
        <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
        </cp:coreProperties>
        """
    }
}

// MARK: - Minimal stored ZIP writer

private enum StoredZipWriter {
    struct Entry {
        var name: String
        var data: Data
    }

    static func archive(_ entries: [Entry]) -> Data {
        var output = Data()
        var centralDirectory = Data()
        let now = Date()
        let (dosTime, dosDate) = dosTimestamp(now)

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let offset = UInt32(output.count)

            output.appendLE32(0x0403_4B50)
            output.appendLE16(20)
            output.appendLE16(0x0800)
            output.appendLE16(0)
            output.appendLE16(dosTime)
            output.appendLE16(dosDate)
            output.appendLE32(crc)
            output.appendLE32(UInt32(entry.data.count))
            output.appendLE32(UInt32(entry.data.count))
            output.appendLE16(UInt16(nameData.count))
            output.appendLE16(0)
            output.append(nameData)
            output.append(entry.data)

            centralDirectory.appendLE32(0x0201_4B50)
            centralDirectory.appendLE16(20)
            centralDirectory.appendLE16(20)
            centralDirectory.appendLE16(0x0800)
            centralDirectory.appendLE16(0)
            centralDirectory.appendLE16(dosTime)
            centralDirectory.appendLE16(dosDate)
            centralDirectory.appendLE32(crc)
            centralDirectory.appendLE32(UInt32(entry.data.count))
            centralDirectory.appendLE32(UInt32(entry.data.count))
            centralDirectory.appendLE16(UInt16(nameData.count))
            centralDirectory.appendLE16(0)
            centralDirectory.appendLE16(0)
            centralDirectory.appendLE16(0)
            centralDirectory.appendLE16(0)
            centralDirectory.appendLE32(0)
            centralDirectory.appendLE32(offset)
            centralDirectory.append(nameData)
        }

        let centralOffset = UInt32(output.count)
        output.append(centralDirectory)
        output.appendLE32(0x0605_4B50)
        output.appendLE16(0)
        output.appendLE16(0)
        output.appendLE16(UInt16(entries.count))
        output.appendLE16(UInt16(entries.count))
        output.appendLE32(UInt32(centralDirectory.count))
        output.appendLE32(centralOffset)
        output.appendLE16(0)
        return output
    }

    private static func dosTimestamp(_ date: Date) -> (UInt16, UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone.current, from: date)
        let year = max(1980, components.year ?? 2026)
        let month = max(1, components.month ?? 1)
        let day = max(1, components.day ?? 1)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        let time = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let dayValue = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (time, dayValue)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.forEach { byte in
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
