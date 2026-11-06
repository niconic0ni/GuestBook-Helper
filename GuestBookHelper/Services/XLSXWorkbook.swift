import Foundation

enum XLSXError: LocalizedError {
    case malformedXML(String)
    case missingWorkbook
    case missingSheet
    case missingHeaders([String])
    case missingColumn(String)
    case noRows

    var errorDescription: String? {
        switch self {
        case .malformedXML(let name): return "无法解析 \(name)。"
        case .missingWorkbook: return "xlsx 缺少工作簿信息。"
        case .missingSheet: return "xlsx 中没有可读取的工作表。"
        case .missingHeaders(let values): return "xlsx 缺少列：\(values.joined(separator: "、"))。"
        case .missingColumn(let value): return "xlsx 缺少列：\(value)。"
        case .noRows: return "xlsx 中没有可导入的数据行。"
        }
    }
}

final class XLSXWorkbook {
    private let archive: ZipArchive
    private let sheetPath: String
    private let sharedStrings: [String]

    init(data: Data) throws {
        let archive = try ZipArchive(data: data)
        self.archive = archive
        guard archive.contains("xl/workbook.xml") else { throw XLSXError.missingWorkbook }
        self.sharedStrings = try Self.readSharedStrings(from: archive)
        self.sheetPath = try Self.resolveFirstSheetPath(in: archive)
    }

    func readRows() throws -> [[String]] {
        guard let sheetData = try? archive.data(for: sheetPath) else { throw XLSXError.missingSheet }
        let delegate = SheetXMLParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: sheetData)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw XLSXError.malformedXML(sheetPath)
        }
        let rows = delegate.rows
        guard !rows.isEmpty else { throw XLSXError.noRows }
        return rows
    }

    // MARK: - Workbook structure

    private static func readSharedStrings(from archive: ZipArchive) throws -> [String] {
        guard let data = try? archive.data(for: "xl/sharedStrings.xml") else { return [] }
        let delegate = SharedStringsXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw XLSXError.malformedXML("xl/sharedStrings.xml") }
        return delegate.strings
    }

    private static func resolveFirstSheetPath(in archive: ZipArchive) throws -> String {
        var sheetRelationshipID: String?
        if let workbookData = try? archive.data(for: "xl/workbook.xml") {
            let delegate = WorkbookXMLParser()
            let parser = XMLParser(data: workbookData)
            parser.delegate = delegate
            parser.shouldProcessNamespaces = false
            parser.shouldResolveExternalEntities = false
            _ = parser.parse()
            sheetRelationshipID = delegate.firstSheetID
        }

        if let workbookRels = try? archive.data(for: "xl/_rels/workbook.xml.rels") {
            let delegate = RelationshipsXMLParser()
            let parser = XMLParser(data: workbookRels)
            parser.delegate = delegate
            parser.shouldProcessNamespaces = false
            parser.shouldResolveExternalEntities = false
            _ = parser.parse()
            if let identifier = sheetRelationshipID,
               let target = delegate.relationships[identifier] {
                return normalizedSheetPath(target)
            }
            if let first = delegate.relationships.values.first {
                return normalizedSheetPath(first)
            }
        }

        if archive.contains("xl/worksheets/sheet1.xml") { return "xl/worksheets/sheet1.xml" }
        if let name = archive.entries.keys.first(where: { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }) {
            return name
        }
        throw XLSXError.missingSheet
    }

    private static func normalizedSheetPath(_ target: String) -> String {
        var value = target
        if value.hasPrefix("/") {
            value.removeFirst()
            return value
        }
        if value.hasPrefix("xl/") { return value }
        if value.contains("../") {
            let parts = value.components(separatedBy: "/")
            var stack: [String] = ["xl"]
            for part in parts {
                if part == ".." {
                    if !stack.isEmpty { stack.removeLast() }
                } else if part != "." && !part.isEmpty {
                    stack.append(part)
                }
            }
            return stack.joined(separator: "/")
        }
        return "xl/" + value
    }
}

// MARK: - XML delegates

private final class SharedStringsXMLParser: NSObject, XMLParserDelegate {
    private var current = ""
    private var inStringItem = false
    private var inText = false
    private var inPhonetic = false
    private(set) var strings: [String] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "si":
            current = ""
            inStringItem = true
        case "rPh":
            inPhonetic = true
        case "t":
            if inStringItem && !inPhonetic { inText = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "t":
            inText = false
        case "rPh":
            inPhonetic = false
        case "si":
            strings.append(current)
            current = ""
            inStringItem = false
        default:
            break
        }
    }
}

private final class WorkbookXMLParser: NSObject, XMLParserDelegate {
    private(set) var firstSheetID: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "sheet", firstSheetID == nil else { return }
        firstSheetID = attributeDict["r:id"] ?? attributeDict["id"]
    }
}

private final class RelationshipsXMLParser: NSObject, XMLParserDelegate {
    private(set) var relationships: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "Relationship",
              let identifier = attributeDict["Id"],
              let target = attributeDict["Target"] else { return }
        relationships[identifier] = target
    }
}

private final class SheetXMLParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private(set) var rows: [[String]] = []

    private var currentRow: [Int: String] = [:]
    private var currentRowIndex = 0
    private var nextColumn = 0
    private var inCell = false
    private var cellColumn = 0
    private var cellType = ""
    private var cellValue = ""
    private var inlineValue = ""
    private var inValue = false
    private var inInlineText = false
    private var maxColumn = 0

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "row":
            currentRow = [:]
            nextColumn = 0
            currentRowIndex = Int(attributeDict["r"] ?? "") ?? 0
        case "c":
            inCell = true
            inValue = false
            inInlineText = false
            cellValue = ""
            inlineValue = ""
            cellType = attributeDict["t"] ?? ""
            let reference = attributeDict["r"] ?? ""
            cellColumn = Self.columnIndex(from: reference) ?? nextColumn
            nextColumn = cellColumn + 1
        case "v":
            if inCell { inValue = true }
        case "t":
            if inCell && cellType == "inlineStr" { inInlineText = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inValue { cellValue += string }
        if inInlineText { inlineValue += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "v":
            inValue = false
        case "t":
            inInlineText = false
        case "c":
            var value = cellValue
            if cellType == "s" {
                if let index = Int(cellValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                   index >= 0 && index < sharedStrings.count {
                    value = sharedStrings[index]
                } else {
                    value = ""
                }
            } else if cellType == "inlineStr" {
                value = inlineValue
            }
            if !value.isEmpty {
                currentRow[cellColumn] = value
                maxColumn = max(maxColumn, cellColumn)
            }
            inCell = false
        case "row":
            if !currentRow.isEmpty {
                let width = (currentRow.keys.max() ?? maxColumn) + 1
                var row = [String](repeating: "", count: width)
                for (column, value) in currentRow where column < width {
                    row[column] = value
                }
                rows.append(row)
                maxColumn = max(maxColumn, width - 1)
            }
        default:
            break
        }
    }

    private static func columnIndex(from reference: String) -> Int? {
        guard !reference.isEmpty else { return nil }
        var value = 0
        var foundLetter = false
        for character in reference.uppercased() {
            if character >= "A" && character <= "Z" {
                foundLetter = true
                let scalar = character.unicodeScalars.first!.value
                value = value * 26 + Int(scalar - 64)
            } else {
                break
            }
        }
        return foundLetter ? max(0, value - 1) : nil
    }
}
