import Foundation
import PDFKit
import zlib

// MARK: - Errors

enum BankParseError: LocalizedError {
    case invalidFormat
    case noTransactionsFound
    case unsupportedEncoding

    var errorDescription: String? {
        switch self {
        case .invalidFormat:        return "Das CSV-Format wurde nicht erkannt."
        case .noTransactionsFound:  return "Keine Transaktionen im Auszug gefunden."
        case .unsupportedEncoding:  return "Datei-Kodierung konnte nicht gelesen werden."
        }
    }
}

// MARK: - Parser

enum BankImportService {

    static func parse(url: URL, format: BankFormat) throws -> [BankTransaction] {
        switch format {
        case .zugerKantonalbank:
            if url.pathExtension.lowercased() == "pdf" {
                guard let data = try? Data(contentsOf: url) else { throw BankParseError.unsupportedEncoding }
                return try ZugerKBParser.parsePDF(data: data)
            }
            return try ZugerKBParser.parse(content: try readContent(from: url))
        case .zuercherKantonalbank:
            return try ZuercherKBParser.parse(content: try readContent(from: url))
        case .yuh:
            return try YuhParser.parse(content: try readContent(from: url))
        case .swisscard:
            guard let data = try? Data(contentsOf: url) else { throw BankParseError.unsupportedEncoding }
            return try SwissCardParser.parse(data: data)
        case .ubs:
            return try UBSParser.parse(content: try readContent(from: url))
        }
    }

    // Try UTF-8 first, then ISO-8859-1 (common for Swiss bank exports).
    // Strip UTF-8 BOM (﻿) that many Swiss bank exports prepend.
    private static func readContent(from url: URL) throws -> String {
        func stripBOM(_ s: String) -> String {
            s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
        }
        if let s = try? String(contentsOf: url, encoding: .utf8)          { return stripBOM(s) }
        if let s = try? String(contentsOf: url, encoding: .isoLatin1)     { return stripBOM(s) }
        if let s = try? String(contentsOf: url, encoding: .windowsCP1252) { return stripBOM(s) }
        throw BankParseError.unsupportedEncoding
    }
}

// MARK: - Zuger Kantonalbank Parser

private enum ZugerKBParser {

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yy"
        f.locale = Locale(identifier: "de_CH")
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        return f
    }()

    private static let dateFmtFull: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "de_CH")
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        return f
    }()

    // MARK: - PDF Support Types

    private struct PDFToken {
        let text: String
        let xCenter: CGFloat
    }

    private struct PDFLine {
        let tokens: [PDFToken]
        var fullText: String { tokens.map(\.text).joined(separator: " ") }
    }

    // MARK: - PDF Parsing (Einzeltransaktionen)

    /// Parses the Zuger Kantonalbank "Einzeltransaktionen" PDF.
    /// Uses PDFKit character bounds to determine whether each amount is in the
    /// Belastung (debit) or Gutschrift (credit) column — works without a Saldo column.
    static func parsePDF(data: Data) throws -> [BankTransaction] {
        guard let doc = PDFDocument(data: data) else { throw BankParseError.invalidFormat }

        // Phase 1: Extract structured lines from all pages using character bounds.
        var allLines: [PDFLine] = []
        var belastungX: CGFloat = -1
        var gutschriftX: CGFloat = -1

        for pageIdx in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIdx),
                  let pageStr = page.string, !pageStr.isEmpty else { continue }

            let lines = extractPDFLines(from: page, string: pageStr)

            // Calibrate column positions from the first header row found.
            if belastungX < 0 {
                for line in lines {
                    if line.fullText.contains("Belastung") && line.fullText.contains("Gutschrift") {
                        for tok in line.tokens {
                            let t = tok.text.trimmingCharacters(in: .whitespaces)
                            if t == "Belastung"  { belastungX  = tok.xCenter }
                            if t == "Gutschrift" { gutschriftX = tok.xCenter }
                        }
                        break
                    }
                }
            }
            allLines.append(contentsOf: lines)
        }

        // Midpoint between column headers → classifies amounts as debit or credit.
        let colMid: CGFloat = (belastungX > 0 && gutschriftX > 0)
            ? (belastungX + gutschriftX) / 2.0
            : 420.0  // fallback for A4 page (~595pt wide)

        // Amounts must be in the right portion of the page (Belastung or Gutschrift zone).
        // This prevents amounts embedded inside descriptions (e.g. "EUR 45.00") from
        // being mistaken for transaction amounts.
        let amountZoneStart: CGFloat = belastungX > 0 ? belastungX - 40 : colMid - 50

        guard let amtRegex  = try? NSRegularExpression(pattern: #"^[\d']+\.\d{2}$"#),
              let dateRegex = try? NSRegularExpression(pattern: #"^\d{2}\.\d{2}\.\d{4}$"#),
              let timeRegex = try? NSRegularExpression(pattern: #"^\d{2}:\d{2}$"#)
        else { throw BankParseError.invalidFormat }

        func matches(_ s: String, _ re: NSRegularExpression) -> Bool {
            let ns = s as NSString
            return re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) != nil
        }
        func parseAmt(_ s: String) -> Double? {
            matches(s, amtRegex) ? Double(s.replacingOccurrences(of: "'", with: "")) : nil
        }
        func isColumnAmt(_ tok: PDFToken) -> Bool {
            parseAmt(tok.text) != nil && tok.xCenter >= amountZoneStart
        }

        var result: [BankTransaction] = []
        var curDate: Date?    = nil
        var curDesc: [String] = []
        var curAmt:  Double?  = nil
        var curIsCredit = false

        func commit() {
            guard let d = curDate, let a = curAmt else { return }
            let desc = curDesc.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let signed = curIsCredit ? a : -a
            let cat = Categorizer.categorize(description: desc, amount: signed)
            let mer = Categorizer.extractMerchant(from: desc)
            result.append(BankTransaction(
                date: d,
                description: desc.isEmpty ? "Transaktion" : desc,
                rawAmount: signed,
                valueDate: d,
                category: cat,
                merchantName: mer
            ))
        }

        for line in allLines {
            let tokens = line.tokens.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !tokens.isEmpty else { continue }

            // Skip structural / non-transaction lines.
            let ft = line.fullText
            if ft.contains("Belastung") && ft.contains("Gutschrift") { continue }
            if ft.hasPrefix("Anfangssaldo") || ft.hasPrefix("Schlusssaldo") { continue }
            if ft.contains("Seite") && (ft.contains(" von ") || ft.contains(" of ")) { continue }
            if ft.contains("IBAN") || ft.contains("Einzeltransaktionen") { continue }
            let firstTok = tokens[0].text.trimmingCharacters(in: .whitespaces)
            if ft.contains("Kantonalbank") && !matches(firstTok, dateRegex) { continue }

            let second = tokens.count > 1 ? tokens[1].text.trimmingCharacters(in: .whitespaces) : ""

            // Start a new transaction when the first token is a date (DD.MM.YYYY) and is NOT
            // immediately followed by a time token (HH:MM) — those are embedded timestamps.
            if matches(firstTok, dateRegex) && !matches(second, timeRegex),
               let date = dateFmtFull.date(from: firstTok) {
                commit()
                curDate = date
                curDesc = []
                curAmt  = nil
                curIsCredit = false

                for tok in tokens.dropFirst() {
                    let t = tok.text.trimmingCharacters(in: .whitespaces)
                    if isColumnAmt(tok), let amt = parseAmt(t) {
                        curAmt = amt
                        curIsCredit = tok.xCenter > colMid
                    } else if !t.isEmpty && !matches(t, timeRegex) {
                        curDesc.append(t)
                    }
                }
            } else if curDate != nil {
                // Continuation / multi-line description line.
                for tok in tokens {
                    let t = tok.text.trimmingCharacters(in: .whitespaces)
                    if isColumnAmt(tok), curAmt == nil, let amt = parseAmt(t) {
                        curAmt = amt
                        curIsCredit = tok.xCenter > colMid
                    } else if !t.isEmpty && !matches(t, dateRegex) {
                        curDesc.append(t)
                    }
                }
            }
        }
        commit()

        guard !result.isEmpty else { throw BankParseError.noTransactionsFound }
        return result.sorted { $0.date > $1.date }
    }

    // MARK: - Character-Bounds Line Extraction

    /// Reconstructs PDF table rows from character positions.
    /// Groups characters by y-coordinate into lines, then by x-gap into tokens.
    /// A gap > 12pt between consecutive characters starts a new token (column gap).
    private static func extractPDFLines(from page: PDFPage, string pageStr: String) -> [PDFLine] {
        let nsStr = pageStr as NSString
        let length = nsStr.length
        guard length > 0 else { return [] }

        struct CP { let ch: unichar; let x: CGFloat; let y: CGFloat; let w: CGFloat }
        var cps: [CP] = []
        cps.reserveCapacity(length)
        for i in 0..<length {
            let b = page.characterBounds(at: i)
            guard b.width > 0 || b.height > 0 else { continue }
            cps.append(CP(ch: nsStr.character(at: i), x: b.minX, y: b.midY, w: b.width))
        }
        guard !cps.isEmpty else { return [] }

        // Group by y with ±3pt tolerance; higher y in PDF space = higher on page.
        var yBuckets: [(y: CGFloat, cps: [CP])] = []
        for cp in cps {
            if let idx = yBuckets.firstIndex(where: { abs($0.y - cp.y) < 3 }) {
                yBuckets[idx].cps.append(cp)
            } else {
                yBuckets.append((cp.y, [cp]))
            }
        }
        yBuckets.sort { $0.y > $1.y }  // descending y = top-to-bottom reading order

        let gapThreshold: CGFloat = 12
        var lines: [PDFLine] = []

        for bucket in yBuckets {
            let sorted = bucket.cps.sorted { $0.x < $1.x }

            var tokens: [PDFToken] = []
            var tokText = ""
            var tokXMin: CGFloat = 0
            var tokXMax: CGFloat = 0
            var prevXEnd: CGFloat = -1

            for cp in sorted {
                guard cp.ch >= 0x20,
                      let scalar = Unicode.Scalar(UInt32(cp.ch)) else { continue }
                let char = Character(scalar)

                if prevXEnd < 0 {
                    tokText = String(char); tokXMin = cp.x; tokXMax = cp.x + cp.w; prevXEnd = tokXMax
                } else if cp.x - prevXEnd > gapThreshold {
                    let t = tokText.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { tokens.append(PDFToken(text: t, xCenter: (tokXMin + tokXMax) / 2)) }
                    tokText = String(char); tokXMin = cp.x; tokXMax = cp.x + cp.w; prevXEnd = tokXMax
                } else {
                    tokText.append(char)
                    tokXMax = max(tokXMax, cp.x + cp.w)
                    prevXEnd = max(prevXEnd, cp.x + cp.w)
                }
            }
            let t = tokText.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { tokens.append(PDFToken(text: t, xCenter: (tokXMin + tokXMax) / 2)) }
            if !tokens.isEmpty { lines.append(PDFLine(tokens: tokens)) }
        }
        return lines
    }

    static func parse(content: String) throws -> [BankTransaction] {
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // Locate header row "Datum;Buchungstext;Betrag;Valuta"
        guard let headerIdx = lines.firstIndex(where: { $0.hasPrefix("Datum;") }) else {
            throw BankParseError.invalidFormat
        }

        var result: [BankTransaction] = []

        for line in lines[(headerIdx + 1)...] {
            guard !line.isEmpty else { continue }
            let fields = line.components(separatedBy: ";")
            guard fields.count >= 3 else { continue }

            let dateStr = fields[0].trimmingCharacters(in: .whitespaces)
            let desc    = fields[1].trimmingCharacters(in: .whitespaces)
            // Remove thousands separator (apostrophe in Swiss locale)
            let amtStr  = fields[2].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "'", with: "")
            let valStr  = fields.count >= 4 ? fields[3].trimmingCharacters(in: .whitespaces) : dateStr

            guard let date   = dateFmt.date(from: dateStr),
                  let amount = Double(amtStr) else { continue }

            let valueDate = dateFmt.date(from: valStr) ?? date
            let category  = Categorizer.categorize(description: desc, amount: amount)
            let merchant  = Categorizer.extractMerchant(from: desc)

            result.append(BankTransaction(
                date:         date,
                description:  desc,
                rawAmount:    amount,
                valueDate:    valueDate,
                category:     category,
                merchantName: merchant
            ))
        }

        guard !result.isEmpty else { throw BankParseError.noTransactionsFound }
        return result.sorted { $0.date > $1.date }
    }
}

// MARK: - Zürcher Kantonalbank Parser
//
// CSV columns (semicolon-separated, header row starts with "Datum;Buchungstext;Whg;"):
//   0  Datum           – DD.MM.YY
//   1  Buchungstext    – booking description / merchant
//   2  Whg             – currency
//   3  Betrag Detail   – partial amount (can be empty)
//   4  ZKB-Referenz    – internal reference
//   5  Referenznummer  – external reference
//   6  Belastung CHF   – debit  (positive → rawAmount negative)
//   7  Gutschrift CHF  – credit (positive → rawAmount positive)
//   8  Valuta          – value date DD.MM.YY
//   9  Saldo CHF       – running balance
//  10  Zahlungszweck   – payment purpose (often empty)
//  11  Details         – additional details

private enum ZuercherKBParser {

    // ZKB exports vary: dd.MM.yy, dd.MM.yyyy, or yyyy-MM-dd depending on portal version
    private static let dateFormatters: [DateFormatter] = {
        [("dd.MM.yy"), ("dd.MM.yyyy"), ("yyyy-MM-dd"), ("dd/MM/yyyy")].map { fmt in
            let f = DateFormatter()
            f.dateFormat = fmt
            f.locale = Locale(identifier: "de_CH")
            f.timeZone = TimeZone(identifier: "Europe/Zurich")
            return f
        }
    }()

    private static func parseDate(_ s: String) -> Date? {
        for fmt in dateFormatters { if let d = fmt.date(from: s) { return d } }
        return nil
    }

    // Strip surrounding quotes (ZKB sometimes wraps fields in double-quotes)
    private static func unquote(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") {
            return String(t.dropFirst().dropLast())
        }
        return t
    }

    // Handles "." and "," decimal separator, "'" / "\u{2019}" thousands separator
    private static func parseAmount(_ s: String) -> Double? {
        var cleaned = s
            .replacingOccurrences(of: "'",        with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        // European "1.234,56" → remove period as thousands sep, comma → dot
        if cleaned.contains(",") && cleaned.contains("."),
           let dotIdx = cleaned.firstIndex(of: "."),
           let commaIdx = cleaned.firstIndex(of: ",") {
            if dotIdx < commaIdx {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        }
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    static func parse(content: String) throws -> [BankTransaction] {
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let headerIdx = lines.firstIndex(where: {
            $0.contains("Buchungstext") && $0.contains("Belastung CHF") && $0.contains("Gutschrift CHF")
        }) else {
            throw BankParseError.invalidFormat
        }

        // Determine column positions from the header so we're robust against reordering
        let headerFields = lines[headerIdx].components(separatedBy: ";")
        let colDate     = headerFields.firstIndex(of: "Datum")           ?? 0
        let colBook     = headerFields.firstIndex(of: "Buchungstext")    ?? 1
        let colDetail   = headerFields.firstIndex(of: "Betrag Detail")   ?? 3
        let colDebit    = headerFields.firstIndex(where: { $0.contains("Belastung") }) ?? 6
        let colCredit   = headerFields.firstIndex(where: { $0.contains("Gutschrift") }) ?? 7
        let colValuta   = headerFields.firstIndex(of: "Valuta")          ?? 8
        let colPurpose  = headerFields.firstIndex(of: "Zahlungszweck")   ?? 10
        let colDetails  = headerFields.firstIndex(of: "Details")         ?? 11

        var result: [BankTransaction] = []

        for line in lines[(headerIdx + 1)...] {
            guard !line.isEmpty else { continue }
            let raw = line.components(separatedBy: ";")
            let fields = raw.map { unquote($0) }
            guard fields.count > max(colDate, colBook, colDebit, colCredit) else { continue }

            let dateStr   = fields[colDate]
            let bookText  = colBook    < fields.count ? fields[colBook]    : ""
            let debitStr  = colDebit   < fields.count ? fields[colDebit]   : ""
            let creditStr = colCredit  < fields.count ? fields[colCredit]  : ""
            let detailAmt = colDetail  < fields.count ? fields[colDetail]  : ""
            let valStr    = colValuta  < fields.count ? fields[colValuta]  : dateStr
            let purpose   = colPurpose < fields.count ? fields[colPurpose] : ""
            let details   = colDetails < fields.count ? fields[colDetails]  : ""

            guard let date = parseDate(dateStr) else { continue }

            let rawAmount: Double
            if !debitStr.isEmpty, let v = parseAmount(debitStr) {
                rawAmount = -v   // debit = expense
            } else if !creditStr.isEmpty, let v = parseAmount(creditStr) {
                rawAmount = v    // credit = income
            } else if !detailAmt.isEmpty, let v = parseAmount(detailAmt) {
                // "Betrag Detail" is a signed amount (negative = expense) in some export variants
                rawAmount = v
            } else {
                continue
            }

            let descParts = [bookText, purpose, details].filter { !$0.isEmpty }
            let desc = descParts.joined(separator: " – ")

            let valueDate = parseDate(valStr) ?? date
            let category  = Categorizer.categorize(description: desc, amount: rawAmount)
            let merchant  = extractMerchant(bookText: bookText, purpose: purpose, details: details)

            result.append(BankTransaction(
                date:         date,
                description:  desc,
                rawAmount:    rawAmount,
                valueDate:    valueDate,
                category:     category,
                merchantName: merchant
            ))
        }

        guard !result.isEmpty else { throw BankParseError.noTransactionsFound }
        return result.sorted { $0.date > $1.date }
    }

    private static func extractMerchant(bookText: String, purpose: String, details: String) -> String {
        for candidate in [details, purpose, bookText] where !candidate.isEmpty {
            let up = candidate.uppercased()
            if up == "E-BANKING" || up.hasPrefix("ZKB") { continue }
            return candidate.trimmingCharacters(in: .whitespaces)
        }
        return bookText
    }
}

// MARK: - Yuh Parser

private enum YuhParser {

    // Columns: DATE;ACTIVITY TYPE;ACTIVITY NAME;DEBIT;DEBIT CURRENCY;CREDIT;CREDIT CURRENCY;
    //          CARD NUMBER;LOCALITY;RECIPIENT;SENDER;FEES/COMMISSION;BUY/SELL;QUANTITY;ASSET;PRICE PER UNIT
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        f.locale = Locale(identifier: "de_CH")
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        return f
    }()

    static func parse(content: String) throws -> [BankTransaction] {
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let headerIdx = lines.firstIndex(where: { $0.hasPrefix("DATE;") }) else {
            throw BankParseError.invalidFormat
        }

        var result: [BankTransaction] = []

        for line in lines[(headerIdx + 1)...] {
            guard !line.isEmpty else { continue }
            let fields = line.components(separatedBy: ";").map { unquote($0) }
            guard fields.count >= 11 else { continue }

            let dateStr      = fields[0]
            let activityType = fields[1]
            let activityName = fields[2]
            let debitStr     = fields[3]  // negative expense (e.g. "-98.20")
            let creditStr    = fields[5]  // positive income

            // Skip investment/trading rows: non-empty ASSET field (index 14) means stock/ETF trade
            if fields.count > 14 && !fields[14].isEmpty { continue }
            // Skip BUY/SELL trades as a secondary guard
            if fields.count > 12 && !fields[12].isEmpty { continue }
            // Skip currency auto-conversion rows (settlement of non-CHF card payments — skipped below)
            if activityType == "BANK_AUTO_ORDER_EXECUTED" { continue }

            // Only process CHF amounts
            let debitCurrency  = fields.count > 4 ? fields[4] : "CHF"
            let creditCurrency = fields.count > 6 ? fields[6] : "CHF"

            guard !debitStr.isEmpty || !creditStr.isEmpty else { continue }
            guard let date = dateFmt.date(from: dateStr) else { continue }

            let rawAmount: Double
            if !debitStr.isEmpty && (debitCurrency == "CHF" || debitCurrency.isEmpty),
               let v = Double(debitStr.replacingOccurrences(of: "'", with: "")) {
                rawAmount = v
            } else if !creditStr.isEmpty && (creditCurrency == "CHF" || creditCurrency.isEmpty),
               let v = Double(creditStr.replacingOccurrences(of: "'", with: "")) {
                rawAmount = v
            } else {
                continue
            }

            // Merchant name: RECIPIENT for outgoing, SENDER for incoming, fallback to name
            let recipient = fields[9]
            let sender    = fields[10]
            let merchant  = rawAmount < 0
                ? (recipient.isEmpty ? activityName : recipient)
                : (sender.isEmpty    ? activityName : sender)

            let category = categorize(activityType: activityType, name: activityName,
                                      merchant: merchant, amount: rawAmount)

            result.append(BankTransaction(
                date:         date,
                description:  activityName,
                rawAmount:    rawAmount,
                valueDate:    date,
                category:     category,
                merchantName: merchant
            ))
        }

        guard !result.isEmpty else { throw BankParseError.noTransactionsFound }
        return result.sorted { $0.date > $1.date }
    }

    private static func unquote(_ s: String) -> String {
        // Strip leading/trailing whitespace and surrounding triple/single quotes
        var t = s.trimmingCharacters(in: .whitespaces)
        while t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }

    private static func categorize(activityType: String, name: String,
                                   merchant: String, amount: Double) -> TransactionCategory {
        switch activityType {
        case "PAYMENT_TRANSACTION_IN":
            if name.uppercased().hasPrefix("TWINT VON") { return .transfer }
            return .einkommen
        case "CASH_TRANSACTION_RELATED_OTHER", "CASH_TRANSACTION_OTHER":
            return amount > 0 ? .einkommen : .sonstiges
        case "GOAL_AUTO_DEPOSIT", "GOAL_WITHDRAWAL":
            return .transfer
        case "PAYMENT_TRANSACTION_OUT":
            let upper = name.uppercased()
            if upper.contains("DAUERAUFTRAG") { return .dauerauftrag }
            if upper.contains("TWINT") { return .transfer }
            return Categorizer.categorizeByMerchant(merchant)
        case "CARD_TRANSACTION_OUT":
            return Categorizer.categorizeByMerchant(merchant)
        default:
            return .sonstiges
        }
    }
}

// MARK: - SwissCard Parser
//
// Supports both CSV (comma-separated, RFC 4180 quoted) and XLSX format.
// Auto-detection: XLSX starts with ZIP magic bytes PK\x03\x04.
//
// Amount sign convention: SwissCard CSV uses positive = expense (Belastung),
// negative = credit/payment (Gutschrift). Our rawAmount: negative = expense.
// Therefore rawAmount = -(csvAmount).
//
// CSV columns (comma-separated, quoted):
//   0  Transaktionsdatum   – DD.MM.YYYY
//   1  Beschreibung        – transaction description
//   2  Händler             – merchant name (may be empty)
//   3  Kartennummer
//   4  Währung             – currency
//   5  Betrag              – CHF amount (positive = expense, negative = credit)
//   6  Fremdwährung
//   7  Betrag in Fremdwährung
//   8  Debit/Kredit        – "Belastung" or "Gutschrift"
//   9  Status
//  10  Händlerkategorie    – SwissCard category string
//  11  Registrierte Kategorie

private enum SwissCardParser {

    static func parse(data: Data) throws -> [BankTransaction] {
        // ZIP/XLSX magic: PK\x03\x04
        if data.count >= 4, data[0] == 0x50, data[1] == 0x4B, data[2] == 0x03, data[3] == 0x04 {
            return try parseXLSX(data)
        }
        guard let content = String(data: data, encoding: .utf8)
                         ?? String(data: data, encoding: .isoLatin1) else {
            throw BankParseError.unsupportedEncoding
        }
        return try parseCSV(content)
    }

    // MARK: CSV

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale     = Locale(identifier: "de_CH")
        f.timeZone   = TimeZone(identifier: "Europe/Zurich")
        return f
    }()

    private static func parseCSV(_ content: String) throws -> [BankTransaction] {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { throw BankParseError.noTransactionsFound }

        var result: [BankTransaction] = []
        for line in lines.dropFirst() {
            let fields = splitCSVLine(line)
            guard fields.count >= 9 else { continue }

            let dateStr  = fields[0]
            let desc     = fields[1]
            let merchant = fields[2]
            let amtStr   = fields[5].replacingOccurrences(of: ",", with: ".")
            let scCat    = fields.count >= 11 ? fields[10] : ""

            guard let date      = dateFmt.date(from: dateStr),
                  let csvAmount = Double(amtStr) else { continue }

            let rawAmount = -csvAmount
            let effectiveMerchant = merchant.isEmpty ? desc : merchant
            let category = mapCategory(swissCardCategory: scCat, merchant: effectiveMerchant,
                                       description: desc, rawAmount: rawAmount)
            result.append(BankTransaction(
                date:         date,
                description:  desc,
                rawAmount:    rawAmount,
                valueDate:    date,
                category:     category,
                merchantName: effectiveMerchant
            ))
        }
        guard !result.isEmpty else { throw BankParseError.noTransactionsFound }
        return result.sorted { $0.date > $1.date }
    }

    // RFC 4180 CSV parser: handles quoted fields with embedded commas and escaped quotes.
    private static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if inQuotes {
                if c == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "\"" {
                        current.append("\"")
                        i = line.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    current.append(c)
                }
            } else {
                if c == "\"" { inQuotes = true }
                else if c == "," { fields.append(current); current = "" }
                else { current.append(c) }
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }

    // MARK: XLSX

    private static func parseXLSX(_ data: Data) throws -> [BankTransaction] {
        guard let sheetData = extractXLSXSheet(data) else { throw BankParseError.invalidFormat }

        let delegate = SheetXMLDelegate()
        let parser   = XMLParser(data: sheetData)
        parser.delegate = delegate
        parser.parse()

        let rows = delegate.rows
        guard !rows.isEmpty else { throw BankParseError.noTransactionsFound }

        var result: [BankTransaction] = []
        for row in rows.dropFirst() {      // skip header row
            guard let dateVal = row[0], let amtVal = row[5],
                  let serial    = Double(dateVal),
                  let csvAmount = Double(amtVal) else { continue }

            let date     = excelSerialToDate(serial)
            let desc     = row[1] ?? ""
            let merchant = row[2] ?? ""
            let scCat    = row[10] ?? ""

            let rawAmount = -csvAmount
            let effectiveMerchant = merchant.isEmpty ? desc : merchant
            let category = mapCategory(swissCardCategory: scCat, merchant: effectiveMerchant,
                                       description: desc, rawAmount: rawAmount)
            result.append(BankTransaction(
                date:         date,
                description:  desc,
                rawAmount:    rawAmount,
                valueDate:    date,
                category:     category,
                merchantName: effectiveMerchant
            ))
        }
        guard !result.isEmpty else { throw BankParseError.noTransactionsFound }
        return result.sorted { $0.date > $1.date }
    }

    // Excel date serial: days since December 30, 1899.
    private static func excelSerialToDate(_ serial: Double) -> Date {
        Date(timeIntervalSince1970: (serial - 25569.0) * 86400.0)
    }

    // MARK: ZIP / XLSX extraction

    private static func extractXLSXSheet(_ data: Data) -> Data? {
        guard let eocdOff = findEOCD(data) else { return nil }
        let cdOffset = readUInt32(data, at: eocdOff + 16)
        let cdSize   = readUInt32(data, at: eocdOff + 12)

        var pos = cdOffset
        while pos + 46 <= cdOffset + cdSize, pos + 46 <= data.count {
            guard readUInt32(data, at: pos) == 0x02014B50 else { break }

            let method           = readUInt16(data, at: pos + 10)
            let compressedSize   = readUInt32(data, at: pos + 20)
            let uncompressedSize = readUInt32(data, at: pos + 24)
            let nameLen          = readUInt16(data, at: pos + 28)
            let extraLen         = readUInt16(data, at: pos + 30)
            let commentLen       = readUInt16(data, at: pos + 32)
            let localOffset      = readUInt32(data, at: pos + 42)

            if pos + 46 + nameLen <= data.count,
               let name = String(data: data.subdata(in: (pos + 46)..<(pos + 46 + nameLen)), encoding: .utf8),
               name == "xl/worksheets/sheet1.xml" {
                return extractEntry(data, localOffset: localOffset,
                                    compressedSize: compressedSize,
                                    uncompressedSize: uncompressedSize,
                                    method: method)
            }
            pos += 46 + nameLen + extraLen + commentLen
        }
        return nil
    }

    private static func findEOCD(_ data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let minSearch = max(0, data.count - 65557)
        for i in stride(from: data.count - 22, through: minSearch, by: -1) {
            if data[i] == 0x50, data[i+1] == 0x4B, data[i+2] == 0x05, data[i+3] == 0x06 {
                return i
            }
        }
        return nil
    }

    private static func extractEntry(_ data: Data, localOffset: Int,
                                     compressedSize: Int, uncompressedSize: Int,
                                     method: Int) -> Data? {
        guard localOffset + 30 <= data.count,
              readUInt32(data, at: localOffset) == 0x04034B50 else { return nil }

        let nameLen  = readUInt16(data, at: localOffset + 26)
        let extraLen = readUInt16(data, at: localOffset + 28)
        let dataStart = localOffset + 30 + nameLen + extraLen

        guard dataStart + compressedSize <= data.count else { return nil }
        let compressed = data.subdata(in: dataStart..<(dataStart + compressedSize))

        switch method {
        case 0: return compressed
        case 8: return inflateRawDeflate(compressed)
        default: return nil
        }
    }

    // MARK: Raw DEFLATE decompression (zlib, windowBits = -15)

    private static func inflateRawDeflate(_ compressed: Data) -> Data? {
        guard !compressed.isEmpty else { return nil }

        var strm = z_stream()
        guard inflateInit2_(&strm, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&strm) }

        let chunkSize = 65536
        var outBuf    = Data(count: chunkSize)
        var output    = Data()

        return compressed.withUnsafeBytes { (inPtr: UnsafeRawBufferPointer) -> Data? in
            guard let inBase = inPtr.baseAddress else { return nil }
            strm.next_in  = UnsafeMutablePointer(mutating: inBase.assumingMemoryBound(to: Bytef.self))
            strm.avail_in = uInt(compressed.count)

            repeat {
                let status = outBuf.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) -> Int32 in
                    strm.next_out  = outPtr.baseAddress?.assumingMemoryBound(to: Bytef.self)
                    strm.avail_out = uInt(chunkSize)
                    return inflate(&strm, Z_NO_FLUSH)
                }
                guard status != Z_STREAM_ERROR, status != Z_DATA_ERROR, status != Z_MEM_ERROR else {
                    return nil
                }
                let have = chunkSize - Int(strm.avail_out)
                output.append(outBuf.prefix(have))
                if status == Z_STREAM_END { break }
            } while strm.avail_out == 0

            return output.isEmpty ? nil : output
        }
    }

    // MARK: XML Delegate

    private class SheetXMLDelegate: NSObject, XMLParserDelegate {
        var rows: [[String?]] = []
        private var currentRow: [String?] = Array(repeating: nil, count: 12)
        private var currentColIndex = -1
        private var currentCellType = ""
        private var charBuffer      = ""
        private var collectingValue = false
        private var inRow           = false

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            switch elementName {
            case "row":
                currentRow = Array(repeating: nil, count: 12)
                inRow = true
            case "c":
                let ref = attributeDict["r"] ?? ""
                currentColIndex = columnIndex(String(ref.prefix(while: { $0.isLetter })))
                currentCellType = attributeDict["t"] ?? ""
                charBuffer      = ""
                collectingValue = false
            case "v":
                charBuffer      = ""
                collectingValue = true
            case "t":
                if currentCellType == "inlineStr" {
                    charBuffer      = ""
                    collectingValue = true
                }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if collectingValue { charBuffer += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName: String?) {
            switch elementName {
            case "v":
                if collectingValue, currentColIndex >= 0, currentColIndex < 12 {
                    currentRow[currentColIndex] = charBuffer
                }
                collectingValue = false
            case "t":
                if currentCellType == "inlineStr", collectingValue,
                   currentColIndex >= 0, currentColIndex < 12 {
                    currentRow[currentColIndex] = charBuffer
                }
                collectingValue = false
            case "row":
                if inRow { rows.append(currentRow) }
                inRow = false
            default: break
            }
        }

        // A=0, B=1, ..., Z=25, AA=26, ...
        private func columnIndex(_ letters: String) -> Int {
            var result = 0
            for c in letters.uppercased() {
                guard let ascii = c.asciiValue else { continue }
                result = result * 26 + Int(ascii) - 64
            }
            return max(result - 1, -1)
        }
    }

    // MARK: Helpers

    private static func readUInt16(_ data: Data, at offset: Int) -> Int {
        guard offset + 2 <= data.count else { return 0 }
        return Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> Int {
        guard offset + 4 <= data.count else { return 0 }
        return Int(data[offset])
             | (Int(data[offset + 1]) << 8)
             | (Int(data[offset + 2]) << 16)
             | (Int(data[offset + 3]) << 24)
    }

    // MARK: Category mapping

    private static func mapCategory(swissCardCategory scCat: String,
                                    merchant: String, description: String,
                                    rawAmount: Double) -> TransactionCategory {
        switch scCat {
        case "Zahlungen":              return .transfer
        case "Reisen":                 return .reisen
        case "Unterhaltung":           return .freizeit
        case "Shopping":               return .shopping
        case "Lebensmittel":           return .lebensmittel
        case "Transport":              return .transport
        case "Gesundheit":             return .gesundheit
        case "Restaurants", "Restaurant": return .restaurant
        case "Tankstellen":            return .tanken
        case "Allgemein":
            if description.uppercased().contains("CASHBACK") { return .bank }
            return Categorizer.categorizeByMerchant(merchant, amount: rawAmount)
        default:
            return Categorizer.categorizeByMerchant(merchant, amount: rawAmount)
        }
    }
}

// MARK: - UBS Parser
//
// CSV columns (semicolon-separated):
//   0  Abschlussdatum   – dd.MM.yy  (closing date)
//   1  Abschlusszeit    – HH:mm:ss  (optional)
//   2  Buchungsdatum    – dd.MM.yy
//   3  Valutadatum      – dd.MM.yy
//   4  Währung          – currency code (e.g. CHF)
//   5  Belastung        – debit amount (negative, e.g. -7.20); empty for credits
//   6  Gutschrift       – credit amount (positive); empty for debits
//   7  Einzelbetrag     – partial amount (often empty)
//   8  Saldo            – running balance (often empty)
//   9  Transaktions-Nr. – internal reference
//  10  Beschreibung1    – primary description / merchant
//  11  Beschreibung2    – secondary description
//  12  Beschreibung3    – additional details
//  13  Fussnoten        – footnotes

private enum UBSParser {

    // UBS exports yyyy-MM-dd (new portal / ISO 8601), dd.MM.yy or dd.MM.yyyy
    private static let dateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "dd.MM.yy", "dd.MM.yyyy"].map { fmt in
            let f = DateFormatter()
            f.dateFormat = fmt
            f.locale = Locale(identifier: "de_CH")
            f.timeZone = TimeZone(identifier: "Europe/Zurich")
            return f
        }
    }()

    private static func parseDate(_ s: String) -> Date? {
        for f in dateFormatters { if let d = f.date(from: s) { return d } }
        return nil
    }

    private static func parseAmount(_ s: String) -> Double? {
        let cleaned = s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    static func parse(content: String) throws -> [BankTransaction] {
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // Locate the column header row — use contains so quoted headers and BOM remnants don't break detection
        guard let headerIdx = lines.firstIndex(where: {
            $0.contains("Abschlussdatum") && $0.contains("Buchungsdatum") && $0.contains("Belastung")
        }) else {
            throw BankParseError.invalidFormat
        }

        // Resolve column positions from the header for robustness against export version differences
        let headerFields = lines[headerIdx].components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        let colDate   = headerFields.firstIndex(of: "Abschlussdatum")         ?? 0
        let colValuta = headerFields.firstIndex(of: "Valutadatum")            ?? 3
        let colDebit  = headerFields.firstIndex(where: { $0.contains("Belastung") })  ?? 5
        let colCredit = headerFields.firstIndex(where: { $0.contains("Gutschrift") }) ?? 6
        let colDesc1  = headerFields.firstIndex(of: "Beschreibung1")          ?? 10
        let colDesc2  = headerFields.firstIndex(of: "Beschreibung2")          ?? 11
        let colDesc3  = headerFields.firstIndex(of: "Beschreibung3")          ?? 12

        var result: [BankTransaction] = []

        for line in lines[(headerIdx + 1)...] {
            guard !line.isEmpty else { continue }
            let fields = splitFields(line)
            guard fields.count > max(colDate, colDebit, colCredit) else { continue }

            let dateStr   = fields[colDate].trimmingCharacters(in: .whitespaces)
            let valStr    = colValuta < fields.count ? fields[colValuta].trimmingCharacters(in: .whitespaces) : dateStr
            let debitStr  = colDebit  < fields.count ? fields[colDebit].trimmingCharacters(in: .whitespaces) : ""
            let creditStr = colCredit < fields.count ? fields[colCredit].trimmingCharacters(in: .whitespaces) : ""
            let desc1     = colDesc1  < fields.count ? fields[colDesc1].trimmingCharacters(in: .whitespaces) : ""
            let desc2     = colDesc2  < fields.count ? fields[colDesc2].trimmingCharacters(in: .whitespaces) : ""
            let desc3     = colDesc3  < fields.count ? fields[colDesc3].trimmingCharacters(in: .whitespaces) : ""

            guard let date = parseDate(dateStr) else { continue }

            let rawAmount: Double
            if !debitStr.isEmpty, let v = parseAmount(debitStr), v != 0 {
                // Belastung is negative in UBS exports; force negative to be safe
                rawAmount = v < 0 ? v : -v
            } else if !creditStr.isEmpty, let v = parseAmount(creditStr), v != 0 {
                // Gutschrift is positive
                rawAmount = v > 0 ? v : -v
            } else {
                continue
            }

            let descParts = [desc1, desc2, desc3].filter { !$0.isEmpty }
            let desc = descParts.joined(separator: " ")

            let valueDate = parseDate(valStr) ?? date
            let merchant  = extractMerchant(desc1: desc1, desc2: desc2)
            let category  = categorize(desc1: desc1, desc2: desc2, desc3: desc3, fullDesc: desc, amount: rawAmount)

            result.append(BankTransaction(
                date:         date,
                description:  desc,
                rawAmount:    rawAmount,
                valueDate:    valueDate,
                category:     category,
                merchantName: merchant
            ))
        }

        guard !result.isEmpty else { throw BankParseError.noTransactionsFound }
        return result.sorted { $0.date > $1.date }
    }

    // Beschreibung1 is the most concise label (e.g. "COOP-3306 STEINHAUSEN").
    // UBS sometimes embeds the payment type after a semicolon inside the quoted field, so strip it.
    // Beschreibung2 contains the payment type — use as fallback.
    private static func extractMerchant(desc1: String, desc2: String) -> String {
        var d1 = desc1.trimmingCharacters(in: .whitespaces)
        if let semiRange = d1.range(of: ";") {
            d1 = String(d1[d1.startIndex..<semiRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        if !d1.isEmpty { return Categorizer.extractMerchant(from: d1) }
        let d2 = desc2.trimmingCharacters(in: .whitespaces)
        if !d2.isEmpty { return Categorizer.extractMerchant(from: d2) }
        return ""
    }

    private static func categorize(desc1: String, desc2: String, desc3: String,
                                   fullDesc: String, amount: Double) -> TransactionCategory {
        let d2 = desc2.trimmingCharacters(in: .whitespaces)
        let d3 = desc3.trimmingCharacters(in: .whitespaces)

        // Salary
        if d2 == "Salaereingang" { return .einkommen }

        // TWINT private transfers (phone number in desc3 = person-to-person)
        if d2.contains("UBS TWINT") && d3.contains("+41") { return .transfer }

        let cat = Categorizer.categorize(description: fullDesc, amount: amount)

        // Dauerauftrag: if general categorizer returned .sonstiges but desc signals standing order
        if cat == .sonstiges && d2.uppercased().contains("DAUERAUFTRAG") { return .dauerauftrag }

        return cat
    }

    // RFC 4180-style split on semicolons, respecting double-quoted fields.
    private static func splitFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for c in line {
            if inQuotes {
                if c == "\"" { inQuotes = false }
                else { current.append(c) }
            } else {
                if c == "\"" { inQuotes = true }
                else if c == ";" { fields.append(current); current = "" }
                else { current.append(c) }
            }
        }
        fields.append(current)
        return fields
    }
}

// MARK: - Custom Category Rules

struct CategoryRule: Codable, Identifiable {
    var id: UUID = UUID()
    var keyword: String            // matched against uppercased merchant name (contains check)
    var categoryRaw: String        // TransactionCategory.rawValue
    var isAutoGenerated: Bool = false
    var amountMin: Double? = nil   // optional lower bound on abs(amount); nil = no restriction
    var amountMax: Double? = nil   // optional upper bound on abs(amount); nil = no restriction
    var accountIDs: [UUID]? = nil  // nil = applies to all accounts

    var category: TransactionCategory? { TransactionCategory(rawValue: categoryRaw) }
    var isAmountFiltered: Bool { amountMin != nil || amountMax != nil }
    var isAccountFiltered: Bool { !(accountIDs?.isEmpty ?? true) }

    var isWildcard: Bool { keyword == "*" }

    func matches(merchant: String, amount: Double, accountID: UUID? = nil, userNote: String = "") -> Bool {
        guard !keyword.isEmpty else { return false }
        if !isWildcard {
            let kw = keyword.uppercased()
            let textMatch = merchant.uppercased().contains(kw)
                         || (!userNote.isEmpty && userNote.uppercased().contains(kw))
            guard textMatch else { return false }
        }
        if let min = amountMin, amount < min { return false }
        if let max = amountMax, amount > max { return false }
        if let ids = accountIDs, !ids.isEmpty {
            // Account-scoped: only matches when the account is known and is in the allowed list.
            // Never matches when accountID is nil (e.g. during initial parsing before account is assigned).
            guard let acctID = accountID, ids.contains(acctID) else { return false }
        }
        return true
    }
}

enum CustomRulesStore {
    private static let legacyKey = "user_category_rules_v1"

    private static var activeProfileID: String {
        UserDefaults.standard.string(forKey: "active_profile_id") ?? ""
    }

    private static func profileKey(_ profileID: String) -> String {
        "user_category_rules_v2_\(profileID)"
    }

    static func load(profileID: String? = nil) -> [CategoryRule] {
        let pid = profileID ?? activeProfileID
        guard !pid.isEmpty else { return [] }
        let pKey = profileKey(pid)

        if let data = UserDefaults.standard.data(forKey: pKey),
           let rules = try? JSONDecoder().decode([CategoryRule].self, from: data) {
            return rules
        }

        // One-time migration: copy rules from the old single-profile key to this profile's key.
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let rules = try? JSONDecoder().decode([CategoryRule].self, from: data) {
            save(rules, profileID: pid)
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return rules
        }

        return []
    }

    static func save(_ rules: [CategoryRule], profileID: String? = nil) {
        let pid = profileID ?? activeProfileID
        guard !pid.isEmpty else { return }
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: profileKey(pid))
        }
    }

    // Creates an auto-generated rule from a manual categorization; skips if keyword already exists.
    static func addAutoRule(merchant: String, category: TransactionCategory, profileID: String? = nil) {
        let kw = merchant.uppercased().trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        var rules = load(profileID: profileID)
        guard !rules.contains(where: { $0.keyword.uppercased() == kw }) else { return }
        rules.insert(CategoryRule(keyword: kw, categoryRaw: category.rawValue, isAutoGenerated: true), at: 0)
        save(rules, profileID: profileID)
    }

    /// Upserts an auto-generated rule for the merchant: if a rule with the same keyword exists,
    /// its category is overwritten; otherwise a new rule is inserted at the top.
    /// Used by "Auf alle anwenden" so user intent always overrides earlier auto-categorization.
    static func upsertAutoRule(merchant: String, category: TransactionCategory, profileID: String? = nil) {
        let kw = merchant.uppercased().trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        var rules = load(profileID: profileID)
        if let idx = rules.firstIndex(where: { $0.keyword.uppercased() == kw }) {
            rules[idx].categoryRaw = category.rawValue
            rules[idx].isAutoGenerated = true
            // Move to front so it wins ordering ties.
            let updated = rules.remove(at: idx)
            rules.insert(updated, at: 0)
        } else {
            rules.insert(CategoryRule(keyword: kw, categoryRaw: category.rawValue, isAutoGenerated: true), at: 0)
        }
        save(rules, profileID: profileID)
    }
}

// MARK: - Note Rules

struct NoteRule: Codable, Identifiable {
    var id: UUID = UUID()
    var merchantName: String   // exact match on uppercased merchant
    var amount: Double         // exact abs-amount this rule was created for
    var noteText: String

    func matches(merchant: String, amount txAmount: Double) -> Bool {
        guard !merchantName.isEmpty else { return false }
        return merchant.uppercased() == merchantName.uppercased()
            && abs(txAmount - amount) < 0.005   // floating-point safe equality
    }
}

enum NoteRulesStore {
    private static var activeProfileID: String {
        UserDefaults.standard.string(forKey: "active_profile_id") ?? ""
    }
    private static func key(_ pid: String) -> String { "note_rules_v1_\(pid)" }

    static func load(profileID: String? = nil) -> [NoteRule] {
        let pid = profileID ?? activeProfileID
        guard !pid.isEmpty,
              let data = UserDefaults.standard.data(forKey: key(pid)),
              let rules = try? JSONDecoder().decode([NoteRule].self, from: data) else { return [] }
        return rules
    }

    static func save(_ rules: [NoteRule], profileID: String? = nil) {
        let pid = profileID ?? activeProfileID
        guard !pid.isEmpty else { return }
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: key(pid))
        }
    }

    static func addOrUpdate(merchantName: String, amount: Double, noteText: String, profileID: String? = nil) {
        guard !merchantName.isEmpty else { return }
        var rules = load(profileID: profileID)
        rules.removeAll { $0.matches(merchant: merchantName, amount: amount) }
        if !noteText.isEmpty {
            rules.insert(NoteRule(merchantName: merchantName, amount: amount, noteText: noteText), at: 0)
        }
        save(rules, profileID: profileID)
    }
}

// MARK: - Categorizer

enum Categorizer {

    static func categorize(description: String, amount: Double, accountID: UUID? = nil) -> TransactionCategory {
        let d = description.uppercased()

        // --- Strukturierte Buchungstypen ---
        if d.hasPrefix("ÜBERTRAG") || d.hasPrefix("UBERTRAG") || d.hasPrefix("\u{DC}BERTRAG") { return .transfer }
        if d.hasPrefix("ZAHLUNGSEINGANG") { return amount > 0 ? .einkommen : .sonstiges }
        if d.hasPrefix("SALDO DER ABSCHLUSS") { return .bank }
        if d.hasPrefix("TWINT-GUTSCHRIFT") {
            return d.contains("+41") ? .transfer : (amount > 0 ? .einkommen : .transfer)
        }
        if d.hasPrefix("TWINT-BELASTUNG") && d.contains("+41") { return .transfer }
        // TWINT zu Firmen (kein +41): weiter zu Keyword-Matching
        if d.hasPrefix("VERG") || d.hasPrefix("VERG\u{DC}") {
            if d.contains("BANKERS") { return .transfer }
            return amount > 0 ? .einkommen : .sonstiges
        }
        if d.hasPrefix("DAUERAUFTRAG") { return .dauerauftrag }
        if d.hasPrefix("EINZAHLUNG") { return amount > 0 ? .einkommen : .transfer }

        let merchant = extractMerchant(from: description)
        return categorizeByMerchant(merchant, amount: amount, accountID: accountID)
    }

    // Shared DACH merchant categorizer — bank-independent, works on a clean merchant name
    static func categorizeByMerchant(_ merchant: String, amount: Double = 0, accountID: UUID? = nil) -> TransactionCategory {
        let m = merchant.uppercased()

        // User-defined rules always take priority — amount-filtered rules checked first (more specific)
        let sorted = CustomRulesStore.load().sorted { $0.isAmountFiltered && !$1.isAmountFiltered }
        for rule in sorted {
            guard rule.matches(merchant: m, amount: amount, accountID: accountID), let cat = rule.category else { continue }
            return cat
        }

        // --- Sparen ---
        if containsAny(m, ["SPARKONTO", "SPARKASSE", "SPARBUCH", "EINLAGE SPAR", "SPAREINLAGE",
                            "SÄULE 3A", "SAULE 3A", "PILLAR 3A",
                            "FINPENSION", "VIAC", "FRANKLY", "VITA INVEST",
                            "VALUEPENSION", "SMARTA", "POSTFINANCE SPAREN",
                            "SPAREN"]) { return .sparen }

        // --- Investieren ---
        if containsAny(m, ["DEGIRO", "INTERACTIVE BROKERS", "IBKR",
                            "TRADE REPUBLIC", "SCALABLE CAPITAL", "FLATEX",
                            "NEON INVEST", "YOVA", "TRUE WEALTH", "TRUEWEALTH",
                            "DESCARTES FINANCE", "SELMA FINANCE", "FINDEPENDENT",
                            "POSTFINANCE INVEST", "SWISSQUOTE", "CORNÈRTRADER",
                            "SAXO BANK", "ETORO", "WEALTHFRONT", "BETTERMENT",
                            "INVESTIEREN"]) { return .investieren }

        // --- Auto & Fahrzeug ---
        if containsAny(m, ["AUTOSERVICE", "AUTOGARAGE", "AUTOWERKSTATT", "GARAGE",
                            "KFZ", "KFZ-", "FAHRZEUGPRÜFUNG", "MFK", "TÜV", "TUEV",
                            "MOTORFAHRZEUGKONTROLLE", "STRASSENVERKEHR",
                            "AUTOBESCHRIFTUNG", "AUTOAUFBEREITUNG",
                            "AUTOWÄSCHE", "AUTOWASCHE", "WASCHANLAGE", "CARWASH",
                           "CAR WASH",
                            "KFZVERSICHERUNG", "AUTO ERSATZ", "AUTOERSATZ",
                            "VELOUNFALL", "PANNENHILFE", "ABSCHLEPPDIENST",
                            "AUTOCENTER",
                            "REIFENWECHSEL", "PNEUHAUS", "PNEU", "REIFENSERVICE",
                            "AUTOCENTER ZOLLIKON"]) { return .auto }

        // --- Tanken ---
        if containsAny(m, ["TANKOMAT", "TANKSTELLE", "TANKEN", "ZAPFSÄULE",
                            "FILLING STATION", "GAS STATION", "PETROL STATION",
                            "SOCAR", "SHELL", "AGROLA", "MIGROL", "ESSO", "AVIA", "TOTAL",
                            "OMV", "ARAL", "BP", "TAMOIL", "JET", "CIRCLE K",
                            "REPSOL", "AGIP", "ENI", "Q8", "GULF", "ORLEN",
                            "CEPSA", "NESTE", "ST1", "OKQ8", "UNO-X",
                            "HOFER TANKSTELLE", "MOVERI", "EUROOIL"]) { return .tanken }
        if m.contains(" OIL") || m.hasPrefix("OIL") { return .tanken }
        if m.contains("MOL ") && !m.contains("SCHOOL") { return .tanken }

        // --- Transport ---
        if containsAny(m, ["SBB CFF", "SBB", "ZVV", "VBZ", "BVB", "BVG",
                            "MVG", "MVV", "TRAM", "S-BAHN", "U-BAHN",
                            "THURBO", "SOB", "BLS", "ZENTRALBAHN",
                            "RHÄTISCHE BAHN", "RHB", "APPENZELLER BAHN", "MATTERHORN GOTTHARD",
                            "POSTAUTO", "POSTBUS", "FLIXBUS", "BLABLACAR",
                            "INTERCITY", "INTERREGIO", "EUROCITY", "RAILJET"]) { return .transport }
        if containsAny(m, ["PARKINGPAY", "PARKING", "PARKHAUS", "TIEFGARAGE",
                            "EASYPARK", "PARK NOW", "PARKNOW", "PARKRIGHT",
                            "VERENAHOF", "METALLI"]) { return .transport }
        if containsAny(m, ["MOBILE SUICA", "ASFINAG", "VIGNETTE", "AUTOBAHN",
                            "MAUT", "VIAPASS", "EUROVIGNETTE"]) { return .transport }
        if containsAny(m, ["MOBILITY", "SIXT", "HERTZ", "AVIS", "EUROPCAR",
                            "LIME", "TIER", "NEXTBIKE", "PUBLIBIKE"]) { return .transport }

        // --- Uber (special case) ---
        if m.contains("UBER") && containsAny(m, ["MEMBERSHIP", "ONE MEMBER"]) { return .abonnement }
        if m.contains("UBER") && m.contains("EAT") { return .restaurant }
        if m.contains("UBER") { return .transport }

        // --- Versicherung ---
        if containsAny(m, ["MOBILIAR", "ALLIANZ", "GENERALI", "HELVETIA", "BALOISE",
                            "BASLER VERS", "VAUDOISE", "SWISS LIFE", "SWISSLIFE",
                            "AXA", "ZURICH VERS", "ZÜRICH VERS", "ZURICH INSURANCE",
                            "TCS", "REGA", "ÖAMTC", "ADAC",
                            "ERGO", "HUK COBURG", "DEVK", "GOTHAER", "UNIQA",
                            "WIENER STÄDTISCHE", "HELVETIA VERS",
                            "KRANKENKASSE", "HAFTPFLICHT VERS",
                            "RECHTSSCHUTZ VERS", "MOTORFAHRZEUG VERS"]) { return .versicherung }

        // --- Steuern & staatliche Abgaben ---
        // Checked before Wohnen so "GEMEINDESTEUER" doesn't match the "GEMEINDEWERKE" pattern.
        if containsAny(m, ["STEUERAMT", "STEUERVERWALTUNG", "STEUERVERWALTUNGEN",
                            "FINANZAMT", "FINANZDIREKTION", "STEUERN",
                            "STEUERAUSGLEICH", "STEUERRÜCKZAHLUNG",
                            "GEMEINDESTEUER", "KANTONSSTEUER", "BUNDESSTEUER",
                            "STAATSSTEUER", "QUELLENSTEUER", "EINKOMMENSSTEUER",
                            "VERMÖGENSSTEUER", "GRUNDSTÜCKGEWINNSTEUER",
                            "ERBSCHAFTSSTEUER", "SCHENKUNGSSTEUER",
                            "MEHRWERTSTEUER", "MWST", "MWST.",
                            "BILLAG", "SERAFE",
                            "AHV", "AHV-BEITRAG", "AHV-IV",
                            "IV-BEITRAG", "EO-BEITRAG",
                            "AUSGLEICHSKASSE", "SVA ", "SVA-",
                            "PENSIONSKASSE BVG", "BVG-BEITRAG",
                            "ZOLL", "EIDG. ZOLLVERWALTUNG", "EZV ",
                            "GEMEINDEVERWALTUNG", "STADTVERWALTUNG",
                            "EINWOHNERDIENSTE", "STRASSENVERKEHRSAMT",
                            "PASSBÜRO", "PASSAMT", "AUSWEISGEBÜHR"]) { return .steuern }

        // --- Wohnen ---
        if containsAny(m, ["NEBENKOSTEN", "HAUSGELD", "MIETE",
                            "EWZ", "EWL", "AEW", "BKW", "WWZ", "AXPO", "SWISSGAS",
                            "STADTWERKE", "GEMEINDEWERKE", "ENERGIE WASSER",
                            "FERNWÄRME", "ERDGAS", "GASWERK",
                            "REINIGUNGSDIENST", "HAUSREINIGUNG", "QUITT",
                            "MÖBELTRANSPORT", "UMZUG", "ZÜGEL",
                            "SCHLÜSSELDIENST", "SELFSTORAGE", "PFLANZEN"]) { return .wohnen }

        // --- Bank & Finanzen ---
        if containsAny(m, ["KONTOGEBÜHR", "JAHRESGEBÜHR", "BANKGEBÜHR", "KARTENGEBÜHR",
                            "BETREIBUNG", "MAHNGEBÜHR", "VERZUGSZINS",
                            "ABSCHLUSSGEBÜHR"]) { return .bank }

        // --- Abonnements ---
        if containsAny(m, ["APPLE.COM", "CLAUDE.AI", "ANTHROPIC", "NETFLIX", "SPOTIFY",
                            "DISNEY", "XBOX GAME", "ADOBE", "AMAZON PRIME",
                            "KABELSCHWEIZ", "NORDVPN", "EXPRESSVPN", "SURFSHARK", "PROTONVPN",
                            "YOUTUBE PREMIUM", "TWITCH", "DAZN", "SKY ABO",
                            "READLY", "AUDIBLE", "KINDLE",
                            "DUOLINGO", "BABBEL", "LINKEDIN PREMIUM",
                            "MICROSOFT 365", "OFFICE 365", "DROPBOX", "GOOGLE ONE",
                            "1PASSWORD", "BITWARDEN", "DASHLANE",
                            "HEADSPACE", "CALM", "STRAVA ABO", "ZWIFT",
                            "SWISSCOM ABO", "SUNRISE ABO", "SALT ABO", "INIT7",
                            "SERAFE"]) { return .abonnement }

        // --- Bildung ---
        if containsAny(m, ["UDEMY", "COURSERA", "SKILLSHARE", "MASTERCLASS", "LINKEDIN LEARNING",
                            "VOLKSHOCHSCHULE", "WEITERBILDUNG", "SEMINARGEBÜHR",
                            "SCHULGEBÜHR", "STUDIENGEBÜHR", "KURSGEBÜHR",
                            "MUSIKSCHULE", "MUSIKUNTERRICHT", "SPRACHSCHULE", "SPRACHKURS",
                            "KITA", "KRIPPE", "HORT", "KINDERTAGESSTÄTTE",
                            "NACHHILFE", "LEHRMITTEL"]) { return .bildung }

        // --- Reisen (before Lebensmittel/Restaurant to avoid false matches) ---
        if containsAny(m, ["AIRBNB", "BOOKING.COM", "HOTELS.COM", "EXPEDIA", "TRIVAGO",
                            "HRS", "AGODA", "HOLIDAYCHECK", "LASTMINUTE", "OPODO",
                            "CHECK24", "KAYAK", "MOMONDO", "SKYSCANNER",
                            "HOTELPLAN", "KUONI", "TUI", "HELVETIC TOURS",
                            "HOTEL", "HOSTEL", "RESORT", "CAMPINGPLATZ", "CAMPING"]) { return .reisen }
        if containsAny(m, ["LUFTHANSA", "SWISS", "EDELWEISS AIR", "AUSTRIAN AIR",
                            "CONDOR", "EUROWINGS", "RYANAIR", "EASYJET", "WIZZ AIR",
                            "TRANSAVIA", "PEGASUS AIR", "VUELING", "TAP AIR",
                            "IBERIA", "FINNAIR", "SAS", "LOT", "KLM", "AIR FRANCE",
                            "BRITISH AIRWAYS", "TURKISH AIR", "EMIRATES", "QATAR AIR",
                            "JTRWEB", "JTBJBI", "TRIPLA"]) { return .reisen }

        // --- Lebensmittel ---
        if containsAny(m, ["MIGROS", "COOP", "DENNER", "ALDI", "LIDL", "SPAR",
                            "VOLG", "REWE", "EDEKA", "NETTO", "PENNY", "KAUFLAND",
                            "NORMA", "HOFER", "BILLA", "MERKUR", "MPREIS",
                            "MANOR FOOD", "GLOBUS", "PICK PAY"]) { return .lebensmittel }
        if containsAny(m, ["BÄCKEREI", "BACKEREI", "KONDITOREI", "METZGEREI", "FLEISCHEREI",
                            "KIOSK", "REFORMHAUS", "BIOMARKT", "FARMY",
                            "GMÜESGARTEN", "JUCKER FARM", "HOFLADEN",
                            "WOCHENMARKT", "BAUERNMARKT", "FRISCHMARKT",
                            "HUG ROTKREUZ", "HUG B"]) { return .lebensmittel }

        // --- Restaurant & Café ---
        if containsAny(m, ["MCDONALDS", "MCDONALD", "MCDONALDIS", "MCD",
                            "BURGER KING", "KFC", "FIVE GUYS", "SUBWAY", "DOMINOS",
                            "PIZZA HUT", "STARBUCKS", "COSTA COFFEE", "NORDSEE",
                            "VAPIANO", "TIBITS", "HILTL", "HANS IM GLÜCK",
                            "BREZELKÖNIG", "SPRÜNGLI", "MOLINO", "FORTYSEVEN",
                            "BOOSTBAR", "FOODSTOFFI", "THAI GARDEN", "DOGANS",
                            "HARMLOS", "EIS DIE LAIT", "ZUGER FOOD",
                            "SV (SCHWEI", "SV GROUP",
                            "CE LA VI", "ANDULINO",
                            "GASTRO", "LIBERTY", "MANTRA", "PUB"]) { return .restaurant }
        if containsAny(m, ["RESTAURANT", "CAFÉ", "CAFE", "KAFFEE", "BISTRO", "BRASSERIE",
                            "GROTTO", "OSTERIA", "TRATTORIA", "PIZZERIA", "GELATERIA",
                            "LOUNGE", " BAR ", "MENSA", "TAKE AWAY", "TAKEAWAY",
                            "PIZZA", "SUSHI", "KEBAB", "DÖNER", "DONER", "BURGER",
                            "FALAFEL", "SHAWARMA", "RAMEN", "POKE"]) { return .restaurant }
        if containsAny(m, ["WOLT", "DELIVEROO", "JUSTEAT", "JUST EAT", "LIEFERANDO",
                            "SMILEFOOD", "FOOD-BLITZ", "GLUEHWEIN", "GLÜHWEIN",
                            "SELECTA", "VENDING", "DRINKS OF",
                            "SERWAYS", "BAHNHOFBUFFET"]) { return .restaurant }
        if m.contains("EATS") { return .restaurant }

        // --- Shopping ---
        if containsAny(m, ["AMAZON", "GALAXUS", "DIGITEC", "MEDIAMARKT", "SATURN",
                            "FNAC", "IKEA", "EBAY", "ZALANDO", "ABOUT YOU",
                            "H&M", "ZARA", "MANGO", "UNIQLO", "LEVIS", "LEVI'S",
                            "DEICHMANN", "TAKKO", "TEDI", "KIK", "WOOLWORTH",
                            "OTTO'S", "OTTOS", "SMYTHS", "TOYS R US",
                            "JUMBO", "DECATHLON", "INTERSPORT", "OCHSNER",
                            "NOTINO", "WATERDROP", "DOUGLAS", "MARIONNAUD",
                            "BAUHAUS", "OBI", "HORNBACH", "LIPO",
                            "MÖBEL PFISTER", "DEPOT", "WESTWING", "MÖMAX",
                            "ORELL FÜSSLI", "THALIA", "HUGENDUBEL",
                            "ALIEXPRESS", "SHEIN", "TEMU", "ASOS",
                            "MALL OF", "MICROSPOT", "BRACK", "PANDORA", "PAYPAL",
                            "NESPRESSO", "SCHONE BESCHERUNG",
                            "PAPETERIE", "WOHNCENTER",
                            "AVEC", "LANDI",
                            "BABY-WALZ", "BABYWALZ", "DUTY FREE",
                            "POST CH AG", "POST ONLINE", "POST",
                            "LIVIQUE", "PAPERLAND", "PAPER LAND",
                            "JYSK", "OFFICE WORLD", "ST. KATHARINA"]) { return .shopping }

        // --- Gesundheit ---
        if containsAny(m, ["APOTHEKE", "PHARMACIE", "BENU", "TOPPHARM", "SUNSTORE",
                            "AMAVITA", "COOP VITALITY", "ROSSMANN", "DROGERIE",
                            "DM-DROG", "MÜLLER DROG", "MULLER HANDELS",
                            "ARZT", "HAUSARZT", "PRAXIS", "GRUPPENPRAXIS",
                            "ZAHNARZT", "DENTIST", "ZAHNKLINIK",
                            "PHYSIOTHERAP", "ERGOTHERAP", "LOGOPÄD", "OSTEOPATH",
                            "PSYCHOLOG", "PSYCHIATR", "PSYCHOTHERAP",
                            "AUGENARZT", "OPTIKER", "FIELMANN", "VISILAB",
                            "KLINIK", "HOSPITAL", "SPITAL", "KANTONSSPITAL",
                            "HIRSLANDEN", "SCHULTHESS", "MEDBASE",
                            "PERMANENCE", "WALK IN MED",
                            "NURAVET", "HÖRGERÄTE", "AMPLIFON",
                            "LABOR", "RÖNTGEN", "ULTRASCHALL"]) { return .gesundheit }

        // --- Haustier ---
        if containsAny(m, ["ZOOPLUS", "FRESSNAPF", "QUALIPET", "PETKIT", "ANIMALIA",
                            "MAXI ZOO", "SUPER ZOO", "PETCO", "PETSMART",
                            "TIERARZT", "TIERSPITAL", "TIERKLINIK", "KLEINTIERPRAXIS",
                            "TIERHANDLUNG", "TIERPENSION", "TIERPFLEGE",
                            "HUNDECOIFFEUR", "GROOMING", "TONI'S ZOO",
                            "ROYAL CANIN", "PURINA"]) { return .haustier }

        // --- Freizeit & Sport ---
        if containsAny(m, ["FITNESS", "GYM", "SPORT", "FITNESSCENTER", "FITNESSPARK",
                            "ACTIV FITNESS", "MCFIT", "URBAN SPORTS", "GYMPASS", "WELLPASS",
                            "BOULDER", "KLETTERHALLE", "PADEL", "TENNIS", "GOLF",
                            "SCHWIMMBAD", "HALLENBAD", "STRANDBAD", "FREIBAD",
                            "BERGBAHN", "SEILBAHN", "GONDELBAHN", "SKIPASS", "BERGBAHNEN",
                            "BARBER", "BERBER", "CLUB", "ACTIONWORLD", "BADEPARADIES"]) { return .freizeit }
        if containsAny(m, ["KINO", "CINEMA", "PATHE", "PATHÉ", "CINEPLEX",
                            "THEATER", "OPER", "PHILHARMONIE", "KONZERT",
                            "MUSEUM", "KUNSTHAUS", "TECHNORAMA", "VERKEHRSHAUS",
                            "STEAM", "PLAYSTATION", "EPIC GAMES", "STEAMGAMES",
                            "TICKETCORNER", "EVENTFROG", "STARTICKET", "TICKETMASTER",
                            "ARENA", "STADION",
                            "ESCAPE ROOM", "LASERTAG", "LASERZONE", "PAINTBALL",
                            "BOWLING", "KARTBAHN", "EUROPAPARK", "ALPAMARE",
                            "FLIP LAB", "LIDO", "POINTBREAK", "OPENAIR", "OPEN AIR",
                            "STRANDBAD"]) { return .freizeit }

        return .sonstiges
    }

    static func extractMerchant(from description: String) -> String {
        let d = description

        // Card payments: "Zahlung - MERCHANT - DD.MM.YYYY HH:mm - Karten-Nr. ..."
        // ATM:           "Tankomat - MERCHANT - ..."
        // Deposits:      "Einzahlung - MERCHANT - ..."
        for prefix in ["Zahlung - ", "Tankomat - ", "Einzahlung - "] {
            if d.hasPrefix(prefix) {
                let rest  = String(d.dropFirst(prefix.count))
                let parts = rest.components(separatedBy: " - ")
                if let merchant = parts.first { return merchant.trimmingCharacters(in: .whitespaces) }
            }
        }

        // TWINT
        for prefix in ["TWINT-Belastung ", "TWINT-Gutschrift "] {
            if d.hasPrefix(prefix) {
                var name = String(d.dropFirst(prefix.count))
                // Remove trailing reference (16+ digits)
                if let r = name.range(of: #"\s+\d{16,}$"#, options: .regularExpression) {
                    name = String(name[..<r.lowerBound])
                }
                // Remove phone number ", +41..."
                if let r = name.range(of: #",\s*\+41\S*"#, options: .regularExpression) {
                    name = String(name[..<r.lowerBound])
                }
                return name.trimmingCharacters(in: .whitespaces)
            }
        }

        return d
    }

    private static func containsAny(_ string: String, _ keywords: [String]) -> Bool {
        keywords.contains { string.contains($0) }
    }
}

// MARK: - Recurring Detection

struct RecurringPattern: Identifiable {
    let id = UUID()
    let merchantName: String
    let category: TransactionCategory
    let occurrences: Int          // months this appeared in
    let averageAmount: Double     // average per occurrence
    let transactions: [BankTransaction]
}

enum RecurringDetector {

    static func detect(in transactions: [BankTransaction]) -> [RecurringPattern] {
        let calendar = Calendar.current
        let expenses = transactions.filter { $0.isExpense && $0.category != .transfer }

        // Group by merchant name
        let grouped = Dictionary(grouping: expenses) { $0.merchantName }

        var patterns: [RecurringPattern] = []

        for (merchant, txs) in grouped where txs.count >= 2 {
            // Count distinct months
            let months = Set(txs.map { t -> String in
                let c = calendar.dateComponents([.year, .month], from: t.date)
                return "\(c.year ?? 0)-\(c.month ?? 0)"
            })
            guard months.count >= 2 else { continue }

            let avg = txs.reduce(0) { $0 + $1.amount } / Double(txs.count)
            let cat = txs.first?.category ?? .sonstiges

            patterns.append(RecurringPattern(
                merchantName:  merchant,
                category:      cat,
                occurrences:   months.count,
                averageAmount: avg,
                transactions:  txs.sorted { $0.date > $1.date }
            ))
        }

        return patterns.sorted { $0.averageAmount > $1.averageAmount }
    }
}
