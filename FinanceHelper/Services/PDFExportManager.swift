import UIKit

// MARK: - Internal canvas helper for PDF drawing

private final class PDFCanvas {
    let ctx: UIGraphicsPDFRendererContext
    let pageW: CGFloat = 595
    let pageH: CGFloat = 842
    let margin: CGFloat = 44
    var y: CGFloat = 44

    var contentW: CGFloat { pageW - margin * 2 }

    static let accent = UIColor(red: 0.20, green: 0.52, blue: 0.95, alpha: 1)
    static let green  = UIColor(red: 0.18, green: 0.72, blue: 0.38, alpha: 1)
    static let red    = UIColor(red: 0.88, green: 0.25, blue: 0.25, alpha: 1)
    static let gray6  = UIColor(white: 0.60, alpha: 1)
    static let gray95 = UIColor(white: 0.95, alpha: 1)
    static let black  = UIColor.black

    init(_ ctx: UIGraphicsPDFRendererContext) { self.ctx = ctx }

    func checkBreak(needed: CGFloat) {
        if y + needed > pageH - margin - 24 {
            ctx.beginPage()
            y = margin
        }
    }

    // Draw text at current y and advance y by the rendered height + spacing
    @discardableResult
    func write(
        _ text: String,
        x: CGFloat? = nil,
        font: UIFont,
        color: UIColor = .black,
        w: CGFloat? = nil,
        align: NSTextAlignment = .left,
        spacing: CGFloat = 2
    ) -> CGFloat {
        let h = render(text, at: CGPoint(x: x ?? margin, y: y),
                       font: font, color: color, maxW: w ?? contentW, align: align)
        y += h + spacing
        return h
    }

    // Draw text at an explicit point — does NOT advance y
    @discardableResult
    func render(
        _ text: String,
        at point: CGPoint,
        font: UIFont,
        color: UIColor = .black,
        maxW: CGFloat,
        align: NSTextAlignment = .left
    ) -> CGFloat {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        let h = ceil((text as NSString)
            .boundingRect(with: CGSize(width: maxW, height: 1000),
                          options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
            .size.height)
        (text as NSString).draw(in: CGRect(x: point.x, y: point.y, width: maxW, height: h + 2),
                                withAttributes: attrs)
        return h + 2
    }

    func fillRect(_ rect: CGRect, color: UIColor, radius: CGFloat = 0) {
        color.setFill()
        (radius > 0 ? UIBezierPath(roundedRect: rect, cornerRadius: radius)
                    : UIBezierPath(rect: rect)).fill()
    }

    func strokeRect(_ rect: CGRect, color: UIColor, lw: CGFloat = 1, radius: CGFloat = 0) {
        color.setStroke()
        let p = radius > 0 ? UIBezierPath(roundedRect: rect, cornerRadius: radius)
                           : UIBezierPath(rect: rect)
        p.lineWidth = lw; p.stroke()
    }

    func hRule(color: UIColor = UIColor(white: 0.7, alpha: 0.3)) {
        color.setStroke()
        let p = UIBezierPath()
        p.move(to: CGPoint(x: margin, y: y))
        p.addLine(to: CGPoint(x: margin + contentW, y: y))
        p.lineWidth = 0.5; p.stroke()
    }

    func advance(_ amount: CGFloat) { y += amount }
}

// MARK: - PDF Export Manager

enum PDFExportManager {

    // Fallback exchange rates (EUR base) — same as DashboardViewModel
    private static let fallbackRates: [String: Double] = [
        "EUR": 1.0,   "USD": 1.08,  "GBP": 0.86,  "CHF": 0.96,
        "JPY": 162.0, "CAD": 1.47,  "AUD": 1.64,  "SEK": 11.50,
        "NOK": 11.70, "DKK": 7.46,  "PLN": 4.25,  "CZK": 25.30,
        "HUF": 395.0, "RON": 4.97,  "HKD": 8.45,  "SGD": 1.46,
        "CNY": 7.85,  "INR": 90.0,  "BRL": 5.85,  "MXN": 19.5,
        "ZAR": 20.5,  "TRY": 36.5,  "AED": 3.97,  "SAR": 4.05,
        "KRW": 1450.0, "IDR": 17200.0,
    ]

    private static func convert(_ amount: Double, from: String, to: String) -> Double {
        guard from != to else { return amount }
        let f = fallbackRates[from] ?? 1.0
        let t = fallbackRates[to]  ?? 1.0
        return amount / f * t
    }

    // MARK: - Public API

    static func generateReport(
        accounts: [Account],
        budgetEntries: [BudgetEntry],
        goals: [FinancialGoal],
        userCategories: [UserBudgetCategory] = [],
        transactions: [ImportedTransaction] = [],
        currency: String
    ) -> URL {
        let numFmt = NumberFormatter()
        numFmt.numberStyle = .currency
        numFmt.currencyCode = currency
        numFmt.maximumFractionDigits = 2

        func money(_ v: Double) -> String { numFmt.string(from: NSNumber(value: v)) ?? "\(v)" }
        func tintFor(_ v: Double) -> UIColor { v >= 0 ? PDFCanvas.green : PDFCanvas.red }

        // Compute totals
        let assets      = accounts.filter { !$0.type.isLiability && $0.isVisible }
                                  .sorted { $0.balance > $1.balance }
        let liabilities = accounts.filter {  $0.type.isLiability && $0.isVisible }
                                  .sorted { $0.balance > $1.balance }

        let totalAssets: Double = assets.reduce(0) {
            $0 + convert(max(0, $1.balance), from: $1.currency, to: currency)
        }
        let totalLiab: Double = liabilities.reduce(0) {
            $0 + convert(max(0, $1.balance), from: $1.currency, to: currency)
        }
        let netWorth = totalAssets - totalLiab

        let active = budgetEntries.filter(\.isActive)
        let incomeEntries: [BudgetEntry] = active
            .filter { $0.isIncomeEntry && $0.transferToAccount == nil }
            .sorted { $0.effectiveMonthlyAmount > $1.effectiveMonthlyAmount }
        let expenseEntries: [BudgetEntry] = active
            .filter { !$0.isIncomeEntry && !$0.isSavingsEntry && $0.transferToAccount == nil }
            .sorted { $0.effectiveMonthlyAmount > $1.effectiveMonthlyAmount }
        let savingsEntries: [BudgetEntry] = active
            .filter { $0.isSavingsEntry && $0.transferToAccount == nil }
            .sorted { $0.effectiveMonthlyAmount > $1.effectiveMonthlyAmount }
        let transferEntries: [BudgetEntry] = active
            .filter { $0.transferToAccount != nil }
            .sorted { $0.effectiveMonthlyAmount > $1.effectiveMonthlyAmount }

        let monthlyIncome: Double = incomeEntries.reduce(0) {
            $0 + convert($1.effectiveMonthlyAmount, from: $1.currencyOverride ?? currency, to: currency)
        }
        let monthlyExpenses: Double = expenseEntries.reduce(0) {
            $0 + convert($1.effectiveMonthlyAmount, from: $1.currencyOverride ?? currency, to: currency)
        }
        let monthlySavings: Double = savingsEntries.reduce(0) {
            $0 + convert($1.effectiveMonthlyAmount, from: $1.currencyOverride ?? currency, to: currency)
        }
        let monthlyFlow = monthlyIncome - monthlyExpenses - monthlySavings

        // Build PDF
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 595, height: 842)
        )
        let fname = "financehelper-report-\(isoDate()).pdf"
        let url   = FileManager.default.temporaryDirectory.appendingPathComponent(fname)

        try? renderer.writePDF(to: url) { ctx in
            let cv = PDFCanvas(ctx)

            // ── PAGE 1 ────────────────────────────────────────────────
            ctx.beginPage()
            cv.y = 0

            // Header band
            cv.fillRect(CGRect(x: 0, y: 0, width: cv.pageW, height: 88), color: PDFCanvas.accent)
            cv.y = 16
            cv.write("Finance Helper",
                     font: .systemFont(ofSize: 22, weight: .bold), color: .white, spacing: 6)
            cv.write("Finanzbericht · \(formattedDate())",
                     font: .systemFont(ofSize: 11), color: UIColor(white: 1, alpha: 0.72), spacing: 0)
            cv.y = 100

            // Net worth banner
            let nwColor = tintFor(netWorth)
            let nwRect  = CGRect(x: cv.margin, y: cv.y, width: cv.contentW, height: 58)
            cv.fillRect(nwRect, color: nwColor.withAlphaComponent(0.08), radius: 10)
            cv.strokeRect(nwRect, color: nwColor.withAlphaComponent(0.40), lw: 1, radius: 10)
            cv.y += 10
            cv.render("Nettovermögen", at: CGPoint(x: cv.margin + 16, y: cv.y),
                      font: .systemFont(ofSize: 10, weight: .medium), color: PDFCanvas.gray6,
                      maxW: cv.contentW)
            cv.y += 14
            cv.render(money(netWorth), at: CGPoint(x: cv.margin + 16, y: cv.y),
                      font: .systemFont(ofSize: 22, weight: .bold), color: nwColor,
                      maxW: cv.contentW)
            cv.y = 168  // 100 + 58 + 10

            // Summary row: Vermögen | Schulden | Flow
            let colW = cv.contentW / 3
            cv.fillRect(CGRect(x: cv.margin, y: cv.y, width: cv.contentW, height: 54),
                        color: PDFCanvas.gray95, radius: 8)
            let summaryItems: [(String, String, UIColor)] = [
                ("Vermögen",    money(totalAssets), PDFCanvas.green),
                ("Schulden",    money(totalLiab),   PDFCanvas.red),
                ("Monatl. Flow",money(monthlyFlow),  tintFor(monthlyFlow)),
            ]
            for (i, item) in summaryItems.enumerated() {
                let xOff = cv.margin + CGFloat(i) * colW
                cv.render(item.0, at: CGPoint(x: xOff + 6, y: cv.y + 9),
                          font: .systemFont(ofSize: 9), color: PDFCanvas.gray6,
                          maxW: colW - 12, align: .center)
                cv.render(item.1, at: CGPoint(x: xOff + 6, y: cv.y + 26),
                          font: .systemFont(ofSize: 12, weight: .bold), color: item.2,
                          maxW: colW - 12, align: .center)
                if i < 2 {
                    PDFCanvas.gray6.withAlphaComponent(0.2).setStroke()
                    let vl = UIBezierPath()
                    vl.move(to: CGPoint(x: xOff + colW, y: cv.y + 10))
                    vl.addLine(to: CGPoint(x: xOff + colW, y: cv.y + 44))
                    vl.lineWidth = 0.5; vl.stroke()
                }
            }
            cv.y += 54 + 18

            // ── ACCOUNTS ─────────────────────────────────────────────
            cv.checkBreak(needed: 50)
            cv.write("Konten", font: .systemFont(ofSize: 14, weight: .bold), spacing: 14)

            func drawAccountRow(_ acc: Account, idx: Int) {
                let rh: CGFloat = 24
                cv.checkBreak(needed: rh + 4)
                if idx % 2 == 0 {
                    cv.fillRect(CGRect(x: cv.margin, y: cv.y, width: cv.contentW, height: rh),
                                color: PDFCanvas.gray95)
                }
                let ry = cv.y
                cv.render(acc.name, at: CGPoint(x: cv.margin + 8, y: ry + 5),
                          font: .systemFont(ofSize: 10, weight: .medium),
                          color: PDFCanvas.black, maxW: cv.contentW * 0.40)
                cv.render(acc.type.localizedName,
                          at: CGPoint(x: cv.margin + cv.contentW * 0.42, y: ry + 5),
                          font: .systemFont(ofSize: 9), color: PDFCanvas.gray6,
                          maxW: cv.contentW * 0.26)
                let converted = convert(acc.balance, from: acc.currency, to: currency)
                let balStr = acc.currency == currency
                    ? money(acc.balance)
                    : "\(money(converted))  (\(acc.currency))"
                cv.render(balStr, at: CGPoint(x: cv.margin + cv.contentW * 0.68, y: ry + 5),
                          font: .systemFont(ofSize: 10, weight: .semibold),
                          color: acc.type.isLiability ? PDFCanvas.red : PDFCanvas.black,
                          maxW: cv.contentW * 0.32, align: .right)
                cv.y = ry + rh
            }

            if !assets.isEmpty {
                cv.checkBreak(needed: 30)
                cv.write("Vermögenswerte", font: .systemFont(ofSize: 10, weight: .semibold),
                         color: PDFCanvas.gray6, spacing: 10)
                for (i, acc) in assets.enumerated() { drawAccountRow(acc, idx: i) }
                cv.advance(10)
            }
            if !liabilities.isEmpty {
                cv.checkBreak(needed: 30)
                cv.write("Schulden", font: .systemFont(ofSize: 10, weight: .semibold),
                         color: PDFCanvas.gray6, spacing: 10)
                for (i, acc) in liabilities.enumerated() { drawAccountRow(acc, idx: i) }
                cv.advance(10)
            }

            // ── BUDGET CASHFLOW ───────────────────────────────────────
            cv.checkBreak(needed: 110)
            cv.advance(6)
            cv.write("Monatlicher Cashflow", font: .systemFont(ofSize: 14, weight: .bold), spacing: 14)

            // Summary band
            let flowSummaryItems: [(String, Double, UIColor)] = [
                ("Einkommen", monthlyIncome,   PDFCanvas.green),
                ("Ausgaben",  monthlyExpenses, PDFCanvas.red),
                ("Sparen",    monthlySavings,  PDFCanvas.accent),
            ]
            cv.checkBreak(needed: 54)
            cv.fillRect(CGRect(x: cv.margin, y: cv.y, width: cv.contentW, height: 54),
                        color: PDFCanvas.gray95, radius: 8)
            let flowColW = cv.contentW / CGFloat(flowSummaryItems.count)
            for (i, item) in flowSummaryItems.enumerated() {
                let xOff = cv.margin + CGFloat(i) * flowColW
                cv.render(item.0, at: CGPoint(x: xOff + 6, y: cv.y + 9),
                          font: .systemFont(ofSize: 9), color: PDFCanvas.gray6,
                          maxW: flowColW - 12, align: .center)
                cv.render(money(item.1), at: CGPoint(x: xOff + 6, y: cv.y + 26),
                          font: .systemFont(ofSize: 12, weight: .bold), color: item.2,
                          maxW: flowColW - 12, align: .center)
                if i < flowSummaryItems.count - 1 {
                    PDFCanvas.gray6.withAlphaComponent(0.2).setStroke()
                    let vl = UIBezierPath()
                    vl.move(to: CGPoint(x: xOff + flowColW, y: cv.y + 10))
                    vl.addLine(to: CGPoint(x: xOff + flowColW, y: cv.y + 44))
                    vl.lineWidth = 0.5; vl.stroke()
                }
            }
            cv.y += 54 + 6

            // Net flow row
            cv.checkBreak(needed: 28)
            cv.fillRect(CGRect(x: cv.margin, y: cv.y, width: cv.contentW, height: 28),
                        color: tintFor(monthlyFlow).withAlphaComponent(0.07), radius: 6)
            let netY = cv.y
            cv.render("Netto / Monat", at: CGPoint(x: cv.margin + 8, y: netY + 6),
                      font: .systemFont(ofSize: 11, weight: .bold), color: PDFCanvas.black,
                      maxW: cv.contentW * 0.6)
            cv.render(money(monthlyFlow), at: CGPoint(x: cv.margin, y: netY + 6),
                      font: .systemFont(ofSize: 11, weight: .bold), color: tintFor(monthlyFlow),
                      maxW: cv.contentW - 8, align: .right)
            cv.y = netY + 28 + 16

            // ── BUDGET ENTRIES DETAIL ─────────────────────────────────

            func drawBudgetSubsection(title: String, entries: [BudgetEntry], amountColor: UIColor) {
                guard !entries.isEmpty else { return }
                cv.checkBreak(needed: 40)
                cv.write(title, font: .systemFont(ofSize: 10, weight: .semibold),
                         color: PDFCanvas.gray6, spacing: 8)
                for (i, entry) in entries.enumerated() {
                    let rh: CGFloat = 22
                    cv.checkBreak(needed: rh + 2)
                    if i % 2 == 0 {
                        cv.fillRect(CGRect(x: cv.margin, y: cv.y, width: cv.contentW, height: rh),
                                    color: PDFCanvas.gray95)
                    }
                    let ry = cv.y
                    // Colored dot — use user category color if available, else the section color
                    let dotColor: UIColor
                    if let uc = entry.userCategory {
                        dotColor = CategoryColor(rawValue: uc.colorNameRaw)?.uiColor ?? amountColor
                    } else {
                        dotColor = amountColor
                    }
                    cv.fillRect(CGRect(x: cv.margin + 6, y: ry + 7, width: 8, height: 8),
                                color: dotColor, radius: 4)
                    // Name
                    cv.render(entry.displayName,
                              at: CGPoint(x: cv.margin + 20, y: ry + 4),
                              font: .systemFont(ofSize: 9.5, weight: .medium),
                              color: PDFCanvas.black, maxW: cv.contentW * 0.40)
                    // Recurrence
                    cv.render(entry.recurrenceDisplayLabel,
                              at: CGPoint(x: cv.margin + cv.contentW * 0.42, y: ry + 4),
                              font: .systemFont(ofSize: 9), color: PDFCanvas.gray6,
                              maxW: cv.contentW * 0.22)
                    // Monthly effective amount
                    let entryCurrency = entry.currencyOverride ?? currency
                    let monthlyAmt = convert(entry.effectiveMonthlyAmount, from: entryCurrency, to: currency)
                    cv.render(money(monthlyAmt),
                              at: CGPoint(x: cv.margin, y: ry + 4),
                              font: .systemFont(ofSize: 9.5, weight: .semibold),
                              color: amountColor, maxW: cv.contentW - 8, align: .right)
                    cv.y = ry + rh
                }
                cv.advance(10)
            }

            cv.checkBreak(needed: 30)
            cv.write("Budgeteinträge", font: .systemFont(ofSize: 14, weight: .bold), spacing: 14)
            drawBudgetSubsection(title: "Einkommen", entries: incomeEntries, amountColor: PDFCanvas.green)
            drawBudgetSubsection(title: "Ausgaben", entries: expenseEntries, amountColor: PDFCanvas.red)
            drawBudgetSubsection(title: "Sparen & Investieren", entries: savingsEntries, amountColor: PDFCanvas.accent)
            if !transferEntries.isEmpty {
                drawBudgetSubsection(title: "Umbuchungen", entries: transferEntries, amountColor: PDFCanvas.gray6)
            }

            // ── GOALS ────────────────────────────────────────────────
            let activeGoals = goals.filter(\.isActive).sorted { $0.priority < $1.priority }
            if !activeGoals.isEmpty {
                cv.checkBreak(needed: 50)
                cv.advance(4)
                cv.write("Finanzielle Ziele", font: .systemFont(ofSize: 14, weight: .bold), spacing: 14)
                for (i, goal) in activeGoals.enumerated() {
                    let rh: CGFloat = 24
                    cv.checkBreak(needed: rh + 4)
                    if i % 2 == 0 {
                        cv.fillRect(CGRect(x: cv.margin, y: cv.y, width: cv.contentW, height: rh),
                                    color: PDFCanvas.gray95)
                    }
                    let ry = cv.y
                    cv.render(goal.name, at: CGPoint(x: cv.margin + 8, y: ry + 5),
                              font: .systemFont(ofSize: 10, weight: .medium),
                              color: PDFCanvas.black, maxW: cv.contentW * 0.55)
                    cv.render(goal.category.localizedName,
                              at: CGPoint(x: cv.margin + cv.contentW * 0.57, y: ry + 5),
                              font: .systemFont(ofSize: 9), color: PDFCanvas.gray6,
                              maxW: cv.contentW * 0.18)
                    cv.render(money(goal.targetAmount),
                              at: CGPoint(x: cv.margin, y: ry + 5),
                              font: .systemFont(ofSize: 10, weight: .semibold),
                              color: PDFCanvas.accent, maxW: cv.contentW - 8, align: .right)
                    cv.y = ry + rh
                }
            }

            // ── USER CATEGORIES ───────────────────────────────────────
            if !userCategories.isEmpty {
                cv.checkBreak(needed: 50)
                cv.advance(8)
                cv.write("Eigene Kategorien", font: .systemFont(ofSize: 14, weight: .bold), spacing: 14)
                for (i, cat) in userCategories.enumerated() {
                    let rh: CGFloat = 22
                    cv.checkBreak(needed: rh + 2)
                    if i % 2 == 0 {
                        cv.fillRect(CGRect(x: cv.margin, y: cv.y, width: cv.contentW, height: rh),
                                    color: PDFCanvas.gray95)
                    }
                    let ry = cv.y
                    // Colored dot
                    let catColor = CategoryColor(rawValue: cat.colorNameRaw)?.uiColor ?? .systemBlue
                    cv.fillRect(CGRect(x: cv.margin + 6, y: ry + 7, width: 8, height: 8),
                                color: catColor, radius: 4)
                    cv.render(cat.name,
                              at: CGPoint(x: cv.margin + 20, y: ry + 4),
                              font: .systemFont(ofSize: 9.5, weight: .medium),
                              color: PDFCanvas.black, maxW: cv.contentW * 0.40)
                    cv.render(cat.group.localizedName,
                              at: CGPoint(x: cv.margin + cv.contentW * 0.42, y: ry + 4),
                              font: .systemFont(ofSize: 9), color: PDFCanvas.gray6,
                              maxW: cv.contentW * 0.26)
                    var flags: [String] = []
                    if cat.isIncome     { flags.append("Einkommen") }
                    if cat.isSavings    { flags.append("Sparen") }
                    if cat.isInvestment { flags.append("Investieren") }
                    if flags.isEmpty    { flags.append("Ausgabe") }
                    cv.render(flags.joined(separator: " · "),
                              at: CGPoint(x: cv.margin, y: ry + 4),
                              font: .systemFont(ofSize: 9), color: PDFCanvas.gray6,
                              maxW: cv.contentW - 8, align: .right)
                    cv.y = ry + rh
                }
            }

            // ── FINANCIAL HEALTH ──────────────────────────────────────
            let liquidBalance = assets.filter { $0.type.isLiquid }
                .reduce(0) { $0 + convert(max(0, $1.balance), from: $1.currency, to: currency) }
            let emergencyMonths = monthlyExpenses > 0 ? liquidBalance / monthlyExpenses : 6.0
            let debtRatio = (totalAssets + totalLiab) > 0 ? totalLiab / (totalAssets + totalLiab) : 0.0
            let investRatio = monthlyIncome > 0 ? monthlySavings / monthlyIncome : 0.0
            let liabIDs = Set(liabilities.map { $0.id })
            let creditMonthly = active.filter { entry in entry.account.map { liabIDs.contains($0.id) } ?? false }
                .reduce(0.0) { $0 + convert($1.effectiveMonthlyAmount, from: $1.currencyOverride ?? currency, to: currency) }
            let creditBurden = monthlyIncome > 0 ? creditMonthly / monthlyIncome : 0.0

            let efScore      = min(100, emergencyMonths / 3.0 * 100)
            let debtScore    = max(0, (1.0 - debtRatio) * 100)
            let invScore     = min(100, investRatio / 0.20 * 100)
            let creditScore  = max(0, (1.0 - creditBurden / 0.30) * 100)
            let healthScore  = (30 * efScore + 25 * debtScore + 25 * invScore + 20 * creditScore) / 100.0

            cv.checkBreak(needed: 50)
            cv.advance(8)
            cv.write("Finance Score", font: .systemFont(ofSize: 14, weight: .bold), spacing: 14)

            let hsColor: UIColor = healthScore >= 80 ? PDFCanvas.green
                                 : healthScore >= 60 ? UIColor(red: 0.20, green: 0.65, blue: 0.30, alpha: 1)
                                 : healthScore >= 40 ? UIColor(red: 0.90, green: 0.55, blue: 0.10, alpha: 1)
                                 : PDFCanvas.red
            let hsBadgeRect = CGRect(x: cv.margin, y: cv.y, width: cv.contentW, height: 44)
            cv.fillRect(hsBadgeRect, color: hsColor.withAlphaComponent(0.09), radius: 8)
            cv.strokeRect(hsBadgeRect, color: hsColor.withAlphaComponent(0.35), lw: 1, radius: 8)
            let scoreLabel = healthScore >= 80 ? "Ausgezeichnet" : healthScore >= 60 ? "Gut"
                           : healthScore >= 40 ? "Mittel" : "Kritisch"
            cv.render(scoreLabel, at: CGPoint(x: cv.margin + 14, y: cv.y + 14),
                      font: .systemFont(ofSize: 10, weight: .medium), color: hsColor, maxW: cv.contentW * 0.5)
            cv.render(String(format: "%.0f / 100", healthScore),
                      at: CGPoint(x: cv.margin, y: cv.y + 12),
                      font: .systemFont(ofSize: 16, weight: .bold), color: hsColor,
                      maxW: cv.contentW - 14, align: .right)
            cv.y += 44 + 10

            let healthCriteria: [(String, Double, Double, String)] = [
                ("Notgroschen",       efScore,     30, String(format: "%.1f Monate", emergencyMonths)),
                ("Schuldenquote",     debtScore,   25, String(format: "%.0f%%", debtRatio * 100)),
                ("Investitionsquote", invScore,    25, String(format: "%.0f%%", investRatio * 100)),
                ("Kreditbelastung",   creditScore, 20, String(format: "%.0f%%", creditBurden * 100)),
            ]
            for (name, score, weight, detail) in healthCriteria {
                cv.checkBreak(needed: 32)
                cv.render(name, at: CGPoint(x: cv.margin, y: cv.y),
                          font: .systemFont(ofSize: 9.5, weight: .medium), color: PDFCanvas.black,
                          maxW: cv.contentW * 0.38)
                cv.render("Gewicht \(Int(weight))%",
                          at: CGPoint(x: cv.margin + cv.contentW * 0.38, y: cv.y),
                          font: .systemFont(ofSize: 9), color: PDFCanvas.gray6, maxW: cv.contentW * 0.22)
                cv.render(detail, at: CGPoint(x: cv.margin, y: cv.y),
                          font: .systemFont(ofSize: 9), color: PDFCanvas.gray6,
                          maxW: cv.contentW - 8, align: .right)
                cv.y += 13
                let barH: CGFloat = 8
                cv.fillRect(CGRect(x: cv.margin, y: cv.y, width: cv.contentW, height: barH),
                            color: UIColor(white: 0.88, alpha: 1), radius: 3)
                let fillW = cv.contentW * CGFloat(min(score, 100)) / 100.0
                let barFill: UIColor = score >= 75 ? PDFCanvas.green
                                     : score >= 50 ? UIColor(red: 0.90, green: 0.55, blue: 0.10, alpha: 1)
                                     : PDFCanvas.red
                if fillW > 0 {
                    cv.fillRect(CGRect(x: cv.margin, y: cv.y, width: fillW, height: barH), color: barFill, radius: 3)
                }
                cv.y += barH + 10
            }

            // ── ASSET ALLOCATION ───────────────────────────────────────
            let liquidAmt = assets.filter { $0.type.isLiquid }
                .reduce(0) { $0 + convert(max(0, $1.balance), from: $1.currency, to: currency) }
            let investAmt = assets.filter { $0.type.isInvestment && $0.type != .altersvorsorge }
                .reduce(0) { $0 + convert(max(0, $1.balance), from: $1.currency, to: currency) }
            let pensionAmt = assets.filter { $0.type == .altersvorsorge }
                .reduce(0) { $0 + convert(max(0, $1.balance), from: $1.currency, to: currency) }
            let otherAmt = max(0, totalAssets - liquidAmt - investAmt - pensionAmt)

            let buckets: [(String, Double, UIColor)] = [
                ("Liquide Mittel",       liquidAmt,  PDFCanvas.accent),
                ("Investitionen & Depot",investAmt,  PDFCanvas.green),
                ("Altersvorsorge",       pensionAmt, UIColor(red: 0.55, green: 0.25, blue: 0.85, alpha: 1)),
                ("Sonstige Vermögen",    otherAmt,   PDFCanvas.gray6),
            ].filter { $0.1 > 0 }

            if !buckets.isEmpty && totalAssets > 0 {
                cv.checkBreak(needed: 50)
                cv.advance(8)
                cv.write("Vermögensallokation", font: .systemFont(ofSize: 14, weight: .bold), spacing: 12)
                cv.checkBreak(needed: 26 + CGFloat(buckets.count) * 16 + 10)
                // Stacked bar
                var xCursor = cv.margin
                for (_, value, color) in buckets {
                    let w = cv.contentW * CGFloat(value / totalAssets)
                    if w > 0 { cv.fillRect(CGRect(x: xCursor, y: cv.y, width: w, height: 18), color: color) }
                    xCursor += w
                }
                cv.y += 18 + 8
                // Legend
                for (label, value, color) in buckets {
                    cv.checkBreak(needed: 16)
                    cv.fillRect(CGRect(x: cv.margin, y: cv.y + 3, width: 10, height: 10), color: color, radius: 2)
                    let pct = String(format: "%.1f%%", value / totalAssets * 100)
                    cv.render("\(label)  \(pct)", at: CGPoint(x: cv.margin + 14, y: cv.y),
                              font: .systemFont(ofSize: 9.5), color: PDFCanvas.black,
                              maxW: cv.contentW * 0.60)
                    cv.render(money(value), at: CGPoint(x: cv.margin, y: cv.y),
                              font: .systemFont(ofSize: 9.5, weight: .semibold), color: PDFCanvas.gray6,
                              maxW: cv.contentW - 8, align: .right)
                    cv.y += 16
                }
                cv.advance(6)
            }

            // ── TRANSACTION SUMMARY ────────────────────────────────────
            if !transactions.isEmpty {
                let txExpenses = transactions.filter { $0.rawAmount < 0 }
                let txIncome   = transactions.filter { $0.rawAmount > 0 }
                let txTotalExp = txExpenses.reduce(0) {
                    $0 + convert(abs($1.rawAmount), from: $1.currencyCode, to: currency)
                }
                let txTotalInc = txIncome.reduce(0) {
                    $0 + convert($1.rawAmount, from: $1.currencyCode, to: currency)
                }

                cv.checkBreak(needed: 50)
                cv.advance(8)
                cv.write("Transaktionsübersicht", font: .systemFont(ofSize: 14, weight: .bold), spacing: 10)

                if let earliest = transactions.map(\.date).min(),
                   let latest   = transactions.map(\.date).max() {
                    let df = DateFormatter()
                    df.dateStyle = .medium; df.timeStyle = .none
                    cv.write("\(df.string(from: earliest)) – \(df.string(from: latest))",
                             font: .systemFont(ofSize: 9), color: PDFCanvas.gray6, spacing: 10)
                }

                cv.checkBreak(needed: 54)
                cv.fillRect(CGRect(x: cv.margin, y: cv.y, width: cv.contentW, height: 54),
                            color: PDFCanvas.gray95, radius: 8)
                let txCols: [(String, String, UIColor)] = [
                    ("Einnahmen",    money(txTotalInc),         PDFCanvas.green),
                    ("Ausgaben",     money(txTotalExp),         PDFCanvas.red),
                    ("Transaktionen","\(transactions.count)",   PDFCanvas.accent),
                ]
                let txColW = cv.contentW / 3
                for (i, item) in txCols.enumerated() {
                    let xOff = cv.margin + CGFloat(i) * txColW
                    cv.render(item.0, at: CGPoint(x: xOff + 6, y: cv.y + 9),
                              font: .systemFont(ofSize: 9), color: PDFCanvas.gray6,
                              maxW: txColW - 12, align: .center)
                    cv.render(item.1, at: CGPoint(x: xOff + 6, y: cv.y + 26),
                              font: .systemFont(ofSize: 11, weight: .bold), color: item.2,
                              maxW: txColW - 12, align: .center)
                    if i < 2 {
                        PDFCanvas.gray6.withAlphaComponent(0.2).setStroke()
                        let vl = UIBezierPath()
                        vl.move(to: CGPoint(x: xOff + txColW, y: cv.y + 10))
                        vl.addLine(to: CGPoint(x: xOff + txColW, y: cv.y + 44))
                        vl.lineWidth = 0.5; vl.stroke()
                    }
                }
                cv.y += 54 + 14

                let catTotals = Dictionary(grouping: txExpenses, by: { $0.categoryRaw })
                    .mapValues { txs in txs.reduce(0) {
                        $0 + convert(abs($1.rawAmount), from: $1.currencyCode, to: currency)
                    }}
                    .sorted { $0.value > $1.value }
                    .prefix(5)

                if !catTotals.isEmpty {
                    cv.checkBreak(needed: 30)
                    cv.write("Top Ausgabenkategorien", font: .systemFont(ofSize: 10, weight: .semibold),
                             color: PDFCanvas.gray6, spacing: 8)
                    let maxCatVal = catTotals.first?.value ?? 1
                    for (i, kv) in catTotals.enumerated() {
                        let rh: CGFloat = 22
                        cv.checkBreak(needed: rh + 2)
                        if i % 2 == 0 {
                            cv.fillRect(CGRect(x: cv.margin, y: cv.y, width: cv.contentW, height: rh),
                                        color: PDFCanvas.gray95)
                        }
                        let ry = cv.y
                        let label = TransactionCategory(rawValue: kv.key)?.rawValue ?? kv.key
                        cv.render(label, at: CGPoint(x: cv.margin + 8, y: ry + 5),
                                  font: .systemFont(ofSize: 9.5, weight: .medium), color: PDFCanvas.black,
                                  maxW: cv.contentW * 0.50)
                        let barMaxW = cv.contentW * 0.28
                        let barFillW = barMaxW * CGFloat(kv.value / maxCatVal)
                        if barFillW > 0 {
                            cv.fillRect(CGRect(x: cv.margin + cv.contentW * 0.38, y: ry + 8,
                                               width: barFillW, height: 6),
                                        color: PDFCanvas.red.withAlphaComponent(0.5), radius: 2)
                        }
                        cv.render(money(kv.value), at: CGPoint(x: cv.margin, y: ry + 5),
                                  font: .systemFont(ofSize: 9.5, weight: .semibold), color: PDFCanvas.red,
                                  maxW: cv.contentW - 8, align: .right)
                        cv.y = ry + rh
                    }
                }
            }

            // Footer note
            cv.advance(16)
            cv.checkBreak(needed: 24)
            cv.hRule(color: UIColor(white: 0.8, alpha: 0.4))
            cv.advance(6)
            cv.render(
                "Finance Helper · \(formattedDate()) · Wechselkurse basieren auf Richtwerten.",
                at: CGPoint(x: cv.margin, y: cv.y),
                font: .systemFont(ofSize: 8.5), color: PDFCanvas.gray6,
                maxW: cv.contentW, align: .center
            )
        }

        try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        return url
    }

    // MARK: - Helpers

    private static func isoDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func formattedDate() -> String {
        DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)
    }

}

// MARK: - CategoryColor UIKit extension

private extension CategoryColor {
    var uiColor: UIColor {
        switch self {
        case .blue:   return .systemBlue
        case .green:  return .systemGreen
        case .red:    return .systemRed
        case .orange: return .systemOrange
        case .purple: return .systemPurple
        case .pink:   return .systemPink
        case .teal:   return .systemTeal
        case .indigo: return .systemIndigo
        case .mint:   return UIColor(red: 0, green: 0.78, blue: 0.75, alpha: 1)
        case .yellow: return .systemYellow
        case .brown:  return .systemBrown
        case .gray:   return .systemGray
        }
    }
}
