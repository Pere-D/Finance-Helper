import SwiftUI
import SwiftData
import Charts

// MARK: - Period

private enum AnalysePeriod: String, CaseIterable {
    case month1   = "1 Monat"
    case month3   = "3 Monate"
    case month6   = "6 Monate"
    case year1    = "1 Jahr"
    case thisYear = "Dieses Jahr"
    case lastYear = "Letztes Jahr"
    case all      = "Alle"

    private static func firstOfMonth(byAdding component: Calendar.Component, value: Int) -> Date? {
        let cal = Calendar.current
        guard let offset = cal.date(byAdding: component, value: value, to: .now) else { return nil }
        return cal.date(from: cal.dateComponents([.year, .month], from: offset))
    }

    var cutoffDate: Date? {
        let cal = Calendar.current
        switch self {
        case .month1:   return Self.firstOfMonth(byAdding: .month, value: -1)
        case .month3:   return Self.firstOfMonth(byAdding: .month, value: -3)
        case .month6:   return Self.firstOfMonth(byAdding: .month, value: -6)
        case .year1:    return Self.firstOfMonth(byAdding: .month, value: -12)
        case .thisYear: return cal.date(from: cal.dateComponents([.year], from: .now))
        case .lastYear:
            guard let d = cal.date(byAdding: .year, value: -1, to: .now) else { return nil }
            return cal.date(from: cal.dateComponents([.year], from: d))
        case .all:      return nil
        }
    }

    var cutoffEndDate: Date? {
        guard self == .lastYear else { return nil }
        return Calendar.current.date(from: Calendar.current.dateComponents([.year], from: .now))
    }

    var localizedName: String { NSLocalizedString(rawValue, comment: "") }
}

private enum AnalyseMainTab: String, CaseIterable {
    case overview      = "Übersicht"
    case transactions  = "Transaktionen"
}

private enum ChartGranularity { case monthly, quarterly, yearComparison, yearly }

private enum TxTypeFilter: String, Identifiable {
    case income, expense
    var id: String { rawValue }
    var label: String { self == .income ? NSLocalizedString("Einnahmen", comment: "") : NSLocalizedString("Ausgaben", comment: "") }
    var icon: String { self == .income ? "arrow.down.circle.fill" : "arrow.up.circle.fill" }
    var color: Color { self == .income ? .green : .red }
}

private enum TxSortOrder { case dateDesc, dateAsc, amountDesc, amountAsc }

private enum TrendDirection: Sendable, Equatable { case up, down, neutral }

private struct TrendInsight: Identifiable, Sendable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let valueColor: Color
    let direction: TrendDirection
    let description: String
}

private struct TxData: Sendable {
    let date: Date
    let amount: Double      // abs(rawAmount)
    let isExpense: Bool     // rawAmount < 0
    let isTransfer: Bool    // category == .transfer
    let merchantName: String
}

struct AnalyseView: View {
    @AppStorage("active_profile_id") private var activeProfileID: String = ""
    @AppStorage("default_currency")  private var defaultCurrency: String = "CHF"
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ImportedTransaction.date, order: .reverse)
    private var allTransactions: [ImportedTransaction]

    @Query private var allCustomCategories: [UserTransactionCategory]

    // Period / date range
    @State private var selectedPeriod: AnalysePeriod = .month3
    @State private var showCustomRange = false
    @State private var customFrom: Date = Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now
    @State private var customTo:   Date = .now

    // Main tab
    @State private var mainTab: AnalyseMainTab = .overview

    // Transactions tab
    @State private var txCategoryFilter: TransactionCategory? = nil
    @State private var txCustomCategoryFilter: UserTransactionCategory? = nil
    @State private var txTypeFilter: TxTypeFilter? = nil
    @State private var pieSelectedValue: Double? = nil
    @State private var showCategoryInfo = false
    @State private var txSearchText = ""
    @State private var txSearchApplied = ""   // debounced — only this drives the filter
    @State private var txSortOrder: TxSortOrder = .dateDesc
    @State private var isBulkEditing = false
    @State private var bulkSelectedIDs: Set<UUID> = []
    @State private var showingBulkCategoryPicker = false
    @State private var editingTx: ImportedTransaction? = nil

    // Rules sheet
    @State private var showingRulesSheet = false

    // Account filter (multi-select)
    @State private var selectedAccountIDs: Set<String> = []

    // Navigation / sheets
    @State private var pendingTransactions: [BankTransaction] = []
    @State private var pendingBatch:  ImportBatch? = nil
    @State private var pendingBank:   BankFormat   = .zugerKantonalbank
    @State private var pendingTitle:  String?       = nil
    @State private var showingDetail        = false
    @State private var showingImport        = false
    @State private var showingAccounts      = false
    @State private var showingSettings      = false
    @State private var showingBatches       = false
    @State private var showingAddManualTx   = false
    @State private var batchToDelete: ImportBatch? = nil
    @State private var isDeletingBatch      = false
    @State private var deletionProgress: Double = 0
    @State private var deletionTotal: Int   = 0
    @State private var showingFAB           = false
    @State private var showingPeriodFilter  = false
    @State private var showingAccountFilter = false
    @State private var trendInsights: [TrendInsight]? = nil
    @State private var cachedFilteredTxs: [ImportedTransaction] = []
    @State private var showBalanceLine = true
    @State private var selectedBarDate: Date? = nil
    @AppStorage("bg_theme") private var rawTheme = BackgroundTheme.emerald.rawValue
    @Environment(PurchaseManager.self) private var purchases
    @State private var showingPaywall = false

    // MARK: - Computed

    private var profileTransactions: [ImportedTransaction] {
        allTransactions.filter { $0.profileID == activeProfileID }
    }

    private func attemptImport() {
        if !purchases.isPremium && profileTransactions.count >= 100 {
            showingPaywall = true
        } else {
            showingImport = true
        }
    }

    private var filteredTransactions: [ImportedTransaction] { cachedFilteredTxs }

    private var txFilteredList: [ImportedTransaction] {
        var list = filteredTransactions
        if let cat = txCategoryFilter {
            list = list.filter { $0.category == cat && $0.customCategoryID == nil }
        } else if let custom = txCustomCategoryFilter {
            list = list.filter { $0.customCategoryID == custom.id.uuidString }
        }
        if let type = txTypeFilter {
            list = list.filter { type == .income ? $0.isIncome : $0.isExpense }
        }
        if !txSearchApplied.isEmpty {
            let q = txSearchApplied.lowercased()
            list = list.filter {
                $0.merchantName.lowercased().contains(q) ||
                $0.transactionDescription.lowercased().contains(q) ||
                $0.userNote.lowercased().contains(q)
            }
        }
        switch txSortOrder {
        case .dateDesc:   break  // default from query
        case .dateAsc:    list.sort { $0.date < $1.date }
        case .amountDesc: list.sort { $0.amount > $1.amount }
        case .amountAsc:  list.sort { $0.amount < $1.amount }
        }
        return list
    }

    // Single-pass category counts — avoids 18× re-scans in the filter chips
    private var categoryCount: [TransactionCategory: Int] {
        var counts = [TransactionCategory: Int]()
        for tx in filteredTransactions where tx.customCategoryID == nil {
            counts[tx.category, default: 0] += 1
        }
        return counts
    }

    // Custom category counts keyed by UUID string
    private var customCategoryCount: [String: Int] {
        var counts = [String: Int]()
        for tx in filteredTransactions {
            if let cid = tx.customCategoryID { counts[cid, default: 0] += 1 }
        }
        return counts
    }

    private var profileCustomCategories: [UserTransactionCategory] {
        allCustomCategories.filter { $0.profileID == activeProfileID }
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.locale = .current; return f
    }()

    private var periodFilterLabel: String {
        if showCustomRange {
            return "\(Self.shortDateFormatter.string(from: customFrom)) – \(Self.shortDateFormatter.string(from: customTo))"
        }
        return selectedPeriod.localizedName
    }

    private var accountGroups: [AccountGroup] {
        let grouped = Dictionary(grouping: profileTransactions) { tx in
            tx.account?.id.uuidString ?? "__none__"
        }
        return grouped.map { _, txs in
            let account = txs.first?.account
            let batchGrouped = Dictionary(grouping: txs) { batchKey(for: $0) }
            let batches = batchGrouped.map { batchID, batchTxs in
                ImportBatch(
                    batchID:    batchID,
                    transactions: batchTxs.sorted { $0.date > $1.date },
                    bank:       BankFormat(rawValue: batchTxs.first?.bankFormatRaw ?? "") ?? .zugerKantonalbank,
                    importedAt: batchTxs.map(\.importedAt).max() ?? .distantPast
                )
            }.sorted { $0.importedAt > $1.importedAt }

            return AccountGroup(
                accountID:   account?.id.uuidString ?? "__none__",
                accountName: account?.name ?? NSLocalizedString("Nicht zugeordnet", comment: ""),
                icon:        account?.effectiveSystemImage ?? "questionmark.circle",
                color:       account?.effectiveColor ?? .gray,
                batches:     batches
            )
        }
        .sorted { $0.accountName < $1.accountName }
    }

    private struct CategoryPieItem: Identifiable {
        let id: String
        let name: String
        let systemImage: String
        let color: Color
        let total: Double
        let builtIn: TransactionCategory?
        let customCategory: UserTransactionCategory?
    }


    private var expensesByCategory: [CategoryPieItem] {
        let expenses = filteredTransactions.filter { $0.isExpense && $0.category != .transfer }
        var items: [CategoryPieItem] = []

        // Custom categories (transactions with customCategoryID)
        for customCat in profileCustomCategories {
            let txs = expenses.filter { $0.customCategoryID == customCat.id.uuidString }
            guard !txs.isEmpty else { continue }
            items.append(CategoryPieItem(
                id: customCat.id.uuidString,
                name: customCat.name,
                systemImage: customCat.systemImage,
                color: customCat.color,
                total: txs.reduce(0) { $0 + $1.amount },
                builtIn: nil,
                customCategory: customCat
            ))
        }

        // Built-in categories (transactions without customCategoryID)
        let grouped = Dictionary(grouping: expenses.filter { $0.customCategoryID == nil }) { $0.category }
        for (cat, txs) in grouped {
            items.append(CategoryPieItem(
                id: cat.rawValue,
                name: cat.localizedName,
                systemImage: cat.systemImage,
                color: cat.color,
                total: txs.reduce(0) { $0 + $1.amount },
                builtIn: cat,
                customCategory: nil
            ))
        }

        return items.sorted { $0.total > $1.total }
    }

    // Spans > 24 months use monthly buckets to avoid rendering thousands of daily points
    private var balanceHistoryUsesMonthlyGranularity: Bool {
        let cal = Calendar.current
        if showCustomRange {
            let months = cal.dateComponents([.month], from: customFrom, to: customTo).month ?? 0
            return months > 24
        }
        if let cutoff = selectedPeriod.cutoffDate {
            let months = cal.dateComponents([.month], from: cutoff, to: Date()).month ?? 0
            return months > 24
        }
        // .all — measure actual transaction range
        let txDates = allTransactions.filter { $0.profileID == activeProfileID }.map(\.date)
        guard let oldest = txDates.min(), let newest = txDates.max() else { return false }
        let months = cal.dateComponents([.month], from: oldest, to: newest).month ?? 0
        return months > 24
    }

    // Reconstructs combined balance history for all selected accounts, back-calculated from account.balance
    private var balanceHistoryData: [(date: Date, balance: Double)] {
        let cal = Calendar.current
        let useMonthly = balanceHistoryUsesMonthlyGranularity

        var perAccountFlows: [String: [String: Double]] = [:]
        var acctCurrentBalance: [String: Double] = [:]

        for tx in allTransactions where tx.profileID == activeProfileID {
            guard let acct = tx.account else { continue }
            let acctID = acct.id.uuidString
            if acctCurrentBalance[acctID] == nil { acctCurrentBalance[acctID] = acct.balance }
            let comps = cal.dateComponents(useMonthly ? [.year, .month] : [.year, .month, .day], from: tx.date)
            let key = useMonthly
                ? "\(comps.year ?? 0)-\(String(format: "%02d", comps.month ?? 0))"
                : "\(comps.year ?? 0)-\(String(format: "%02d", comps.month ?? 0))-\(String(format: "%02d", comps.day ?? 0))"
            perAccountFlows[acctID, default: [:]][key, default: 0] += tx.rawAmount
        }

        let targetIDs: Set<String> = selectedAccountIDs.isEmpty ? Set(acctCurrentBalance.keys) : selectedAccountIDs
        guard !targetIDs.isEmpty else { return [] }

        var allKeys = Set<String>()
        for id in targetIDs { perAccountFlows[id]?.keys.forEach { allKeys.insert($0) } }
        guard !allKeys.isEmpty else { return [] }

        var accountBalances: [String: [String: Double]] = [:]
        for acctID in targetIDs {
            guard let currentBalance = acctCurrentBalance[acctID] else { continue }
            let flows = perAccountFlows[acctID] ?? [:]
            var running = currentBalance
            var balances: [String: Double] = [:]
            for key in allKeys.sorted().reversed() {
                balances[key] = running
                running -= flows[key] ?? 0
            }
            accountBalances[acctID] = balances
        }

        let cutoff: Date? = showCustomRange ? cal.startOfDay(for: customFrom) : selectedPeriod.cutoffDate
        let endCutoff: Date? = showCustomRange
            ? (cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: customTo)) ?? customTo)
            : selectedPeriod.cutoffEndDate

        var result: [(date: Date, balance: Double)] = []
        for key in allKeys.sorted() {
            let parts = key.split(separator: "-")
            let date: Date?
            if useMonthly {
                guard parts.count == 2,
                      let year = Int(parts[0]), let month = Int(parts[1]) else { continue }
                date = cal.date(from: DateComponents(year: year, month: month, day: 1))
            } else {
                guard parts.count == 3,
                      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { continue }
                date = cal.date(from: DateComponents(year: year, month: month, day: day))
            }
            guard let date else { continue }
            if let c = cutoff, date < c { continue }
            if let e = endCutoff, date >= e { continue }
            let combined = targetIDs.reduce(0.0) { $0 + (accountBalances[$1]?[key] ?? 0) }
            result.append((date: date, balance: combined))
        }
        return result.sorted { $0.date < $1.date }
    }

    private var chartGranularity: ChartGranularity {
        guard let oldest = filteredTransactions.map(\.date).min(),
              let newest = filteredTransactions.map(\.date).max() else { return .monthly }
        let months = Calendar.current.dateComponents([.month], from: oldest, to: newest).month ?? 0
        if months <= 12 { return .monthly }
        if months < 24  { return .quarterly }
        if months < 48  { return .yearComparison }
        return .yearly
    }

    private var chartData: [(label: String, date: Date, income: Double, expenses: Double)] {
        switch chartGranularity {
        case .monthly:       return monthlyData
        case .quarterly:     return quarterlyData
        case .yearComparison,
             .yearly:        return yearlyData
        }
    }

    private var monthlyData: [(label: String, date: Date, income: Double, expenses: Double)] {
        let cal = Calendar.current
        let relevant = filteredTransactions.filter { $0.category != .transfer }
        let grouped = Dictionary(grouping: relevant) {
            cal.dateComponents([.year, .month], from: $0.date)
        }
        return grouped
            .compactMap { key, txs -> (String, Date, Double, Double)? in
                guard let date = cal.date(from: key) else { return nil }
                let inc = txs.filter(\.isIncome).reduce(0)  { $0 + $1.amount }
                let exp = txs.filter(\.isExpense).reduce(0) { $0 + $1.amount }
                let monthNum = cal.component(.month, from: date)
                let year     = cal.component(.year,  from: date) % 100
                let abbrev   = date.formatted(.dateTime.month(.abbreviated))
                let lbl      = monthNum == 1 ? "\(abbrev) '\(String(format: "%02d", year))" : abbrev
                return (lbl, date, inc, exp)
            }
            .sorted { $0.1 < $1.1 }
            .map { (label: $0.0, date: $0.1, income: $0.2, expenses: $0.3) }
    }

    private var yearlyData: [(label: String, date: Date, income: Double, expenses: Double)] {
        let cal = Calendar.current
        let relevant = filteredTransactions.filter { $0.category != .transfer }
        let grouped = Dictionary(grouping: relevant) { cal.component(.year, from: $0.date) }
        return grouped
            .compactMap { year, txs -> (String, Date, Double, Double)? in
                guard let date = cal.date(from: DateComponents(year: year)) else { return nil }
                let inc = txs.filter(\.isIncome).reduce(0)  { $0 + $1.amount }
                let exp = txs.filter(\.isExpense).reduce(0) { $0 + $1.amount }
                return ("\(year)", date, inc, exp)
            }
            .sorted { $0.1 < $1.1 }
            .map { (label: $0.0, date: $0.1, income: $0.2, expenses: $0.3) }
    }

    private var quarterlyData: [(label: String, date: Date, income: Double, expenses: Double)] {
        let cal = Calendar.current
        let relevant = filteredTransactions.filter { $0.category != .transfer }
        let grouped = Dictionary(grouping: relevant) { tx -> String in
            let year    = cal.component(.year,  from: tx.date)
            let month   = cal.component(.month, from: tx.date)
            let quarter = (month - 1) / 3 + 1
            return "\(year)-\(quarter)"
        }
        return grouped
            .compactMap { key, txs -> (String, Date, Double, Double)? in
                let parts = key.split(separator: "-")
                guard parts.count == 2,
                      let year = Int(parts[0]), let quarter = Int(parts[1]) else { return nil }
                let startMonth = (quarter - 1) * 3 + 1
                guard let date = cal.date(from: DateComponents(year: year, month: startMonth)) else { return nil }
                let inc = txs.filter(\.isIncome).reduce(0)  { $0 + $1.amount }
                let exp = txs.filter(\.isExpense).reduce(0) { $0 + $1.amount }
                let yr  = year % 100
                return ("Q\(quarter) '\(String(format: "%02d", yr))", date, inc, exp)
            }
            .sorted { $0.1 < $1.1 }
            .map { (label: $0.0, date: $0.1, income: $0.2, expenses: $0.3) }
    }

    private func batchKey(for tx: ImportedTransaction) -> String {
        if !tx.importBatchID.isEmpty { return tx.importBatchID }
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: tx.importedAt)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(c.hour ?? 0)-\(c.minute ?? 0)"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
            Group {
                if profileTransactions.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        // Controls always visible at top
                        VStack(spacing: 10) {
                            HStack(spacing: 8) {
                                Button { showingPeriodFilter = true } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "calendar")
                                            .font(.system(size: 13, weight: .medium))
                                        Text(periodFilterLabel)
                                            .font(.subheadline.weight(.medium))
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundStyle(showCustomRange ? .white : .primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(showCustomRange ? Color.blue : Color(.secondarySystemBackground))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                                Spacer()
                                if accountGroups.count > 1 {
                                    accountFilterChips
                                }
                            }
                            mainTabPicker
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 10)
                        .background(.regularMaterial)

                        Divider()

                        if mainTab == .overview {
                            ScrollView {
                                VStack(spacing: 14) {
                                    summaryCard
                                    if chartData.count >= 2 || !balanceHistoryData.isEmpty { monthlyChartCard }
                                    if !expensesByCategory.isEmpty { categoryChartCard }
                                    trendsSection
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 96)
                            }
                            .background(AnimatedPatternBackground())
                            .task(id: trendTrigger) {
                                trendInsights = nil
                                let snapshot = filteredTransactions.map {
                                    TxData(date: $0.date, amount: $0.amount, isExpense: $0.isExpense,
                                           isTransfer: $0.category == .transfer, merchantName: $0.merchantName)
                                }
                                let currency = defaultCurrency
                                let result = await Task.detached(priority: .userInitiated) {
                                    AnalyseView.computeTrendInsights(from: snapshot, currency: currency)
                                }.value
                                trendInsights = result
                            }
                        } else {
                            transactionsTab
                                .background(AnimatedPatternBackground())
                        }
                    }
                }
            }

            // Dismiss overlay — tap or swipe anywhere outside the FAB
            if showingFAB {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            showingFAB = false
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    showingFAB = false
                                }
                            }
                    )
            }

            // Floating action button — always visible, even in the empty state
            analyseFAB
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("Analyse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .tint(.primary)
                }
                ToolbarItem(placement: .principal) {
                    ProfilePill()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingBatches = true } label: {
                        Image(systemName: "creditcard")
                    }
                    .tint(.primary)
                }
            }
            .fullScreenCover(isPresented: $showingImport) { BankImportView() }
            .fullScreenCover(isPresented: $showingAccounts) { AccountsView() }
            .fullScreenCover(isPresented: $showingSettings) { SettingsView() }
            .fullScreenCover(isPresented: $showingPaywall) { PaywallView().environment(purchases) }
            .fullScreenCover(isPresented: $showingBatches) {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 16) {
                            Button {
                                showingBatches = false
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(350))
                                    attemptImport()
                                }
                            } label: {
                                Label("Kontoauszug importieren", systemImage: "square.and.arrow.down")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)

                            accountGroupsSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .navigationTitle("Konten & Datensätze")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fertig") { showingBatches = false }.foregroundStyle(.primary)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingAddManualTx) {
                AddManualTransactionSheet(
                    profileID: activeProfileID,
                    accounts: Array(Set(profileTransactions.compactMap(\.account)))
                ) { newTx in
                    modelContext.insert(newTx)
                }
            }
            .fullScreenCover(isPresented: $showingRulesSheet) {
                CustomRulesSheet(
                    matchCount: { rule in
                        profileTransactions.filter {
                            rule.matches(merchant: $0.merchantName, amount: $0.amount, accountID: $0.account?.id, userNote: $0.userNote)
                        }.count
                    },
                    onSave: { _ in applyRulesToExisting() }
                )
            }
            .fullScreenCover(isPresented: $showingPeriodFilter) {
                PeriodFilterSheet(
                    selectedPeriod: $selectedPeriod,
                    showCustomRange: $showCustomRange,
                    customFrom: $customFrom,
                    customTo: $customTo,
                    txCount: filteredTransactions.count
                ) {
                    showingPeriodFilter = false
                }
            }
            .fullScreenCover(isPresented: $showingDetail) {
                if let batch = pendingBatch {
                    TransactionAnalysisView(
                        transactions: [],
                        bank: batch.bank,
                        customTitle: pendingTitle,
                        importedBatch: batch
                    )
                } else {
                    TransactionAnalysisView(
                        transactions: pendingTransactions,
                        bank: pendingBank,
                        customTitle: pendingTitle
                    )
                }
            }
            .fullScreenCover(item: $editingTx) { tx in
                AnalyseCategoryPickerSheet(
                    transaction: tx,
                    onRuleApplied: { applyRulesToExisting() },
                    customCategories: profileCustomCategories,
                    countMatchingTransactions: { keyword in
                        profileTransactions.filter {
                            $0.merchantName.uppercased().contains(keyword.uppercased())
                        }.count
                    },
                    noteApplyCount: {
                        profileTransactions.filter {
                            $0.merchantName == tx.merchantName && abs($0.rawAmount) == abs(tx.rawAmount)
                        }.count
                    },
                    applyNoteToAll: { noteText in
                        // Derive the category strictly from the NOTE TEXT, not from existing
                        // merchant rules — otherwise an older auto-rule on this merchant would
                        // win and override what the user just typed.
                        let rules = CustomRulesStore.load().sorted { $0.isAmountFiltered && !$1.isAmountFiltered }
                        var triggeredCat: TransactionCategory? = nil
                        let noteUp = noteText.uppercased()
                        for rule in rules where !rule.isWildcard {
                            let kw = rule.keyword.uppercased()
                            if !noteUp.isEmpty, noteUp.contains(kw), let cat = rule.category {
                                triggeredCat = cat
                                break
                            }
                        }
                        if triggeredCat == nil {
                            let noteCat = Categorizer.categorizeByMerchant(noteText, amount: tx.amount,
                                                                            accountID: tx.account?.id)
                            if noteCat != .sonstiges { triggeredCat = noteCat }
                        }
                        for other in profileTransactions where other.merchantName == tx.merchantName && abs(other.rawAmount) == abs(tx.rawAmount) {
                            other.userNote = noteText
                            // Force-overwrite category here — user intent is explicit.
                            if let cat = triggeredCat {
                                other.category = cat
                            }
                        }
                        // Persist as upsert so future imports of the same merchant get the new category,
                        // even if an older auto-rule already existed for this merchant.
                        if let cat = triggeredCat {
                            CustomRulesStore.upsertAutoRule(merchant: tx.merchantName, category: cat)
                        }
                    }
                )
            }
            .fullScreenCover(isPresented: $showingBulkCategoryPicker) {
                AnalyseBulkCategoryPickerSheet(
                    count: bulkSelectedIDs.count,
                    customCategories: profileCustomCategories,
                    onSelect: { category in applyBulkCategory(category) },
                    onSelectCustom: { custom in applyBulkCustomCategory(custom) }
                )
            }
            .confirmationDialog(
                "Datensatz löschen?",
                isPresented: Binding(get: { batchToDelete != nil }, set: { if !$0 { batchToDelete = nil } }),
                titleVisibility: .visible
            ) {
                if let batch = batchToDelete {
                    Button(String(format: NSLocalizedString("Löschen (%lld Transaktionen)", comment: ""), batch.transactions.count), role: .destructive) {
                        let captured = batch
                        batchToDelete = nil
                        Task { await deleteBatch(captured) }
                    }
                }
                Button("Abbrechen", role: .cancel) { batchToDelete = nil }
            } message: {
                Text("Alle Transaktionen dieses Imports werden dauerhaft entfernt.")
            }
            .onChange(of: mainTab) {
                isBulkEditing = false
                bulkSelectedIDs = []
                txCategoryFilter = nil
                txCustomCategoryFilter = nil
                txTypeFilter = nil
                txSearchText = ""
                txSearchApplied = ""
                // don't reset selectedAccountID — intentional filter carries over
            }
            .onChange(of: txSearchText) { _, newValue in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 420_000_000)  // 420 ms debounce
                    guard txSearchText == newValue else { return }
                    txSearchApplied = newValue
                }
            }
            .onChange(of: filterTrigger, initial: true) { rebuildFilteredTxs() }
            .onChange(of: NavigationRouter.shared.analyseCategoryFilter) { _, newValue in
                if let cat = newValue {
                    NavigationRouter.shared.analyseCategoryFilter = nil
                    // Apply date range before tab switch
                    if let from = NavigationRouter.shared.analyseDateFrom {
                        customFrom = from
                        customTo = .now
                        showCustomRange = true
                        NavigationRouter.shared.analyseDateFrom = nil
                    }
                    // Switch tab first (triggers onChange(of: mainTab) which resets filters)
                    mainTab = .transactions
                    // Set the filter in the next runloop, after the reset has fired
                    Task { @MainActor in
                        txCategoryFilter = cat
                        txCustomCategoryFilter = nil
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .categoryRulesDidImport)) { _ in
                applyRulesToExisting()
            }
        }

        .overlay {
            if isDeletingBatch {
                ZStack {
                    Color(.systemBackground).opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView(value: deletionProgress, total: Double(max(1, deletionTotal)))
                            .progressViewStyle(.linear)
                            .tint(.red)
                            .frame(maxWidth: 240)
                        Text(String(format: NSLocalizedString("%lld / %lld gelöscht …", comment: ""), Int(deletionProgress), deletionTotal))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isDeletingBatch)
            }
        }
    }

    // MARK: - Account filter chips

    private var accountFilterChips: some View {
        Button {
            showingAccountFilter = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "creditcard")
                    .font(.system(size: 13, weight: .medium))
                Text(accountFilterLabel)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selectedAccountIDs.isEmpty ? Color.primary : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selectedAccountIDs.isEmpty ? Color(.secondarySystemBackground) : Color.blue)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingAccountFilter, arrowEdge: .top) {
            AccountFilterPopover(accountGroups: accountGroups, selectedAccountIDs: $selectedAccountIDs)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var accountFilterLabel: String {
        if selectedAccountIDs.isEmpty { return "Alle Konten" }
        if selectedAccountIDs.count == 1,
           let group = accountGroups.first(where: { selectedAccountIDs.contains($0.accountID) }) {
            let name = group.accountName
            return name.count > 14 ? String(name.prefix(14)) + "…" : name
        }
        return "\(selectedAccountIDs.count) Konten"
    }

    // MARK: - Main tab picker

    private var mainTabPicker: some View {
        Picker("", selection: $mainTab) {
            ForEach(AnalyseMainTab.allCases, id: \.self) { tab in
                Text(LocalizedStringKey(tab.rawValue)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Transactions tab

    private var transactionsTab: some View {
        VStack(spacing: 0) {
            // Category filter chips + bulk controls
            txCategoryChips
            txSearchBar
            if !txSearchApplied.isEmpty {
                txSearchSummary
            }
            txColumnHeader

            if txFilteredList.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(.secondary.opacity(0.4))
                    Text("Keine Transaktionen").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(txFilteredList) { tx in
                            editableTxRow(tx)
                            Divider().padding(.leading, 64)
                        }
                        if isBulkEditing && !bulkSelectedIDs.isEmpty {
                            Color.clear.frame(height: 56)
                        }
                    }
                }
            }

            // Sticky bulk action bar
            if isBulkEditing && !bulkSelectedIDs.isEmpty {
                bulkActionBar
            }
        }
    }

    // MARK: - Search bar

    private var txSearchBar: some View {
        let isPending = !txSearchText.isEmpty && txSearchText != txSearchApplied
        let isActive = !txSearchText.isEmpty
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isActive ? .primary : Color(.tertiaryLabel))
            TextField("Suchen…", text: $txSearchText)
                .font(.system(size: 15))
                .autocorrectionDisabled()
                .onSubmit { txSearchApplied = txSearchText }
            if isPending {
                ProgressView().scaleEffect(0.72)
                    .tint(.secondary)
            } else if isActive {
                Button {
                    txSearchText = ""
                    txSearchApplied = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isActive ? Color.primary.opacity(0.18) : Color(.separator), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 3)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Search result summary

    private var txSearchSummary: some View {
        let results  = txFilteredList
        let count    = results.count
        let expTotal = results.filter(\.isExpense).reduce(0.0) { $0 + $1.amount }
        let incTotal = results.filter(\.isIncome ).reduce(0.0) { $0 + $1.amount }
        return HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(UIColor.tertiaryLabel))
            Text(String(format: NSLocalizedString("search_results_fmt", comment: ""), count))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            if expTotal > 0 {
                Text("·").font(.caption2).foregroundStyle(Color(UIColor.quaternaryLabel))
                Text("-\(expTotal.formatted(.currency(code: defaultCurrency)))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.red.opacity(0.75))
            }
            if incTotal > 0 {
                Text("·").font(.caption2).foregroundStyle(Color(UIColor.quaternaryLabel))
                Text("+\(incTotal.formatted(.currency(code: defaultCurrency)))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.green.opacity(0.75))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 5)
    }

    // MARK: - Column sort header

    private var txColumnHeader: some View {
        HStack(spacing: 0) {
            Text("Info")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color(UIColor.tertiaryLabel))

            Spacer()

            datumSortButton

            Text("·")
                .font(.caption2)
                .foregroundStyle(Color(UIColor.quaternaryLabel))
                .padding(.horizontal, 8)

            betragSortButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(.separator)).frame(height: 0.5) }
    }

    private var datumSortButton: some View {
        let isActive = txSortOrder == .dateDesc || txSortOrder == .dateAsc
        let chevron  = txSortOrder == .dateAsc    ? "chevron.up"
                     : txSortOrder == .dateDesc   ? "chevron.down"
                     : "chevron.up.chevron.down"
        return Button {
            txSortOrder = (txSortOrder == .dateDesc) ? .dateAsc : .dateDesc
        } label: {
            HStack(spacing: 3) {
                Text("Datum")
                Image(systemName: chevron)
                    .font(.system(size: 8, weight: isActive ? .semibold : .light))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(isActive ? Color.blue : Color(UIColor.secondaryLabel))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: txSortOrder)
    }

    private var betragSortButton: some View {
        let isActive = txSortOrder == .amountDesc || txSortOrder == .amountAsc
        let chevron  = txSortOrder == .amountAsc  ? "chevron.up"
                     : txSortOrder == .amountDesc ? "chevron.down"
                     : "chevron.up.chevron.down"
        return Button {
            txSortOrder = (txSortOrder == .amountDesc) ? .amountAsc : .amountDesc
        } label: {
            HStack(spacing: 3) {
                Text("Betrag")
                Image(systemName: chevron)
                    .font(.system(size: 8, weight: isActive ? .semibold : .light))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(isActive ? Color.blue : Color(UIColor.secondaryLabel))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: txSortOrder)
    }

    // MARK: - Category filter bar + edit toggle

    private var txCategoryChips: some View {
        let counts = categoryCount
        let customCounts = customCategoryCount
        let hasFilter = txCategoryFilter != nil || txCustomCategoryFilter != nil || txTypeFilter != nil
        return HStack(spacing: 8) {
            // Active filter pill (or "Alle")
            if let cat = txCategoryFilter {
                Button { txCategoryFilter = nil } label: {
                    HStack(spacing: 5) {
                        Image(systemName: cat.systemImage).font(.caption2)
                        Text(cat.localizedName).font(.caption.weight(.semibold))
                        Text("(\(counts[cat] ?? 0))").font(.caption2)
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.blue)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else if let custom = txCustomCategoryFilter {
                Button { txCustomCategoryFilter = nil } label: {
                    HStack(spacing: 5) {
                        Image(systemName: custom.systemImage).font(.caption2)
                        Text(custom.name).font(.caption.weight(.semibold))
                        Text("(\(customCounts[custom.id.uuidString] ?? 0))").font(.caption2)
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(custom.color)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else if let type = txTypeFilter {
                let typeCount = filteredTransactions.filter { type == .income ? $0.isIncome : $0.isExpense }.count
                Button { txTypeFilter = nil } label: {
                    HStack(spacing: 5) {
                        Image(systemName: type.icon).font(.caption2)
                        Text(type.label).font(.caption.weight(.semibold))
                        Text("(\(typeCount))").font(.caption2)
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(type.color)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text("Alle (\(filteredTransactions.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(Capsule())
            }

            // Category picker via Menu (no horizontal scrolling)
            Menu {
                let incomeCount = filteredTransactions.filter(\.isIncome).count
                let expenseCount = filteredTransactions.filter(\.isExpense).count
                if incomeCount > 0 {
                    Button {
                        txCategoryFilter = nil
                        txCustomCategoryFilter = nil
                        txTypeFilter = .income
                    } label: {
                        Label("Einnahmen (\(incomeCount))", systemImage: TxTypeFilter.income.icon)
                    }
                }
                if expenseCount > 0 {
                    Button {
                        txCategoryFilter = nil
                        txCustomCategoryFilter = nil
                        txTypeFilter = .expense
                    } label: {
                        Label("Ausgaben (\(expenseCount))", systemImage: TxTypeFilter.expense.icon)
                    }
                }
                if incomeCount > 0 || expenseCount > 0 {
                    Divider()
                }
                ForEach(TransactionCategory.allCases) { cat in
                    let count = counts[cat] ?? 0
                    if count > 0 {
                        Button {
                            txCustomCategoryFilter = nil
                            txTypeFilter = nil
                            txCategoryFilter = cat
                        } label: {
                            Label(cat.localizedName + " (\(count))", systemImage: cat.systemImage)
                        }
                    }
                }
                let profileCustom = profileCustomCategories
                if !profileCustom.isEmpty {
                    Divider()
                    ForEach(profileCustom) { custom in
                        let count = customCounts[custom.id.uuidString] ?? 0
                        if count > 0 {
                            Button {
                                txCategoryFilter = nil
                                txTypeFilter = nil
                                txCustomCategoryFilter = custom
                            } label: {
                                Label("\(custom.name) (\(count))", systemImage: custom.systemImage)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: hasFilter
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                    Text("Kategorie")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(hasFilter ? .white : .primary)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(hasFilter ? Color.blue : Color.primary.opacity(0.07))
                .clipShape(Capsule())
            }

            Spacer()

            // Bulk edit controls (only visible when active)
            if isBulkEditing {
                Button {
                    let all = Set(txFilteredList.map(\.id))
                    bulkSelectedIDs = bulkSelectedIDs.count == txFilteredList.count ? [] : all
                } label: {
                    Text(bulkSelectedIDs.count == txFilteredList.count ? "Keine" : "Alle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.blue.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    isBulkEditing = false
                    bulkSelectedIDs = []
                } label: {
                    Text("Fertig")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Editable transaction row

    private func editableTxRow(_ tx: ImportedTransaction) -> some View {
        let isSelected = bulkSelectedIDs.contains(tx.id)
        // Resolve custom category if set
        let customCat: UserTransactionCategory? = tx.customCategoryID.flatMap { cid in
            profileCustomCategories.first { $0.id.uuidString == cid }
        }
        let categoryIcon  = customCat?.systemImage ?? tx.category.systemImage
        let categoryColor = customCat?.color        ?? tx.category.color
        let categoryLabel = customCat?.name         ?? tx.category.localizedName

        return HStack(spacing: 12) {
            if isBulkEditing {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.4))
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            }

            ZStack {
                Circle().fill(categoryColor.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: categoryIcon)
                    .font(.caption.weight(.medium)).foregroundStyle(categoryColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.merchantName)
                    .font(.subheadline.weight(.medium)).lineLimit(1).foregroundStyle(.primary)
                if !tx.userNote.isEmpty {
                    Text(tx.userNote)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(tx.date.formatted(.dateTime.day().month().year()))
                        .font(.caption2).foregroundStyle(.secondary)
                    if let acct = tx.account {
                        Text("· \(acct.name)").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(tx.rawAmount, format: .currency(code: tx.currencyCode))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tx.isIncome ? Color.green : Color.primary)
                if !isBulkEditing {
                    HStack(spacing: 3) {
                        Text(categoryLabel)
                            .font(.caption2).foregroundStyle(categoryColor)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7)).foregroundStyle(.tertiary)
                    }
                } else {
                    Text(categoryLabel)
                        .font(.caption2).foregroundStyle(categoryColor)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(isSelected && isBulkEditing ? Color.blue.opacity(0.06) : Color(.systemBackground).opacity(0.01))
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.1), value: isSelected)
        .onTapGesture {
            if isBulkEditing {
                if isSelected { bulkSelectedIDs.remove(tx.id) } else { bulkSelectedIDs.insert(tx.id) }
            } else {
                editingTx = tx
            }
        }
    }

    // MARK: - Bulk action bar

    private var bulkActionBar: some View {
        HStack(spacing: 12) {
            Text(String(format: NSLocalizedString("%lld ausgewählt", comment: ""), bulkSelectedIDs.count))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showingBulkCategoryPicker = true
            } label: {
                Label("Kategorie zuweisen", systemImage: "tag.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private func applyBulkCategory(_ category: TransactionCategory) {
        for tx in filteredTransactions where bulkSelectedIDs.contains(tx.id) {
            tx.category = category   // also clears customCategoryID
        }
        bulkSelectedIDs = []
        isBulkEditing = false
    }

    private func applyBulkCustomCategory(_ custom: UserTransactionCategory) {
        for tx in filteredTransactions where bulkSelectedIDs.contains(tx.id) {
            tx.customCategoryID = custom.id.uuidString
            tx.categoryRaw = TransactionCategory.sonstiges.rawValue
        }
        bulkSelectedIDs = []
        isBulkEditing = false
    }

    private func applyRulesToExisting() {
        let rules = CustomRulesStore.load()
        guard !rules.isEmpty else { return }
        // Amount-filtered rules first so they win over catch-all rules with the same keyword
        let sorted = rules.sorted { $0.isAmountFiltered && !$1.isAmountFiltered }
        for tx in profileTransactions {
            for rule in sorted {
                // Merchant path: respect amount/account filters (rule was made for that merchant context).
                let merchantMatch = rule.matches(merchant: tx.merchantName, amount: tx.amount,
                                                  accountID: tx.account?.id, userNote: "")
                // Note path: keyword in the user-typed note overrides amount/account filters —
                // the user's explicit text intent should win.
                let noteMatch: Bool = {
                    guard !rule.isWildcard, !tx.userNote.isEmpty else { return false }
                    let kw = rule.keyword.uppercased()
                    guard !kw.isEmpty else { return false }
                    return tx.userNote.uppercased().contains(kw)
                }()
                guard merchantMatch || noteMatch else { continue }
                if let cat = rule.category {
                    tx.category = cat
                    tx.customCategoryID = nil
                } else if let custom = profileCustomCategories.first(where: { $0.name == rule.categoryRaw }) {
                    tx.customCategoryID = custom.id.uuidString
                    tx.categoryRaw = TransactionCategory.sonstiges.rawValue
                }
                break
            }
        }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        let income   = filteredTransactions.filter(\.isIncome).reduce(0)  { $0 + $1.amount }
        let expenses = filteredTransactions.filter(\.isExpense).reduce(0) { $0 + $1.amount }
        let net      = income - expenses

        return VStack(spacing: 14) {
            HStack {
                Text("Gesamt")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                if showCustomRange {
                    Text("· \(customFrom.formatted(.dateTime.day().month(.abbreviated))) – \(customTo.formatted(.dateTime.day().month(.abbreviated).year()))")
                        .font(.caption2.weight(.medium)).foregroundStyle(.blue)
                } else if selectedPeriod != .all {
                    Text(verbatim: "· " + selectedPeriod.localizedName)
                        .font(.caption2.weight(.medium)).foregroundStyle(.blue)
                }
                Spacer()
                Text("\(filteredTransactions.count) Tx").font(.caption2).foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                Button { navigateToTransactionType(.income) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Einnahmen", systemImage: "arrow.down.circle.fill")
                            .font(.caption2.weight(.medium)).foregroundStyle(.green)
                        Text(income, format: .currency(code: defaultCurrency).notation(.compactName))
                            .font(.title2.weight(.bold)).foregroundStyle(Color.green)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button { navigateToTransactionType(.expense) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Ausgaben", systemImage: "arrow.up.circle.fill")
                            .font(.caption2.weight(.medium)).foregroundStyle(.red)
                        Text(expenses, format: .currency(code: defaultCurrency).notation(.compactName))
                            .font(.title2.weight(.bold)).foregroundStyle(Color.red)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("Differenz").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: net >= 0 ? "arrow.up" : "arrow.down")
                    .font(.caption2.weight(.bold)).foregroundStyle(net >= 0 ? Color.green : Color.red)
                Text(net, format: .currency(code: defaultCurrency).notation(.compactName))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(net >= 0 ? Color.green : Color.red)
            }
            .padding(.horizontal, 2)
        }
        .padding(16).cardStyle(cornerRadius: 14)
    }

    // MARK: - Chart card (balance line / cashflow bars, switchable)

    private var monthlyChartCard: some View {
        let cashData    = chartData
        let balData     = balanceHistoryData
        let granularity = chartGranularity
        let lineColor   = fabAccentColor

        let hasBal  = !balData.isEmpty
        let hasCash = cashData.count >= 2
        let showLine = hasBal && (!hasCash || showBalanceLine)
        let balInterp: InterpolationMethod = balanceHistoryUsesMonthlyGranularity ? .linear : .stepEnd

        let balMonthSpan: Int = {
            guard let first = balData.first?.date, let last = balData.last?.date else { return 6 }
            return max(1, Calendar.current.dateComponents([.month], from: first, to: last).month ?? 6)
        }()
        // 3 days of breathing room — keeps domain tight to the last transaction date
        let domainEnd: Date = {
            let cal = Calendar.current
            guard let last = balData.last?.date,
                  let ext = cal.date(byAdding: .day, value: 3, to: last) else { return Date() }
            return ext
        }()

        // Bar chart selection — falls back to most recent bar when nothing is tapped
        let isYearBasedGran = granularity == .yearly || granularity == .yearComparison
        let barGranUnit: Calendar.Component = isYearBasedGran ? .year : .month
        let selectedBarItemRaw = selectedBarDate.flatMap { d in
            cashData.first { Calendar.current.isDate($0.date, equalTo: d, toGranularity: barGranUnit) }
        }
        let selectedBarItem = selectedBarItemRaw ?? cashData.last
        let isBarDefault = selectedBarDate == nil || selectedBarItemRaw == nil
        let barPeriodLabel = isBarDefault ? NSLocalizedString("today", comment: "") : (selectedBarItem?.label ?? "")

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                if showLine {
                    Text("Saldoverlauf").font(.subheadline.weight(.semibold))
                } else {
                    switch granularity {
                    case .monthly:
                        Text("Monatlicher Verlauf").font(.subheadline.weight(.semibold))
                    case .quarterly:
                        Text("Quartalsverlauf").font(.subheadline.weight(.semibold))
                        Text("· \(cashData.count) Quartale")
                            .font(.caption2.weight(.medium)).foregroundStyle(.blue)
                    case .yearComparison:
                        Text("Jahresvergleich").font(.subheadline.weight(.semibold))
                        Text("· Vorjahr vs. aktuell")
                            .font(.caption2.weight(.medium)).foregroundStyle(.blue)
                    case .yearly:
                        Text("Jährlicher Verlauf").font(.subheadline.weight(.semibold))
                        Text("· \(cashData.count) Jahre")
                            .font(.caption2.weight(.medium)).foregroundStyle(.blue)
                    }
                }
                Spacer()
                if hasBal && hasCash {
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showBalanceLine = true }
                        } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(showBalanceLine ? Color.secondary.opacity(0.18) : Color.clear)
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showBalanceLine = false }
                        } label: {
                            Image(systemName: "chart.bar.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(!showBalanceLine ? Color.secondary.opacity(0.18) : Color.clear)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            if showLine {
                AnalyseBalanceLineChart(
                    data: balData,
                    lineColor: lineColor,
                    interpolation: balInterp,
                    monthSpan: balMonthSpan,
                    domainEnd: domainEnd,
                    granularity: granularity,
                    currency: defaultCurrency,
                    usesMonthlyGranularity: balanceHistoryUsesMonthlyGranularity
                )
            } else if hasCash {
                periodChart(data: cashData, granularity: granularity, selectedDate: $selectedBarDate).frame(height: 160)
            }

            HStack(spacing: 16) {
                if !showLine && hasCash {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.75)).frame(width: 12, height: 8)
                        Text("\(barPeriodLabel):").font(.caption2).foregroundStyle(.secondary)
                        if let s = selectedBarItem {
                            Text(s.income, format: .currency(code: defaultCurrency).notation(.compactName).precision(.fractionLength(0)))
                                .font(.caption2.weight(.semibold)).foregroundStyle(.green)
                        } else {
                            Text("Einnahmen").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(0.75)).frame(width: 12, height: 8)
                        if let s = selectedBarItem {
                            Text(s.expenses, format: .currency(code: defaultCurrency).notation(.compactName).precision(.fractionLength(0)))
                                .font(.caption2.weight(.semibold)).foregroundStyle(.red)
                        } else {
                            Text("Ausgaben").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if showLine {
                    HStack(spacing: 6) {
                        Rectangle().fill(lineColor).frame(width: 14, height: 2)
                        Text("Heute:").font(.caption2).foregroundStyle(.secondary)
                        if let last = balData.last {
                            Text(last.balance, format: .currency(code: defaultCurrency).notation(.compactName))
                                .font(.caption2.weight(.semibold)).foregroundStyle(lineColor)
                        }
                    }
                }
                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showBalanceLine)
        .onChange(of: showBalanceLine) { _, _ in selectedBarDate = nil }
        .padding(16).cardStyle(cornerRadius: 14)
    }

    @ViewBuilder
    private func periodChart(data: [(label: String, date: Date, income: Double, expenses: Double)], granularity: ChartGranularity, selectedDate: Binding<Date?>) -> some View {
        let cal = Calendar.current
        let isYearBased = granularity == .yearly || granularity == .yearComparison
        let unit: Calendar.Component = isYearBased ? .year : .month
        // End domain at the last instant of the last data period — no empty extra periods
        let domainEnd: Date = {
            guard let last = data.last?.date else { return Date() }
            let periodComps: Set<Calendar.Component> = isYearBased ? [.year] : [.year, .month]
            let periodStart = cal.date(from: cal.dateComponents(periodComps, from: last)) ?? last
            let nextPeriodStart = cal.date(byAdding: unit, value: 1, to: periodStart) ?? last
            return nextPeriodStart.addingTimeInterval(-1)
        }()
        let domainStart: Date = data.first?.date ?? Date()
        // Quarterly bars span 3 month-slots → widen them so they look natural
        let barWidth: MarkDimension = granularity == .quarterly ? .ratio(0.85) : .ratio(0.4)
        let selVal = selectedDate.wrappedValue
        let selectionActive = selVal != nil

        Chart {
            ForEach(data, id: \.date) { item in
                let isSelected = selVal.map { cal.isDate(item.date, equalTo: $0, toGranularity: unit) } ?? false
                let opacity: Double = isSelected ? 0.95 : (selectionActive ? 0.28 : 0.75)
                BarMark(x: .value("Zeitraum", item.date, unit: unit), y: .value("Einnahmen", item.income), width: barWidth)
                    .foregroundStyle(Color.green.opacity(opacity)).position(by: .value("Typ", "Einnahmen"))
                BarMark(x: .value("Zeitraum", item.date, unit: unit), y: .value("Ausgaben", item.expenses), width: barWidth)
                    .foregroundStyle(Color.red.opacity(opacity)).position(by: .value("Typ", "Ausgaben"))
            }
        }
        .chartXScale(domain: domainStart...domainEnd)
        .chartXAxis {
            switch granularity {
            case .yearly, .yearComparison:
                AxisMarks(values: .stride(by: .year, count: data.count > 10 ? 2 : 1)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date.formatted(.dateTime.year(.twoDigits))).font(.caption2)
                        }
                    }
                }
            case .quarterly:
                AxisMarks(values: .automatic(desiredCount: data.count)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            let month   = cal.component(.month, from: date)
                            let quarter = (month - 1) / 3 + 1
                            let yr      = cal.component(.year, from: date) % 100
                            Text("Q\(quarter) '\(String(format: "%02d", yr))").font(.caption2)
                        }
                    }
                }
            case .monthly:
                AxisMarks(values: .stride(by: .month, count: data.count >= 8 ? 2 : 1)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date.formatted(.dateTime.month(.abbreviated))).font(.caption2)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v, format: .currency(code: defaultCurrency).notation(.compactName).precision(.fractionLength(0)))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let origin = proxy.plotFrame.map { geo[$0].origin } ?? .zero
                                let xPos = value.location.x - origin.x
                                if let tapped: Date = proxy.value(atX: xPos) {
                                    // Prefer granularity-aware match (exact month/quarter/year bucket)
                                    let match = data.first { cal.isDate($0.date, equalTo: tapped, toGranularity: unit) }
                                    let resolved = match ?? data.min {
                                        abs($0.date.timeIntervalSince(tapped)) < abs($1.date.timeIntervalSince(tapped))
                                    }
                                    if let resolved { selectedDate.wrappedValue = resolved.date }
                                }
                            }
                    )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: data.count)
    }

    // MARK: - Floating Action Button

    private var fabAccentColor: Color {
        (BackgroundTheme(rawValue: rawTheme) ?? .emerald).primary
    }

    private var analyseFAB: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if showingFAB {
                // Popup card box
                VStack(spacing: 0) {
                    fabMenuItem(
                        label: "Transaktion hinzufügen",
                        sublabel: nil,
                        icon: "pencil",
                        color: Color(.label)
                    ) {
                        showingFAB = false
                        showingAddManualTx = true
                    }
                    Divider().padding(.leading, 52)
                    fabMenuItem(
                        label: "Kontoauszug importieren",
                        sublabel: "Möchtest du Daten importieren?",
                        icon: "square.and.arrow.down",
                        color: Color(.label)
                    ) {
                        showingFAB = false
                        attemptImport()
                    }
                    Divider().padding(.leading, 52)
                    fabMenuItem(
                        label: "Kategorien & Regeln",
                        sublabel: nil,
                        icon: "slider.horizontal.3",
                        color: Color(.label)
                    ) {
                        showingFAB = false
                        showingRulesSheet = true
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(.separator), lineWidth: 1.0)
                )
                .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 8)
                .frame(width: 248)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity),
                    removal:   .scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity)
                ))
            }

            // FAB button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                    showingFAB.toggle()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(fabAccentColor)
                        .frame(width: 50, height: 50)
                        .shadow(color: fabAccentColor.opacity(0.4), radius: 10, x: 0, y: 4)
                    Image(systemName: showingFAB ? "minus" : "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func fabMenuItem(label: LocalizedStringKey, sublabel: LocalizedStringKey?, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    if let sub = sublabel {
                        Text(sub).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category chart card

    private func navigateToCategory(_ item: CategoryPieItem) {
        mainTab = .transactions
        Task { @MainActor in
            if let builtIn = item.builtIn {
                txCategoryFilter = builtIn
                txCustomCategoryFilter = nil
            } else if let custom = item.customCategory {
                txCustomCategoryFilter = custom
                txCategoryFilter = nil
            }
        }
    }

    private func navigateToTransactionType(_ type: TxTypeFilter) {
        mainTab = .transactions
        Task { @MainActor in
            txCategoryFilter = nil
            txCustomCategoryFilter = nil
            txTypeFilter = type
        }
    }

    private func categoryForPieValue(_ val: Double) -> CategoryPieItem? {
        var cumulative = 0.0
        for item in expensesByCategory {
            cumulative += item.total
            if val <= cumulative { return item }
        }
        return nil
    }

    private var categoryChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text("Ausgaben nach Kategorie").font(.subheadline.weight(.semibold))
                Button {
                    showCategoryInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showCategoryInfo, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Kategorisierung", systemImage: "info.circle")
                            .font(.subheadline.weight(.semibold))
                        Text("Die automatische Kategorisierung basiert auf Stichwörtern im Verwendungszweck und kann **Fehler enthalten** – besonders bei unbekannten Zahlungen landet vieles unter «Unkategorisiert».")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Du kannst Buchungen korrigieren, indem du **Regeln** definierst oder einer Transaktion manuell eine **Notiz mit Kategorie** vergibst. So lernt die Auswertung mit der Zeit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(width: 280)
                    .presentationCompactAdaptation(.popover)
                }
            }

            Chart(expensesByCategory) { item in
                let selectedID = pieSelectedValue.flatMap { categoryForPieValue($0) }?.id
                let dimmed = pieSelectedValue != nil && selectedID != item.id
                SectorMark(angle: .value("Betrag", item.total), innerRadius: .ratio(0.58), angularInset: 1.5)
                    .foregroundStyle(item.color.opacity(dimmed ? 0.35 : 1.0))
                    .cornerRadius(3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .chartAngleSelection(value: $pieSelectedValue)
            .onChange(of: pieSelectedValue) { _, newVal in
                guard let val = newVal, let item = categoryForPieValue(val) else { return }
                pieSelectedValue = nil
                navigateToCategory(item)
            }

            let grandTotal = expensesByCategory.reduce(0.0) { $0 + $1.total }
            let maxVal = expensesByCategory.first?.total ?? 1

            VStack(spacing: 8) {
                ForEach(expensesByCategory) { item in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(item.color.opacity(0.15))
                                .frame(width: 26, height: 26)
                            Image(systemName: item.systemImage)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(item.color)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(grandTotal > 0 ? item.total / grandTotal : 0, format: .percent.precision(.fractionLength(1)))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(item.total, format: .currency(code: defaultCurrency).notation(.compactName))
                                    .font(.caption2.weight(.semibold))
                                    .frame(width: 52, alignment: .trailing)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.secondary.opacity(0.1))
                                        .frame(height: 5)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(item.color.opacity(0.75))
                                        .frame(width: geo.size.width * CGFloat(item.total / maxVal), height: 5)
                                }
                            }
                            .frame(height: 5)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { navigateToCategory(item) }
                }
            }
        }
        .padding(16).cardStyle(cornerRadius: 14)
    }

    // MARK: - Account groups section

    private var accountGroupsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Konten & Datensätze")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                let totalBatches = accountGroups.reduce(0) { $0 + $1.batches.count }
                Text(String(format: NSLocalizedString("imports_count_fmt", comment: ""), totalBatches)).font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.leading, 2)

            ForEach(accountGroups) { group in accountGroupCard(group) }
        }
    }

    private func accountGroupCard(_ group: AccountGroup) -> some View {
        VStack(spacing: 0) {
            Button {
                if selectedAccountIDs.contains(group.accountID) {
                    selectedAccountIDs.remove(group.accountID)
                } else {
                    selectedAccountIDs.insert(group.accountID)
                }
                mainTab = .transactions
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(group.color.opacity(0.15)).frame(width: 44, height: 44)
                        Image(systemName: group.icon).font(.subheadline.weight(.medium)).foregroundStyle(group.color)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.accountName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text(String(format: NSLocalizedString("tx_imports_count_fmt", comment: ""), group.transactions.count, group.batches.count))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        let net = group.totalIncome - group.totalExpenses
                        Text(net, format: .currency(code: defaultCurrency).notation(.compactName))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(net >= 0 ? Color.green : Color.red)
                        Text("Gesamt").font(.caption2).foregroundStyle(.secondary)
                    }
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.subheadline).foregroundStyle(.tertiary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if !group.batches.isEmpty {
                Divider().padding(.leading, 72)
                ForEach(Array(group.batches.enumerated()), id: \.element.id) { idx, batch in
                    batchRow(batch)
                    if idx < group.batches.count - 1 { Divider().padding(.leading, 44) }
                }
            }
        }
        .cardStyle(cornerRadius: 14)
    }

    private func batchRow(_ batch: ImportBatch) -> some View {
        HStack(spacing: 12) {
            Image(systemName: batch.bank.logoSymbol)
                .font(.caption).foregroundStyle(.secondary).frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                if let from = batch.oldestDate, let to = batch.newestDate {
                    if Calendar.current.isDate(from, equalTo: to, toGranularity: .month) {
                        Text(from.formatted(.dateTime.month(.wide).year())).font(.caption.weight(.medium))
                    } else {
                        Text("\(from.formatted(.dateTime.month(.abbreviated).year())) – \(to.formatted(.dateTime.month(.abbreviated).year()))")
                            .font(.caption.weight(.medium))
                    }
                }
                Text("\(batch.transactions.count) Tx · \(batch.bank.rawValue)").font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                pendingBatch  = batch
                pendingTitle  = batch.oldestDate.map { $0.formatted(.dateTime.month(.abbreviated).year()) }
                showingDetail = true
            } label: {
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.blue.opacity(0.6))
            }
            .buttonStyle(.plain)

            Button { batchToDelete = batch } label: {
                Image(systemName: "trash").font(.caption2).foregroundStyle(Color.red.opacity(0.7))
                    .padding(6).background(Color.red.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - Delete batch

    @MainActor
    private func deleteBatch(_ batch: ImportBatch) async {
        let txs = batch.transactions
        guard !txs.isEmpty else { return }
        deletionTotal = txs.count
        deletionProgress = 0
        withAnimation { isDeletingBatch = true }
        let chunkSize = 50
        for chunkStart in stride(from: 0, to: txs.count, by: chunkSize) {
            let end = min(chunkStart + chunkSize, txs.count)
            for i in chunkStart..<end {
                modelContext.delete(txs[i])
            }
            deletionProgress = Double(end)
            await Task.yield()
        }
        withAnimation { isDeletingBatch = false }
    }

    // MARK: - Filter caching

    private var filterTrigger: String {
        let ids = selectedAccountIDs.sorted().joined(separator: ",")
        let dateKey = showCustomRange
            ? "\(Int(customFrom.timeIntervalSince1970))-\(Int(customTo.timeIntervalSince1970))"
            : selectedPeriod.rawValue
        return "\(allTransactions.count)|\(activeProfileID)|\(dateKey)|\(ids)"
    }

    private func rebuildFilteredTxs() {
        var txs = allTransactions.filter { $0.profileID == activeProfileID }
        if !selectedAccountIDs.isEmpty {
            txs = txs.filter { tx in
                guard let id = tx.account?.id.uuidString else { return false }
                return selectedAccountIDs.contains(id)
            }
        }
        if showCustomRange {
            let from = Calendar.current.startOfDay(for: customFrom)
            let to = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: customTo)) ?? customTo
            cachedFilteredTxs = txs.filter { $0.date >= from && $0.date < to }
            return
        }
        guard let cutoff = selectedPeriod.cutoffDate else { cachedFilteredTxs = txs; return }
        if let end = selectedPeriod.cutoffEndDate {
            cachedFilteredTxs = txs.filter { $0.date >= cutoff && $0.date < end }
            return
        }
        cachedFilteredTxs = txs.filter { $0.date >= cutoff }
    }

    // MARK: - Trend insights

    private var trendTrigger: String { filterTrigger }

    private nonisolated static func computeTrendInsights(from txData: [TxData], currency: String) -> [TrendInsight] {
        let cal = Calendar.current
        let now = Date()
        let expenses = txData.filter { $0.isExpense && !$0.isTransfer }
        var insights: [TrendInsight] = []

        // 1. Month-over-month: last complete month vs the one before
        let lastMonthDate = cal.date(byAdding: .month, value: -1, to: now)!
        let twoMonthsAgoDate = cal.date(byAdding: .month, value: -2, to: now)!
        let lastMonthExp = expenses.filter { cal.isDate($0.date, equalTo: lastMonthDate, toGranularity: .month) }
        let prevMonthExp  = expenses.filter { cal.isDate($0.date, equalTo: twoMonthsAgoDate, toGranularity: .month) }
        if lastMonthExp.count >= 5 && prevMonthExp.count >= 5 {
            let lastTotal = lastMonthExp.reduce(0) { $0 + $1.amount }
            let prevTotal = prevMonthExp.reduce(0) { $0 + $1.amount }
            let pct = prevTotal > 0 ? (lastTotal - prevTotal) / prevTotal * 100 : 0
            let dir: TrendDirection = pct > 5 ? .up : pct < -5 ? .down : .neutral
            let sign = pct >= 0 ? "+" : ""
            let monthName = lastMonthDate.formatted(.dateTime.month(.wide))
            let dirColor1: Color
            switch dir { case .up: dirColor1 = .red; case .down: dirColor1 = .green; case .neutral: dirColor1 = .secondary }
            insights.append(TrendInsight(
                icon: "calendar.badge.clock",
                iconColor: dirColor1,
                title: monthName,
                value: lastTotal.formatted(.currency(code: currency).notation(.compactName)),
                valueColor: .primary,
                direction: dir,
                description: String(format: NSLocalizedString("trend_pct_vs_prev_month_fmt", comment: ""), sign + String(format: "%.0f", pct))
            ))
        }

        // 2. Weekday with highest average spending (min 5 occurrences)
        var weekdayAmounts = [Int: [Double]]()
        for tx in expenses {
            let wd = cal.component(.weekday, from: tx.date)
            weekdayAmounts[wd, default: []].append(tx.amount)
        }
        let qualifiedDays = weekdayAmounts.filter { $0.value.count >= 5 }
        if !qualifiedDays.isEmpty {
            let avgByDay = qualifiedDays.mapValues { $0.reduce(0, +) / Double($0.count) }
            if let (topDay, topAvg) = avgByDay.max(by: { $0.value < $1.value }) {
                let dayName = cal.weekdaySymbols[topDay - 1]
                let formatted = topAvg.formatted(.currency(code: currency).notation(.compactName))
                insights.append(TrendInsight(
                    icon: "calendar.day.timeline.left",
                    iconColor: .orange,
                    title: NSLocalizedString("trend_title_teuerster_wochentag", comment: ""),
                    value: dayName,
                    valueColor: .orange,
                    direction: .neutral,
                    description: String(format: NSLocalizedString("trend_avg_per_weekday_fmt", comment: ""), formatted, dayName)
                ))
            }
        }

        // 3. Seasonal: quarterly comparison (min 2 months per quarter, min 2 quarters)
        var quarterMonthlyTotals = [Int: [Double]]()
        let monthlyGroups = Dictionary(grouping: expenses) { tx -> String in
            let comps = cal.dateComponents([.year, .month], from: tx.date)
            return "\(comps.year ?? 0)-\(comps.month ?? 1)"
        }
        for (key, txs) in monthlyGroups {
            let parts = key.split(separator: "-")
            guard parts.count == 2, let month = Int(parts[1]) else { continue }
            let q = (month - 1) / 3 + 1
            quarterMonthlyTotals[q, default: []].append(txs.reduce(0) { $0 + $1.amount })
        }
        let qualifiedQuarters = quarterMonthlyTotals.filter { $0.value.count >= 2 }
        if qualifiedQuarters.count >= 2 {
            let quarterAvgs = qualifiedQuarters.mapValues { $0.reduce(0, +) / Double($0.count) }
            if let (topQ, topAvg) = quarterAvgs.max(by: { $0.value < $1.value }) {
                let m = cal.shortMonthSymbols
                let qRanges = ["", "\(m[0])–\(m[2])", "\(m[3])–\(m[5])", "\(m[6])–\(m[8])", "\(m[9])–\(m[11])"]
                let formatted = topAvg.formatted(.currency(code: currency).notation(.compactName))
                insights.append(TrendInsight(
                    icon: "chart.bar.fill",
                    iconColor: .purple,
                    title: NSLocalizedString("trend_title_ausgaben_saison", comment: ""),
                    value: "Q\(topQ)",
                    valueColor: .purple,
                    direction: .neutral,
                    description: String(format: NSLocalizedString("trend_avg_per_month_season_fmt", comment: ""), formatted, qRanges[topQ])
                ))
            }
        }

        // 4. Year-over-year (min 3 months this year, min 5 last year)
        let thisYear = cal.component(.year, from: now)
        let lastYear = thisYear - 1
        let thisYearExp = expenses.filter { cal.component(.year, from: $0.date) == thisYear }
        let lastYearExp = expenses.filter { cal.component(.year, from: $0.date) == lastYear }
        let thisYearMonths = Set(thisYearExp.map { cal.component(.month, from: $0.date) })
        let lastYearMonths = Set(lastYearExp.map { cal.component(.month, from: $0.date) })
        if thisYearMonths.count >= 3 && lastYearMonths.count >= 5 {
            let thisTotal = thisYearExp.reduce(0) { $0 + $1.amount }
            let lastSameMonths = lastYearExp.filter { thisYearMonths.contains(cal.component(.month, from: $0.date)) }
            let lastNorm = lastSameMonths.reduce(0) { $0 + $1.amount }
            if lastNorm > 0 {
                let pct = (thisTotal - lastNorm) / lastNorm * 100
                let dir: TrendDirection = pct > 5 ? .up : pct < -5 ? .down : .neutral
                let sign = pct >= 0 ? "+" : ""
                let dirColor4: Color
                switch dir { case .up: dirColor4 = .red; case .down: dirColor4 = .green; case .neutral: dirColor4 = .secondary }
                insights.append(TrendInsight(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: dirColor4,
                    title: NSLocalizedString("trend_title_jahresvergleich", comment: ""),
                    value: "\(sign)\(String(format: "%.0f", pct))%",
                    valueColor: dirColor4,
                    direction: dir,
                    description: String(format: NSLocalizedString("trend_year_vs_year_fmt", comment: ""), thisYear, lastYear)
                ))
            }
        }

        // 5. Most frequent merchant (min 5 transactions)
        let merchantGroups = Dictionary(grouping: expenses) { $0.merchantName }
        let qualifiedMerchants = merchantGroups.filter { $0.value.count >= 5 }
        if let (merchant, txs) = qualifiedMerchants.max(by: { $0.value.count < $1.value.count }) {
            let total = txs.reduce(0) { $0 + $1.amount }
            insights.append(TrendInsight(
                icon: "cart.fill",
                iconColor: .blue,
                title: NSLocalizedString("trend_title_haeufigster_haendler", comment: ""),
                value: merchant,
                valueColor: .primary,
                direction: .neutral,
                description: String(format: NSLocalizedString("trend_merchant_count_total_fmt", comment: ""), txs.count, total.formatted(.currency(code: currency).notation(.compactName)))
            ))
        }

        // 6. 3-month spending trajectory
        let m1 = cal.date(byAdding: .month, value: -3, to: now)!
        let m2 = cal.date(byAdding: .month, value: -2, to: now)!
        let m3 = cal.date(byAdding: .month, value: -1, to: now)!
        let monthTotals = [m1, m2, m3].map { mDate in
            expenses.filter { cal.isDate($0.date, equalTo: mDate, toGranularity: .month) }.reduce(0) { $0 + $1.amount }
        }
        if monthTotals.filter({ $0 > 0 }).count >= 3 {
            let changes = zip(monthTotals.dropFirst(), monthTotals).map { ($0 - $1) / max($1, 1) * 100 }
            let avgChange = changes.reduce(0, +) / Double(changes.count)
            let dir: TrendDirection = avgChange > 5 ? .up : avgChange < -5 ? .down : .neutral
            let sign = avgChange >= 0 ? "+" : ""
            let label6: String; let icon6: String; let dirColor6: Color
            switch dir {
            case .up:      label6 = NSLocalizedString("trend_steigend", comment: "");  icon6 = "arrow.up.right";   dirColor6 = .red
            case .down:    label6 = NSLocalizedString("trend_sinkend", comment: "");   icon6 = "arrow.down.right"; dirColor6 = .green
            case .neutral: label6 = NSLocalizedString("trend_stabil", comment: "");    icon6 = "minus";            dirColor6 = .secondary
            }
            insights.append(TrendInsight(
                icon: icon6,
                iconColor: dirColor6,
                title: NSLocalizedString("trend_title_3_monats_trend", comment: ""),
                value: label6,
                valueColor: dirColor6,
                direction: dir,
                description: String(format: NSLocalizedString("trend_pct_monthly_change_fmt", comment: ""), sign + String(format: "%.0f", avgChange))
            ))
        }

        return Array(insights.prefix(6))
    }

    @ViewBuilder
    private var trendsSection: some View {
        if let insights = trendInsights {
            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Trends & Einblicke")
                        .font(.subheadline.weight(.semibold))
                    VStack(spacing: 8) {
                        ForEach(insights) { insight in
                            TrendInsightCard(insight: insight)
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 130, height: 12)
                VStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { _ in TrendSkeletonCard() }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ZStack {
            AnimatedPatternBackground()
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "chart.bar.xaxis").font(.system(size: 52)).foregroundStyle(.secondary.opacity(0.5))
                VStack(spacing: 6) {
                    Text("Keine importierten Daten").font(.title3.weight(.semibold))
                    Text("Importiere deinen ersten Bankauszug, um\ndeine Ausgaben zu analysieren.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button { attemptImport() } label: {
                    Label("Kontoauszug importieren", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(Color.blue).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button { showingAccounts = true } label: {
                    Label("Konto hinzufügen", systemImage: "plus.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(Color.secondary.opacity(0.12)).foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Spacer()
            }
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Account filter popover

private struct AccountFilterPopover: View {
    let accountGroups: [AccountGroup]
    @Binding var selectedAccountIDs: Set<String>
    @Environment(\.dismiss) private var dismiss

    // Local draft — parent only updates on dismiss, preventing re-renders while picking
    @State private var draft: Set<String>

    init(accountGroups: [AccountGroup], selectedAccountIDs: Binding<Set<String>>) {
        self.accountGroups = accountGroups
        self._selectedAccountIDs = selectedAccountIDs
        self._draft = State(initialValue: selectedAccountIDs.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Konto filtern")
                    .font(.headline)
                Spacer()
                Button("Fertig") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    // "Alle Konten" row
                    rowButton(
                        icon: "tray.2",
                        color: .blue,
                        name: "Alle Konten",
                        isSelected: draft.isEmpty
                    ) {
                        draft = []
                    }

                    Divider().padding(.leading, 52)

                    ForEach(Array(accountGroups.enumerated()), id: \.element.id) { idx, group in
                        rowButton(
                            icon: group.icon,
                            color: group.color,
                            name: group.accountName,
                            isSelected: draft.contains(group.accountID)
                        ) {
                            if draft.contains(group.accountID) {
                                draft.remove(group.accountID)
                            } else {
                                draft.insert(group.accountID)
                            }
                        }
                        if idx < accountGroups.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 280)
        .onDisappear {
            selectedAccountIDs = draft
        }
    }

    @ViewBuilder
    private func rowButton(icon: String, color: Color, name: String,
                           isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(color)
                }

                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}

// MARK: - Balance line chart (isolated subview for smooth scrubbing)

private struct AnalyseBalanceLineChart: View {
    let data: [(date: Date, balance: Double)]
    let lineColor: Color
    let interpolation: InterpolationMethod
    let monthSpan: Int
    let domainEnd: Date
    let granularity: ChartGranularity
    let currency: String
    let usesMonthlyGranularity: Bool

    @State private var selectedDate: Date? = nil

    private var selectedPoint: (date: Date, balance: Double)? {
        guard let d = selectedDate else { return nil }
        return data.first { $0.date == d }
    }

    var body: some View {
        VStack(spacing: 8) {
            Chart {
                ForEach(Array(data.enumerated()), id: \.offset) { _, pt in
                    AreaMark(x: .value("Tag", pt.date), y: .value("Saldo", pt.balance))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [lineColor.opacity(0.28), lineColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(interpolation)
                    LineMark(x: .value("Tag", pt.date), y: .value("Saldo", pt.balance))
                        .foregroundStyle(lineColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(interpolation)
                        .symbolSize(0)
                }
                RuleMark(y: .value("zero", 0))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                if let d = selectedDate, let sp = selectedPoint {
                    RuleMark(x: .value("sel", d))
                        .foregroundStyle(Color.primary.opacity(0.08))
                        .lineStyle(StrokeStyle(lineWidth: 8))
                    PointMark(x: .value("sel", d), y: .value("sel", sp.balance))
                        .foregroundStyle(Color(.systemBackground))
                        .symbolSize(130)
                    PointMark(x: .value("sel", d), y: .value("sel", sp.balance))
                        .foregroundStyle(lineColor)
                        .symbolSize(50)
                }
            }
            .frame(height: 160)
            .chartXScale(domain: (data.first?.date ?? Date())...domainEnd)
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v, format: .currency(code: currency).notation(.compactName).precision(.fractionLength(0)))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                switch granularity {
                case .yearly, .yearComparison:
                    AxisMarks(values: .stride(by: .year, count: monthSpan / 12 > 10 ? 2 : 1)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date.formatted(.dateTime.year(.twoDigits))).font(.caption2)
                            }
                        }
                    }
                case .quarterly:
                    AxisMarks(values: .stride(by: .month, count: 3)) { value in
                        if let date = value.as(Date.self) {
                            let cal = Calendar.current
                            let month   = cal.component(.month, from: date)
                            let quarter = (month - 1) / 3 + 1
                            let yr      = cal.component(.year, from: date) % 100
                            AxisValueLabel {
                                Text("Q\(quarter) '\(String(format: "%02d", yr))").font(.caption2)
                            }
                        }
                    }
                case .monthly:
                    AxisMarks(values: .stride(by: .month, count: monthSpan >= 8 ? 2 : 1)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date.formatted(.dateTime.month(.abbreviated))).font(.caption2)
                            }
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let origin = proxy.plotFrame.map { geo[$0].origin } ?? .zero
                                    let xPos = value.location.x - origin.x
                                    if let dragged: Date = proxy.value(atX: xPos) {
                                        let nearest = data.min {
                                            abs($0.date.timeIntervalSince(dragged)) < abs($1.date.timeIntervalSince(dragged))
                                        }
                                        if let nearest, nearest.date != selectedDate {
                                            selectedDate = nearest.date
                                        }
                                    }
                                }
                        )
                }
            }

            if let sp = selectedPoint, let d = selectedDate {
                HStack {
                    Text(d, format: usesMonthlyGranularity
                         ? .dateTime.month(.abbreviated).year(.twoDigits)
                         : .dateTime.day().month(.abbreviated).year(.twoDigits))
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(sp.balance, format: .currency(code: currency))
                        .font(.caption2.weight(.semibold)).foregroundStyle(lineColor)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDate)
    }
}

// MARK: - Trend insight card

private struct TrendInsightCard: View {
    let insight: TrendInsight

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(insight.iconColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: insight.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(insight.iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(insight.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if insight.direction != .neutral {
                    Image(systemName: insight.direction == .up ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(insight.valueColor)
                }
                Text(insight.value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(insight.valueColor)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .cardStyle(cornerRadius: 14)
    }
}

private struct TrendSkeletonCard: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 120, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 180, height: 10)
            }

            Spacer()

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 60, height: 14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .cardStyle(cornerRadius: 14)
        .opacity(pulse ? 0.45 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Single category picker (Analyse context)

private struct AnalyseCategoryPickerSheet: View {
    @Bindable var transaction: ImportedTransaction
    let onRuleApplied: (() -> Void)?
    let customCategories: [UserTransactionCategory]
    let countMatchingTransactions: (String) -> Int
    let noteApplyCount: () -> Int
    let applyNoteToAll: (String) -> Void
    @AppStorage("default_currency") private var defaultCurrency: String = "CHF"
    @AppStorage("active_profile_id") private var activeProfileID: String = ""
    @Environment(\.dismiss) private var dismiss
    @Query private var allAccounts: [Account]

    @State private var createRule        = false
    @State private var ruleKeyword       = ""
    @State private var keywordMatchCount = 0
    @State private var amountFilter      = false
    @State private var amountTolerance   = 0.0
    @State private var ruleAccountIDs: Set<UUID> = []
    @State private var showingCategoryManager = false
    @State private var cachedNoteApplyCount: Int = 0
    @State private var localNote: String = ""
    @State private var applyNoteToAllToggle: Bool = false
    @State private var cachedRules: [CategoryRule] = []
    @State private var didExplicitlyPickCategory = false
    @State private var didSaveExplicitly = false

    private var profileAccounts: [Account] {
        allAccounts.filter { $0.profileID == activeProfileID }.sorted { $0.name < $1.name }
    }

    private var noteTriggeredCategory: TransactionCategory? {
        guard !localNote.isEmpty else { return nil }
        let noteUp = localNote.uppercased()
        // 1. Check user-defined rules — match keyword against the NOTE TEXT only.
        //    Ignore the rule's amount/account filters here: the user just typed a keyword on a
        //    different transaction, so the explicit text intent should override those filters.
        for rule in cachedRules where !rule.isWildcard {
            let kw = rule.keyword.uppercased()
            guard !kw.isEmpty, noteUp.contains(kw), let cat = rule.category else { continue }
            return cat == transaction.category ? nil : cat
        }
        // 2. Fallback: run the built-in categorizer on the note text itself
        let noteCat = Categorizer.categorizeByMerchant(localNote, amount: transaction.amount,
                                                        accountID: transaction.account?.id)
        guard noteCat != .sonstiges, noteCat != transaction.category else { return nil }
        return noteCat
    }

    var body: some View {
        NavigationStack {
            List {
                // Transaction preview
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(transaction.merchantName).font(.subheadline.weight(.semibold))
                            Text(transaction.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(transaction.rawAmount, format: .currency(code: transaction.currencyCode))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(transaction.isIncome ? Color.green : Color.primary)
                    }
                    .padding(.vertical, 4)
                    HStack(spacing: 8) {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary).font(.caption)
                        TextField("Notiz hinzufügen…", text: $localNote)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                    if cachedNoteApplyCount > 1 {
                        Toggle(isOn: $applyNoteToAllToggle) {
                            HStack(spacing: 6) {
                                Text(String(format: NSLocalizedString("Notiz auf alle %lld anwenden", comment: ""), cachedNoteApplyCount))
                                    .font(.caption)
                                    .foregroundStyle(applyNoteToAllToggle ? .primary : .secondary)
                            }
                        }
                        .tint(.blue)
                    }
                    // Show which category the note would trigger (if any rule matches)
                    if !localNote.isEmpty {
                        if let triggered = noteTriggeredCategory {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.caption2).foregroundStyle(.blue)
                                Text("Notiz setzt Kategorie auf")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Image(systemName: triggered.systemImage)
                                    .font(.caption2).foregroundStyle(triggered.color)
                                Text(triggered.localizedName)
                                    .font(.caption2.weight(.medium)).foregroundStyle(triggered.color)
                            }
                        } else {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2).foregroundStyle(Color.secondary.opacity(0.5))
                                Text("Kategorie bleibt unverändert")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Options toggles
                Section {
                    Toggle(isOn: $createRule) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Regel erstellen")
                                .font(.subheadline)
                            Text("Alle bisherigen & künftigen Transaktionen zuweisen")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: createRule) { _, on in
                        if on { keywordMatchCount = countMatchingTransactions(ruleKeyword) }
                    }

                    if createRule {
                        VStack(spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                                TextField("Stichwort  (oder * für alles)", text: $ruleKeyword)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.characters)
                                    .onChange(of: ruleKeyword) { _, val in
                                        keywordMatchCount = countMatchingTransactions(val)
                                    }
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(keywordMatchCount == 0
                                     ? "Keine Transaktionen treffen zu"
                                     : "\(keywordMatchCount) Transaktion\(keywordMatchCount == 1 ? "" : "en") treffen zu")
                                    .font(.caption2)
                                    .foregroundStyle(keywordMatchCount > 0 ? Color.blue : Color.secondary)
                                Spacer()
                            }
                        }
                        .padding(.vertical, 2)

                        Toggle(isOn: $amountFilter) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Betrag einschränken")
                                    .font(.subheadline)
                                Text("Nur bei ähnlichem Betrag anwenden")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }

                        if amountFilter {
                            VStack(spacing: 10) {
                                HStack {
                                    Text("Referenzbetrag")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(abs(transaction.rawAmount), format: .currency(code: transaction.currencyCode))
                                        .font(.caption.weight(.semibold))
                                }
                                Picker("Toleranz", selection: $amountTolerance) {
                                    Text("Exakt").tag(0.0)
                                    Text("±5%").tag(5.0)
                                    Text("±10%").tag(10.0)
                                    Text("±20%").tag(20.0)
                                }
                                .pickerStyle(.segmented)
                                let base = abs(transaction.rawAmount)
                                let tol  = base * amountTolerance / 100
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    if amountTolerance == 0 {
                                        Text(String(format: NSLocalizedString("Passt nur auf exakt %@", comment: ""), base.formatted(.currency(code: transaction.currencyCode))))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    } else {
                                        Text("Bereich: \((base - tol).formatted(.currency(code: transaction.currencyCode).precision(.fractionLength(0)))) – \((base + tol).formatted(.currency(code: transaction.currencyCode).precision(.fractionLength(0))))")
                                            .font(.caption2).foregroundStyle(.blue)
                                    }
                                    Spacer()
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        if !profileAccounts.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                let acctColor: Color = ruleAccountIDs.isEmpty ? .secondary : .blue
                                HStack(spacing: 4) {
                                    Image(systemName: "building.columns")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Text(ruleAccountIDs.isEmpty ? "Alle Konten" : "\(ruleAccountIDs.count) Konto\(ruleAccountIDs.count == 1 ? "" : "en")")
                                        .font(.caption2).foregroundStyle(acctColor)
                                }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(profileAccounts) { acct in
                                            let sel = ruleAccountIDs.contains(acct.id)
                                            Button {
                                                if sel { ruleAccountIDs.remove(acct.id) }
                                                else { ruleAccountIDs.insert(acct.id) }
                                            } label: {
                                                Text(acct.name)
                                                    .font(.caption.weight(.medium))
                                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                                    .background(sel ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.1))
                                                    .foregroundStyle(sel ? Color.blue : Color.primary)
                                                    .clipShape(Capsule())
                                                    .overlay(Capsule().stroke(sel ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Optionen")
                }

                // Built-in categories
                Section("Kategorie wählen") {
                    ForEach(TransactionCategory.allCases) { cat in
                        let isSelected = transaction.customCategoryID == nil && transaction.category == cat
                        Button { applyBuiltIn(cat) } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(cat.color.opacity(0.12)).frame(width: 30, height: 30)
                                    Image(systemName: cat.systemImage)
                                        .font(.caption.weight(.medium)).foregroundStyle(cat.color)
                                }
                                Text(cat.localizedName).foregroundStyle(Color.primary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark").foregroundStyle(.blue).fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Custom categories
                if !customCategories.isEmpty {
                    Section("Eigene Kategorien") {
                        ForEach(customCategories) { custom in
                            let isSelected = transaction.customCategoryID == custom.id.uuidString
                            Button { applyCustom(custom) } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(custom.color.opacity(0.12)).frame(width: 30, height: 30)
                                        Image(systemName: custom.systemImage)
                                            .font(.caption.weight(.medium)).foregroundStyle(custom.color)
                                    }
                                    Text(custom.name).foregroundStyle(Color.primary)
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark").foregroundStyle(.blue).fontWeight(.semibold)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button { showingCategoryManager = true } label: {
                        Label("Eigene Kategorien verwalten", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle("Kategorie ändern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.foregroundStyle(.primary) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        didSaveExplicitly = true
                        transaction.userNote = localNote
                        if !didExplicitlyPickCategory, let triggered = noteTriggeredCategory {
                            transaction.category = triggered
                        }
                        if applyNoteToAllToggle { applyNoteToAll(localNote) }
                        NoteRulesStore.addOrUpdate(merchantName: transaction.merchantName,
                                                   amount: transaction.amount,
                                                   noteText: localNote,
                                                   profileID: activeProfileID)
                        // Re-apply all rules across all transactions — the just-saved note
                        // may match an existing rule's keyword on other transactions too.
                        onRuleApplied?()
                        dismiss()
                    }
                    .foregroundStyle(.primary)
                }
            }
            .sheet(isPresented: $showingCategoryManager) { CategoryManagementView() }
            .onAppear {
                ruleKeyword = transaction.merchantName
                localNote = transaction.userNote
                cachedNoteApplyCount = noteApplyCount()
                cachedRules = CustomRulesStore.load().sorted { $0.isAmountFiltered && !$1.isAmountFiltered }
            }
            .onDisappear {
                guard !didSaveExplicitly else { return }
                transaction.userNote = localNote
                if !didExplicitlyPickCategory, let triggered = noteTriggeredCategory {
                    transaction.category = triggered
                }
                if applyNoteToAllToggle { applyNoteToAll(localNote) }
                NoteRulesStore.addOrUpdate(merchantName: transaction.merchantName,
                                           amount: transaction.amount,
                                           noteText: localNote,
                                           profileID: activeProfileID)
                onRuleApplied?()
            }
        }
    }

    private func buildAndSaveRule(categoryRaw: String) {
        let kw = ruleKeyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        var rules = CustomRulesStore.load()
        if !amountFilter {
            rules.removeAll { $0.keyword.uppercased() == kw.uppercased() && !$0.isAmountFiltered }
        }
        var rule = CategoryRule(keyword: kw, categoryRaw: categoryRaw)
        if amountFilter {
            let base = abs(transaction.rawAmount)
            let tol  = base * amountTolerance / 100
            rule.amountMin = max(0, base - tol)
            rule.amountMax = base + tol
        }
        rule.accountIDs = ruleAccountIDs.isEmpty ? nil : Array(ruleAccountIDs)
        rules.append(rule)
        CustomRulesStore.save(rules)
        onRuleApplied?()
    }

    private func applyBuiltIn(_ cat: TransactionCategory) {
        didExplicitlyPickCategory = true
        transaction.userNote = localNote
        transaction.category = cat
        transaction.customCategoryID = nil
        if createRule { buildAndSaveRule(categoryRaw: cat.rawValue) }
        dismiss()
    }

    private func applyCustom(_ custom: UserTransactionCategory) {
        didExplicitlyPickCategory = true
        transaction.userNote = localNote
        transaction.customCategoryID = custom.id.uuidString
        transaction.categoryRaw = TransactionCategory.sonstiges.rawValue
        if createRule { buildAndSaveRule(categoryRaw: custom.name) }
        dismiss()
    }
}

// MARK: - Bulk category picker (Analyse context)

private struct AnalyseBulkCategoryPickerSheet: View {
    let count: Int
    let customCategories: [UserTransactionCategory]
    let onSelect: (TransactionCategory) -> Void
    let onSelectCustom: (UserTransactionCategory) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Kategorie für \(count) Transaktionen") {
                    ForEach(TransactionCategory.allCases) { cat in
                        Button {
                            onSelect(cat)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(cat.color.opacity(0.12)).frame(width: 30, height: 30)
                                    Image(systemName: cat.systemImage)
                                        .font(.caption.weight(.medium)).foregroundStyle(cat.color)
                                }
                                Text(cat.localizedName).foregroundStyle(Color.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !customCategories.isEmpty {
                    Section("Eigene Kategorien") {
                        ForEach(customCategories) { custom in
                            Button {
                                onSelectCustom(custom)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(custom.color.opacity(0.12)).frame(width: 30, height: 30)
                                        Image(systemName: custom.systemImage)
                                            .font(.caption.weight(.medium)).foregroundStyle(custom.color)
                                    }
                                    Text(custom.name).foregroundStyle(Color.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("\(count) Transaktionen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.foregroundStyle(.primary) }
            }
        }
    }
}

// MARK: - Custom Rules Sheet

private struct CustomRulesSheet: View {
    let matchCount: (CategoryRule) -> Int
    let onSave: ([CategoryRule]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("active_profile_id") private var activeProfileID: String = ""
    @AppStorage("default_currency")  private var defaultCurrency: String = "CHF"
    @Query private var allCustomCategories: [UserTransactionCategory]
    @Query private var allAccounts: [Account]

    @State private var rules: [CategoryRule] = CustomRulesStore.load()
    @State private var showingAdd = false
    @State private var newKeyword           = ""
    @State private var newCategoryRaw: String = TransactionCategory.sonstiges.rawValue
    @State private var newAmountFilter      = false
    @State private var newAmountText        = ""
    @State private var newAmountTolerance   = 0.0
    @State private var newAccountIDs: Set<UUID> = []
    @State private var ruleToEdit: CategoryRule? = nil
    @State private var showingCategoryManager = false
    @State private var matchCounts: [UUID: Int] = [:]
    @State private var cacheVersion = 0
    @State private var showingDeleteAllConfirmation = false

    private var customCategories: [UserTransactionCategory] {
        allCustomCategories.filter { $0.profileID == activeProfileID }
    }

    private var profileAccounts: [Account] {
        allAccounts.filter { $0.profileID == activeProfileID }.sorted { $0.name < $1.name }
    }

    private var groupedRules: [(categoryRaw: String, rules: [CategoryRule])] {
        var groups: [String: [CategoryRule]] = [:]
        for rule in rules {
            groups[rule.categoryRaw, default: []].append(rule)
        }
        return groups
            .map { (categoryRaw: $0.key, rules: $0.value) }
            .sorted { lhs, rhs in
                let lCount = lhs.rules.reduce(0) { $0 + (matchCounts[$1.id, default: 0]) }
                let rCount = rhs.rules.reduce(0) { $0 + (matchCounts[$1.id, default: 0]) }
                return lCount != rCount ? lCount > rCount : lhs.rules.count > rhs.rules.count
            }
    }

    private func displayInfo(for rawValue: String) -> (name: String, systemImage: String, color: Color) {
        if let bi = TransactionCategory(rawValue: rawValue) { return (bi.localizedName, bi.systemImage, bi.color) }
        if let cu = customCategories.first(where: { $0.name == rawValue }) { return (cu.name, cu.systemImage, cu.color) }
        return (rawValue.isEmpty ? NSLocalizedString("Unkategorisiert", comment: "") : rawValue, "tag.fill", .gray)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                if showingAdd {
                    Section("Neue Regel") {
                        TextField("Stichwort, z.B. MIGROS  (oder * für alles)", text: $newKeyword)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .id("newRuleTop")

                        let trimmed = newKeyword.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            let count = matchCount(buildTempRule())
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(count == 0
                                     ? NSLocalizedString("keine_transaktionen_treffen_zu", comment: "")
                                     : String(format: NSLocalizedString("transactions_match_fmt", comment: ""), count))
                                    .font(.caption2)
                                    .foregroundStyle(count > 0 ? Color.blue : Color.secondary)
                            }
                        }

                        let selInfo = displayInfo(for: newCategoryRaw)
                        Menu {
                            Section("Standard") {
                                ForEach(TransactionCategory.allCases) { cat in
                                    Button { newCategoryRaw = cat.rawValue } label: {
                                        Label(cat.localizedName, systemImage: cat.systemImage)
                                    }
                                }
                            }
                            if !customCategories.isEmpty {
                                Section("Eigene") {
                                    ForEach(customCategories) { cat in
                                        Button { newCategoryRaw = cat.name } label: {
                                            Label(cat.name, systemImage: cat.systemImage)
                                        }
                                    }
                                }
                            }
                            Section {
                                Button { showingCategoryManager = true } label: {
                                    Label("Neue Kategorie erstellen …", systemImage: "plus.circle")
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(selInfo.color.opacity(0.12)).frame(width: 26, height: 26)
                                    Image(systemName: selInfo.systemImage)
                                        .font(.caption.weight(.medium)).foregroundStyle(selInfo.color)
                                }
                                Text(selInfo.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Toggle(isOn: $newAmountFilter) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Betrag einschränken")
                                    .font(.subheadline)
                                Text("Nur bei ähnlichem Betrag anwenden")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }

                        if newAmountFilter {
                            HStack(spacing: 8) {
                                Image(systemName: "equal.circle")
                                    .foregroundStyle(.secondary).font(.subheadline)
                                TextField("Betrag, z.B. 3500", text: $newAmountText)
                                    .keyboardType(.decimalPad)
                                Text(defaultCurrency)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Picker("Toleranz", selection: $newAmountTolerance) {
                                Text("Exakt").tag(0.0)
                                Text("±5%").tag(5.0)
                                Text("±10%").tag(10.0)
                                Text("±20%").tag(20.0)
                            }
                            .pickerStyle(.segmented)
                            if let base = Double(newAmountText.replacingOccurrences(of: ",", with: ".")) {
                                let tol = base * newAmountTolerance / 100
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    if newAmountTolerance == 0 {
                                        Text("Exakt \(base.formatted(.currency(code: defaultCurrency)))")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    } else {
                                        Text("Bereich: \((base - tol).formatted(.currency(code: defaultCurrency).precision(.fractionLength(0)))) – \((base + tol).formatted(.currency(code: defaultCurrency).precision(.fractionLength(0))))")
                                            .font(.caption2).foregroundStyle(.blue)
                                    }
                                    Spacer()
                                }
                            }
                        }

                        if !profileAccounts.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    Image(systemName: "building.columns")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    let acctLabel = newAccountIDs.isEmpty ? "Alle Konten" : "\(newAccountIDs.count) Konto\(newAccountIDs.count == 1 ? "" : "en")"
                                    let acctLabelColor: Color = newAccountIDs.isEmpty ? .secondary : .blue
                                    Text(acctLabel)
                                        .font(.caption2).foregroundStyle(acctLabelColor)
                                }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(profileAccounts) { account in
                                            let selected = newAccountIDs.contains(account.id)
                                            Button {
                                                if selected { newAccountIDs.remove(account.id) }
                                                else { newAccountIDs.insert(account.id) }
                                            } label: {
                                                Text(account.name)
                                                    .font(.caption.weight(.medium))
                                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                                    .background(selected ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.1))
                                                    .foregroundStyle(selected ? .blue : .primary)
                                                    .clipShape(Capsule())
                                                    .overlay(Capsule().stroke(selected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        Button("Hinzufügen") { addRule() }
                            .disabled(trimmed.isEmpty)
                    }
                }

                if !rules.isEmpty {
                    ForEach(groupedRules, id: \.categoryRaw) { group in
                        let groupInfo = displayInfo(for: group.categoryRaw)
                        let totalMatches = group.rules.reduce(0) { $0 + matchCounts[$1.id, default: 0] }
                        Section {
                            ForEach(group.rules) { rule in
                                let count = matchCounts[rule.id, default: 0]
                                let scopedAccounts: [String] = rule.accountIDs?.compactMap { id in
                                    profileAccounts.first(where: { $0.id == id })?.name
                                } ?? []
                                Button { ruleToEdit = rule } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle().fill(groupInfo.color.opacity(0.12)).frame(width: 32, height: 32)
                                            Image(systemName: groupInfo.systemImage)
                                                .font(.caption.weight(.medium)).foregroundStyle(groupInfo.color)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(rule.isWildcard ? "* (Alle)" : rule.keyword)
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(rule.isWildcard ? Color.purple : Color.primary)
                                                if rule.isAutoGenerated {
                                                    Text("auto")
                                                        .font(.system(size: 10, weight: .medium))
                                                        .foregroundStyle(.secondary)
                                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                                        .background(Color.secondary.opacity(0.12))
                                                        .clipShape(Capsule())
                                                }
                                                if let min = rule.amountMin {
                                                    Text("≈\(min.formatted(.currency(code: defaultCurrency).precision(.fractionLength(0))))")
                                                        .font(.system(size: 10, weight: .medium))
                                                        .foregroundStyle(.orange)
                                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                                        .background(Color.orange.opacity(0.1))
                                                        .clipShape(Capsule())
                                                }
                                            }
                                            if !scopedAccounts.isEmpty {
                                                Text(scopedAccounts.joined(separator: ", "))
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.blue)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        if count > 0 {
                                            Text("\(count)")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.8))
                                                .clipShape(Capsule())
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.caption2).foregroundStyle(Color.secondary.opacity(0.4))
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { idx in
                                let toDelete = Set(idx.map { group.rules[$0].id })
                                rules.removeAll { toDelete.contains($0.id) }
                                saveAndApply()
                            }
                        } header: {
                            HStack(spacing: 5) {
                                Image(systemName: groupInfo.systemImage)
                                    .font(.caption2)
                                    .foregroundStyle(groupInfo.color)
                                Text(groupInfo.name)
                                if totalMatches > 0 {
                                    Text("· \(totalMatches) Treffer")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section {
                        Button {
                            sendRulesEmail()
                        } label: {
                            Label("Regeln per Mail einsenden", systemImage: "envelope")
                        }
                        Button(role: .destructive) {
                            showingDeleteAllConfirmation = true
                        } label: {
                            Label("Alle Regeln löschen", systemImage: "trash")
                        }
                    } footer: {
                        Text("Gute Regeln werden in zukünftige App-Versionen aufgenommen — danke für deinen Beitrag!")
                            .font(.caption2)
                    }
                }

                if rules.isEmpty && !showingAdd {
                    ContentUnavailableView {
                        Label("Keine Regeln", systemImage: "list.bullet.clipboard")
                    } description: {
                        Text("Tippe auf + um ein eigenes Stichwort\nmit einer Kategorie zu verknüpfen.")
                    }
                }
            }
            .navigationTitle("Kategorisierungsregeln")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { showingAdd.toggle() }
                        if !showingAdd { newKeyword = "" }
                    } label: {
                        Image(systemName: showingAdd ? "xmark" : "plus")
                    }
                    .foregroundStyle(.primary)
                }
            }
            .sheet(item: $ruleToEdit) { rule in
                EditRuleSheet(rule: rule, customCategories: customCategories, accounts: profileAccounts) { updated in
                    if let idx = rules.firstIndex(where: { $0.id == updated.id }) {
                        rules[idx] = updated
                        saveAndApply()
                    }
                }
            }
            .sheet(isPresented: $showingCategoryManager) { CategoryManagementView() }
            .confirmationDialog(String(format: NSLocalizedString("Alle %lld Regeln löschen?", comment: ""), rules.count), isPresented: $showingDeleteAllConfirmation, titleVisibility: .visible) {
                Button("Alle löschen", role: .destructive) {
                    rules.removeAll()
                    saveAndApply()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Diese Aktion kann nicht rückgängig gemacht werden.")
            }
            .onChange(of: showingAdd) { _, isShowing in
                if isShowing {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        withAnimation { proxy.scrollTo("newRuleTop", anchor: .top) }
                    }
                }
            }
            .task(id: cacheVersion) {
                var counts: [UUID: Int] = [:]
                for rule in rules {
                    counts[rule.id] = matchCount(rule)
                }
                matchCounts = counts
            }
            } // ScrollViewReader
        }
    }

    private func buildTempRule() -> CategoryRule {
        var rule = CategoryRule(keyword: newKeyword.trimmingCharacters(in: .whitespaces), categoryRaw: newCategoryRaw)
        if newAmountFilter, let base = Double(newAmountText.replacingOccurrences(of: ",", with: ".")) {
            let tol = base * newAmountTolerance / 100
            rule.amountMin = max(0, base - tol)
            rule.amountMax = base + tol
        }
        rule.accountIDs = newAccountIDs.isEmpty ? nil : Array(newAccountIDs)
        return rule
    }

    private func addRule() {
        let rule = buildTempRule()
        guard !rule.keyword.isEmpty else { return }
        rules.insert(rule, at: 0)   // newest rule at top
        saveAndApply()
        newKeyword = ""
        newAmountFilter = false
        newAmountText = ""
        newAccountIDs = []
        showingAdd = false
    }

    private func saveAndApply() {
        CustomRulesStore.save(rules)
        onSave(rules)
        cacheVersion += 1
    }

    private func sendRulesEmail() {
        let lines = rules.map { "  \($0.keyword) → \($0.categoryRaw)" }.joined(separator: "\n")
        let body = "Meine Kategorisierungsregeln (FinanceHelper):\n\n\(lines)\n\n---\nGesendet aus FinanceHelper"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@financehelper.ch"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "FinanceHelper Kategorisierungsregeln"),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url { openURL(url) }
    }
}

// MARK: - Edit Rule Sheet

private struct EditRuleSheet: View {
    let rule: CategoryRule
    let customCategories: [UserTransactionCategory]
    let accounts: [Account]
    let onSave: (CategoryRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("default_currency") private var defaultCurrency: String = "CHF"
    @State private var keyword: String
    @State private var categoryRaw: String
    @State private var amountMin: Double?
    @State private var amountMax: Double?
    @State private var selectedAccountIDs: Set<UUID>
    @State private var showingCategoryManager = false

    init(rule: CategoryRule, customCategories: [UserTransactionCategory], accounts: [Account], onSave: @escaping (CategoryRule) -> Void) {
        self.rule = rule
        self.customCategories = customCategories
        self.accounts = accounts
        self.onSave = onSave
        _keyword            = State(initialValue: rule.keyword)
        _categoryRaw        = State(initialValue: rule.categoryRaw)
        _amountMin          = State(initialValue: rule.amountMin)
        _amountMax          = State(initialValue: rule.amountMax)
        _selectedAccountIDs = State(initialValue: Set(rule.accountIDs ?? []))
    }

    private func displayInfo(for rawValue: String) -> (name: String, systemImage: String, color: Color) {
        if let bi = TransactionCategory(rawValue: rawValue) { return (bi.localizedName, bi.systemImage, bi.color) }
        if let cu = customCategories.first(where: { $0.name == rawValue }) { return (cu.name, cu.systemImage, cu.color) }
        return (rawValue.isEmpty ? NSLocalizedString("Unkategorisiert", comment: "") : rawValue, "tag.fill", .gray)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Stichwort") {
                    TextField("z.B. MIGROS  (oder * für alles)", text: $keyword)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                Section("Kategorie") {
                    let selInfo = displayInfo(for: categoryRaw)
                    Menu {
                        Section("Standard") {
                            ForEach(TransactionCategory.allCases) { cat in
                                Button { categoryRaw = cat.rawValue } label: {
                                    Label(cat.rawValue, systemImage: cat.systemImage)
                                }
                            }
                        }
                        if !customCategories.isEmpty {
                            Section("Eigene") {
                                ForEach(customCategories) { cat in
                                    Button { categoryRaw = cat.name } label: {
                                        Label(cat.name, systemImage: cat.systemImage)
                                    }
                                }
                            }
                        }
                        Section {
                            Button { showingCategoryManager = true } label: {
                                Label("Neue Kategorie erstellen …", systemImage: "plus.circle")
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(selInfo.color.opacity(0.12)).frame(width: 26, height: 26)
                                Image(systemName: selInfo.systemImage)
                                    .font(.caption.weight(.medium)).foregroundStyle(selInfo.color)
                            }
                            Text(selInfo.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if let min = amountMin, let max = amountMax {
                    Section("Betrag") {
                        HStack {
                            Image(systemName: "equal.circle.fill")
                                .foregroundStyle(.orange).font(.subheadline)
                            Text("\(min.formatted(.currency(code: defaultCurrency).precision(.fractionLength(0)))) – \(max.formatted(.currency(code: defaultCurrency).precision(.fractionLength(0))))")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.orange)
                            Spacer()
                        }
                        Button("Betragsbindung entfernen", role: .destructive) {
                            amountMin = nil
                            amountMax = nil
                        }
                    }
                }
                if !accounts.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "building.columns")
                                    .font(.caption2).foregroundStyle(.secondary)
                                let editAcctLabel: String = selectedAccountIDs.isEmpty
                                    ? NSLocalizedString("Alle Konten", comment: "")
                                    : selectedAccountIDs.count == 1
                                        ? NSLocalizedString("1 Konto ausgewählt", comment: "")
                                        : String(format: NSLocalizedString("%lld Konten ausgewählt", comment: ""), selectedAccountIDs.count)
                                let editAcctColor: Color = selectedAccountIDs.isEmpty ? .secondary : .blue
                                Text(editAcctLabel)
                                    .font(.caption2).foregroundStyle(editAcctColor)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(accounts) { account in
                                        let selected = selectedAccountIDs.contains(account.id)
                                        Button {
                                            if selected { selectedAccountIDs.remove(account.id) }
                                            else { selectedAccountIDs.insert(account.id) }
                                        } label: {
                                            Text(account.name)
                                                .font(.caption.weight(.medium))
                                                .padding(.horizontal, 10).padding(.vertical, 5)
                                                .background(selected ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.1))
                                                .foregroundStyle(selected ? .blue : .primary)
                                                .clipShape(Capsule())
                                                .overlay(Capsule().stroke(selected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Konten")
                    } footer: {
                        Text("Leer lassen = auf alle Konten anwenden.")
                            .font(.caption2)
                    }
                }
                if rule.isAutoGenerated {
                    Section {
                        Label("Automatisch generiert — wird nach dem Speichern als eigene Regel markiert.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Regel bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.foregroundStyle(.primary) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        var updated = rule
                        updated.keyword = keyword.trimmingCharacters(in: .whitespaces)
                        updated.categoryRaw = categoryRaw
                        updated.isAutoGenerated = false
                        updated.amountMin = amountMin
                        updated.amountMax = amountMax
                        updated.accountIDs = selectedAccountIDs.isEmpty ? nil : Array(selectedAccountIDs)
                        onSave(updated)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingCategoryManager) { CategoryManagementView() }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Add Manual Transaction Sheet

private struct AddManualTransactionSheet: View {
    let profileID: String
    let accounts: [Account]
    let onAdd: (ImportedTransaction) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("default_currency") private var defaultCurrency: String = "CHF"

    @State private var date: Date = .now
    @State private var merchantName: String = ""
    @State private var amountText: String = ""
    @State private var isExpense: Bool = true
    @State private var category: TransactionCategory = .sonstiges
    @State private var selectedAccount: Account? = nil

    private var amountValue: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }
    private var canSave: Bool {
        !merchantName.trimmingCharacters(in: .whitespaces).isEmpty && amountValue != nil && amountValue! > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaktion") {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    TextField("Händler / Beschreibung", text: $merchantName)
                        .autocorrectionDisabled()
                }

                Section("Betrag") {
                    HStack {
                        Picker("", selection: $isExpense) {
                            Text("Ausgabe").tag(true)
                            Text("Einnahme").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 160)

                        Spacer()

                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)

                        Text(defaultCurrency)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }

                Section("Kategorie") {
                    Picker("Kategorie", selection: $category) {
                        ForEach(TransactionCategory.allCases) { cat in
                            Label(cat.localizedName, systemImage: cat.systemImage).tag(cat)
                        }
                    }
                }

                if !accounts.isEmpty {
                    Section("Konto (optional)") {
                        Picker("Konto", selection: $selectedAccount) {
                            Text("Kein Konto").tag(Account?.none)
                            ForEach(accounts, id: \.id) { acct in
                                Text(acct.name).tag(Account?.some(acct))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Transaktion hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        guard let value = amountValue, canSave else { return }
                        let raw = isExpense ? -value : value
                        let batchTx = BankTransaction(
                            date: date,
                            description: merchantName.trimmingCharacters(in: .whitespaces),
                            rawAmount: raw,
                            valueDate: date,
                            category: isExpense ? category : .einkommen,
                            merchantName: merchantName.trimmingCharacters(in: .whitespaces)
                        )
                        let imported = ImportedTransaction(
                            from: batchTx,
                            bank: .zugerKantonalbank,
                            profileID: profileID,
                            batchID: "manual-\(UUID().uuidString)"
                        )
                        imported.account = selectedAccount
                        onAdd(imported)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Data models

struct ImportBatch: Identifiable {
    let batchID:      String
    let transactions: [ImportedTransaction]
    let bank:         BankFormat
    let importedAt:   Date
    var id: String { batchID }
    var oldestDate: Date? { transactions.map(\.date).min() }
    var newestDate: Date? { transactions.map(\.date).max() }
    var bankTransactions: [BankTransaction] { transactions.map { $0.toBankTransaction() } }
}

struct AccountGroup: Identifiable {
    let accountID:   String
    let accountName: String
    let icon:        String
    let color:       Color
    let batches:     [ImportBatch]
    var id: String { accountID }
    var transactions: [ImportedTransaction] { batches.flatMap(\.transactions) }
    var primaryBank: BankFormat { batches.first?.bank ?? .zugerKantonalbank }
    var totalIncome:   Double { transactions.filter(\.isIncome).reduce(0)  { $0 + $1.amount } }
    var totalExpenses: Double { transactions.filter(\.isExpense).reduce(0) { $0 + $1.amount } }
    var oldestDate: Date? { transactions.map(\.date).min() }
    var newestDate: Date? { transactions.map(\.date).max() }
}

// MARK: - Period Filter Sheet

private struct PeriodFilterSheet: View {
    @Binding var selectedPeriod: AnalysePeriod
    @Binding var showCustomRange: Bool
    @Binding var customFrom: Date
    @Binding var customTo: Date
    let txCount: Int
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Preset period grid
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Zeitraum")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(AnalysePeriod.allCases, id: \.self) { period in
                                periodButton(period)
                            }
                        }
                        // Custom range button (full-width, distinct colour)
                        customRangeButton
                    }

                    // Date pickers — appear when custom range is selected
                    if showCustomRange {
                        VStack(spacing: 10) {
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Von")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    DatePicker("", selection: $customFrom, in: ...customTo, displayedComponents: .date)
                                        .labelsHidden()
                                        .datePickerStyle(.compact)
                                        .tint(.orange)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)

                                Divider().frame(height: 50)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Bis")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    DatePicker("", selection: $customTo, in: customFrom..., displayedComponents: .date)
                                        .labelsHidden()
                                        .datePickerStyle(.compact)
                                        .tint(.orange)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            }
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            Button(action: onDone) {
                                Text("Übernehmen")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.orange)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Transaction count info
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: NSLocalizedString("transactions_in_period_fmt", comment: ""), txCount))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .animation(.easeInOut(duration: 0.2), value: showCustomRange)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Zeitraum wählen").font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { onDone() }
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    @ViewBuilder
    private func periodButton(_ period: AnalysePeriod) -> some View {
        let isActive = !showCustomRange && selectedPeriod == period
        Button {
            selectedPeriod = period
            showCustomRange = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                onDone()
            }
        } label: {
            Text(period.localizedName)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(isActive ? Color.blue : Color(.systemBackground))
                .foregroundStyle(isActive ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isActive ? Color.clear : Color(.systemGray4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    private var customRangeButton: some View {
        let isActive = showCustomRange
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { showCustomRange = true }
        } label: {
            Label("Eigener Zeitraum", systemImage: "calendar.badge.plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(isActive ? Color.orange : Color(.systemBackground))
                .foregroundStyle(isActive ? .white : Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isActive ? Color.clear : Color.orange.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}
