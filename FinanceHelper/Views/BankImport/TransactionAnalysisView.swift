import SwiftUI
import SwiftData
import Charts

struct TransactionAnalysisView: View {
    let transactions: [BankTransaction]   // used for new import preview
    let bank: BankFormat
    var isNewImport: Bool = false
    var customTitle: String? = nil
    var importedBatch: ImportBatch? = nil  // set when viewing an existing saved batch
    var truncatedFrom: Int? = nil          // original count before free-tier truncation
    var onImportComplete: (() -> Void)? = nil  // called on "Fertig" after save to dismiss all sheets

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("active_profile_id") private var activeProfileID: String = ""

    @Query private var allAccounts: [Account]
    @State private var selectedTab: AnalysisTab = .overview
    @State private var selectedCategory: TransactionCategory? = nil
    @State private var targetAccount: Account? = nil
    @State private var importBatchID = UUID().uuidString
    @State private var duplicateCount = 0
    @State private var savedCount = 0
    @State private var isSaved = false
    @State private var showingSaveSuccess = false
    @State private var editingImportedTx: ImportedTransaction? = nil
    @State private var isBulkEditing = false
    @State private var bulkSelectedIDs: Set<UUID> = []
    @State private var showingBulkCategoryPicker = false
    @State private var showingAddAccount = false
    @State private var isSaving = false
    @State private var saveProgress: Int = 0
    @Environment(PurchaseManager.self) private var purchases
    @Query(sort: \ImportedTransaction.date) private var allImportedTxQuery: [ImportedTransaction]
    @State private var showingPaywall = false

    enum AnalysisTab: String, CaseIterable {
        case overview   = "Übersicht"
        case categories = "Kategorien"
        case recurring  = "Wiederkehrend"
        case list       = "Alle"
    }

    // MARK: - Computed

    // Effective transactions for charts/stats: derived from batch OR raw passed-in array
    private var effectiveTransactions: [BankTransaction] {
        if let batch = importedBatch { return batch.transactions.map { $0.toBankTransaction() } }
        return transactions
    }

    private var profileAccounts: [Account] {
        allAccounts.filter { $0.profileID == activeProfileID }
    }

    private var expenseTransactions: [BankTransaction] {
        effectiveTransactions.filter { $0.isExpense && $0.category != .transfer }
    }
    private var incomeTransactions: [BankTransaction] {
        effectiveTransactions.filter { $0.isIncome && $0.category != .transfer }
    }
    private var totalIncome:   Double { incomeTransactions.reduce(0)  { $0 + $1.amount } }
    private var totalExpenses: Double { expenseTransactions.reduce(0) { $0 + $1.amount } }
    private var netFlow:       Double { totalIncome - totalExpenses }

    private var monthlyData: [(month: String, income: Double, expenses: Double)] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: effectiveTransactions.filter { $0.category != .transfer }) {
            cal.dateComponents([.year, .month], from: $0.date)
        }
        return grouped
            .map { key, txs in
                let inc = txs.filter(\.isIncome).reduce(0)  { $0 + $1.amount }
                let exp = txs.filter(\.isExpense).reduce(0) { $0 + $1.amount }
                let date = cal.date(from: key) ?? Date()
                let label = date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
                return (month: label, income: inc, expenses: exp)
            }
            .sorted { a, b in
                (monthDate(a.month) ?? .distantPast) < (monthDate(b.month) ?? .distantPast)
            }
    }

    private var categoryTotals: [(category: TransactionCategory, total: Double)] {
        let grouped = Dictionary(grouping: expenseTransactions) { $0.category }
        return grouped
            .map { cat, txs in (category: cat, total: txs.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    private var recurringPatterns: [RecurringPattern] {
        RecurringDetector.detect(in: effectiveTransactions)
    }

    private var filteredList: [BankTransaction] {
        if let cat = selectedCategory { return effectiveTransactions.filter { $0.category == cat } }
        return effectiveTransactions
    }

    // For editable batch mode
    private var filteredImportedList: [ImportedTransaction] {
        guard let batch = importedBatch else { return [] }
        if let cat = selectedCategory { return batch.transactions.filter { $0.category == cat } }
        return batch.transactions
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryBar
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                Divider()

                if isNewImport && !isSaved {
                    accountPickerBanner
                    Divider()
                }

                if let total = truncatedFrom {
                    HStack(spacing: 10) {
                        Image(systemName: "crown.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(String(format: NSLocalizedString("import_truncated_banner", comment: ""), 100, total))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            showingPaywall = true
                        } label: {
                            Text(NSLocalizedString("upgrade_to_premium", comment: ""))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.1))
                    Divider()
                }

                Picker("", selection: $selectedTab) {
                    ForEach(AnalysisTab.allCases, id: \.self) { tab in
                        Text(LocalizedStringKey(tab.rawValue)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()

                ScrollView {
                    switch selectedTab {
                    case .overview:   overviewContent
                    case .categories: categoriesContent
                    case .recurring:  recurringContent
                    case .list:       listContent
                    }
                }

                // Bulk action bar — sits outside ScrollView so it stays pinned at bottom
                if isBulkEditing && !bulkSelectedIDs.isEmpty {
                    bulkActionBar
                }
            }
            .navigationTitle(customTitle ?? bank.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isNewImport && !isSaved {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                            .foregroundStyle(.primary)
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            HStack(spacing: 6) {
                                ProgressView()
                                Text("\(saveProgress)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        } else {
                            Button("Importieren") { Task { await saveTransactions() } }
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .disabled(targetAccount == nil)
                        }
                    }
                } else if isNewImport && isSaved {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Label("Importiert", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline.weight(.medium))
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { onImportComplete?(); dismiss() }
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .alert("Importiert", isPresented: $showingSaveSuccess) {
                Button("Fertig") { onImportComplete?(); dismiss() }
                Button("Weiter ansehen", role: .cancel) {}
            } message: {
                let skipped = transactions.count - savedCount
                if skipped > 0 {
                    Text(String(format: NSLocalizedString("import_success_fmt", comment: ""), savedCount, skipped))
                } else {
                    Text(String(format: NSLocalizedString("import_assigned_fmt", comment: ""), savedCount, targetAccount?.name ?? ""))
                }
            }
            .onChange(of: targetAccount) { _, account in
                if let account { computeDuplicates(for: account) } else { duplicateCount = 0 }
            }
            .sheet(isPresented: Binding(
                get: { editingImportedTx != nil },
                set: { if !$0 { editingImportedTx = nil } }
            )) {
                if let tx = editingImportedTx {
                    CategoryPickerSheet(transaction: tx)
                        .presentationDetents([.medium])
                }
            }
            .sheet(isPresented: $showingBulkCategoryPicker) {
                BulkCategoryPickerSheet(count: bulkSelectedIDs.count) { category in
                    applyBulkCategory(category)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingAddAccount) {
                AddEditAccountView()
                    .onDisappear {
                        // Auto-select the newest account (just created) if nothing selected yet
                        if targetAccount == nil {
                            targetAccount = profileAccounts.last
                        }
                    }
            }
            .fullScreenCover(isPresented: $showingPaywall) {
                PaywallView().environment(purchases)
            }
            .onChange(of: selectedTab) {
                isBulkEditing = false
                bulkSelectedIDs = []
            }
        }
    }

    // MARK: - Account Picker Banner

    private var accountPickerBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.subheadline).foregroundStyle(.blue)
                Text("Konto:").font(.subheadline)
                Spacer()
                Menu {
                    ForEach(profileAccounts) { account in
                        Button { targetAccount = account } label: {
                            Label(account.name, systemImage: account.effectiveSystemImage)
                        }
                    }
                    Section {
                        Button { showingAddAccount = true } label: {
                            Label("Neues Konto erstellen …", systemImage: "plus.circle")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(targetAccount?.name ?? NSLocalizedString("Konto wählen…", comment: ""))
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .foregroundStyle(targetAccount != nil ? Color.primary : Color.blue)
                }
            }
            .padding(.horizontal).padding(.vertical, 10)

            if duplicateCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                    Text(String(format: NSLocalizedString("%lld Duplikate erkannt – werden beim Import übersprungen", comment: ""), duplicateCount))
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal).padding(.bottom, 8)
            }
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Save

    // O(1) duplicate key
    private struct TxKey: Hashable {
        let date: Date; let amount: Double
    }

    private func computeDuplicates(for account: Account) {
        let existingKeys = Set(account.importedTransactions.map {
            TxKey(date: $0.date, amount: $0.rawAmount)
        })
        duplicateCount = transactions.filter {
            existingKeys.contains(TxKey(date: $0.date, amount: $0.rawAmount))
        }.count
    }

    @MainActor
    private func saveTransactions() async {
        guard let account = targetAccount else { return }
        isSaving = true
        saveProgress = 0

        let existingKeys = Set(account.importedTransactions.map {
            TxKey(date: $0.date, amount: $0.rawAmount)
        })

        let existingProfileCount = allImportedTxQuery.filter { $0.profileID == activeProfileID }.count
        let insertLimit = purchases.isPremium ? Int.max : max(0, 100 - existingProfileCount)

        var inserted = 0
        var newImports: [ImportedTransaction] = []
        for (i, tx) in transactions.enumerated() {
            guard inserted < insertLimit else { break }
            guard !existingKeys.contains(TxKey(date: tx.date, amount: tx.rawAmount)) else { continue }
            let imported = ImportedTransaction(from: tx, bank: bank, profileID: activeProfileID, batchID: importBatchID)
            imported.account = account
            modelContext.insert(imported)
            newImports.append(imported)
            inserted += 1
            saveProgress = inserted

            // Yield every 300 inserts so the main thread stays responsive
            if i % 300 == 0 { await Task.yield() }
        }

        // Re-apply custom rules with the correct account ID now that it is known.
        // This picks up account-scoped rules that couldn't fire during initial parsing.
        let rules = CustomRulesStore.load().sorted { $0.isAmountFiltered && !$1.isAmountFiltered }
        if !rules.isEmpty {
            for tx in newImports {
                for rule in rules {
                    guard rule.matches(merchant: tx.merchantName, amount: tx.amount,
                                       accountID: account.id, userNote: tx.userNote) else { continue }
                    if let cat = rule.category {
                        tx.category = cat
                        tx.customCategoryID = nil
                    }
                    break
                }
            }
        }

        // Apply note rules — set user notes (and note-triggered category) for known merchants.
        let noteRules = NoteRulesStore.load()
        if !noteRules.isEmpty {
            for tx in newImports {
                guard let rule = noteRules.first(where: { $0.matches(merchant: tx.merchantName, amount: tx.amount) }) else { continue }
                tx.userNote = rule.noteText
                let noteCat = Categorizer.categorizeByMerchant(rule.noteText, amount: tx.amount, accountID: account.id)
                if noteCat != .sonstiges { tx.category = noteCat }
            }
        }

        savedCount = inserted
        isSaving = false
        if !purchases.isPremium {
            let newTotal = allImportedTxQuery.filter { $0.profileID == activeProfileID }.count
            if newTotal >= 100 { showingPaywall = true }
        }
        isSaved = true
        showingSaveSuccess = true
    }

    // MARK: - Summary bar

    private var summaryBar: some View {
        HStack(spacing: 0) {
            summaryCell(label: "Einnahmen", amount: totalIncome,   color: .green)
            Divider().frame(height: 36)
            summaryCell(label: "Ausgaben",  amount: totalExpenses, color: .red)
            Divider().frame(height: 36)
            summaryCell(label: "Netto",     amount: netFlow,       color: netFlow >= 0 ? .green : .red)
        }
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func summaryCell(label: LocalizedStringKey, amount: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(amount, format: .currency(code: "CHF").notation(.compactName))
                .font(.subheadline.weight(.bold)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }

    // MARK: - Overview

    private var overviewContent: some View {
        VStack(spacing: 16) {
            if !monthlyData.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Monatlicher Verlauf")
                        .font(.subheadline.weight(.semibold)).padding(.horizontal)

                    Chart {
                        ForEach(monthlyData, id: \.month) { row in
                            BarMark(x: .value("Monat", row.month), y: .value("Einnahmen", row.income))
                                .foregroundStyle(Color.green.opacity(0.75)).cornerRadius(3)
                            BarMark(x: .value("Monat", row.month), y: .value("Ausgaben", -row.expenses))
                                .foregroundStyle(Color.red.opacity(0.65)).cornerRadius(3)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { v in
                            AxisGridLine().foregroundStyle(Color.secondary.opacity(0.1))
                            if let val = v.as(Double.self) {
                                AxisValueLabel {
                                    Text(abs(val), format: .number.notation(.compactName))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in AxisValueLabel().font(.caption2).foregroundStyle(.secondary) }
                    }
                    .frame(height: 180).padding(.horizontal)

                    HStack(spacing: 16) {
                        Label("Einnahmen", systemImage: "square.fill").foregroundStyle(.green)
                        Label("Ausgaben",  systemImage: "square.fill").foregroundStyle(.red)
                    }
                    .font(.caption2).padding(.horizontal)
                }
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }

            if let first = effectiveTransactions.last?.date, let last = effectiveTransactions.first?.date {
                HStack {
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                    Text("\(first.formatted(.dateTime.day().month().year())) – \(last.formatted(.dateTime.day().month().year()))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(effectiveTransactions.count) Transaktionen")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Categories

    private var categoriesContent: some View {
        VStack(spacing: 0) {
            ForEach(categoryTotals, id: \.category) { item in
                let pct = totalExpenses > 0 ? item.total / totalExpenses : 0
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(item.category.color.opacity(0.15)).frame(width: 34, height: 34)
                            Image(systemName: item.category.systemImage)
                                .font(.caption.weight(.medium)).foregroundStyle(item.category.color)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.category.localizedName).font(.subheadline.weight(.medium))
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.secondary.opacity(0.12)).frame(height: 4)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(item.category.color.opacity(0.7))
                                        .frame(width: geo.size.width * CGFloat(pct), height: 4)
                                }
                            }
                            .frame(height: 4)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(item.total, format: .currency(code: "CHF")
                                .notation(.compactName).precision(.fractionLength(0...1)))
                                .font(.subheadline.weight(.semibold))
                            Text(String(format: "%.0f%%", pct * 100))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    Divider().padding(.leading, 62)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Recurring

    private var recurringContent: some View {
        VStack(spacing: 0) {
            if recurringPatterns.isEmpty {
                ContentUnavailableView(
                    "Keine wiederkehrenden Ausgaben",
                    systemImage: "repeat.circle",
                    description: Text("Für die Erkennung werden mindestens 2 Monate benötigt.")
                )
                .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Erkannte wiederkehrende Ausgaben")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.top, 16)
                    Text(String(format: NSLocalizedString("Ø Betrag über %lld Monate", comment: ""), recurringPatterns.first.map { $0.occurrences } ?? 0))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.horizontal, 16).padding(.bottom, 8)
                }
                ForEach(recurringPatterns) { pattern in
                    RecurringPatternRow(pattern: pattern)
                    Divider().padding(.leading, 62)
                }
            }
        }
    }

    // MARK: - Transaction list

    private var listContent: some View {
        LazyVStack(spacing: 0) {
            categoryFilterChips

            if importedBatch != nil {
                ForEach(filteredImportedList) { tx in
                    editableRow(tx)
                    Divider().padding(.leading, 52)
                }
            } else {
                ForEach(filteredList) { tx in
                    TransactionRow(transaction: tx)
                    Divider().padding(.leading, 52)
                }
            }
        }
    }

    private var categoryFilterChips: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let totalCount = importedBatch != nil
                        ? importedBatch!.transactions.count
                        : effectiveTransactions.count
                    filterChip(label: String(format: NSLocalizedString("Alle (%lld)", comment: ""), totalCount), isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(TransactionCategory.allCases) { cat in
                        let count = importedBatch != nil
                            ? importedBatch!.transactions.filter { $0.category == cat }.count
                            : effectiveTransactions.filter { $0.category == cat }.count
                        if count > 0 {
                            filterChip(label: "\(cat.localizedName) (\(count))", isSelected: selectedCategory == cat) {
                                selectedCategory = (selectedCategory == cat) ? nil : cat
                            }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }

            // Edit / bulk-select controls (only when viewing a saved batch)
            if importedBatch != nil {
                Divider().frame(height: 24).padding(.vertical, 8)
                if isBulkEditing {
                    Button {
                        let all = Set(filteredImportedList.map(\.id))
                        bulkSelectedIDs = bulkSelectedIDs.count == filteredImportedList.count ? [] : all
                    } label: {
                        Group {
                            if bulkSelectedIDs.count == filteredImportedList.count {
                                Text("Keine")
                            } else {
                                Text("Alle")
                            }
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 10)

                    Button {
                        isBulkEditing = false
                        bulkSelectedIDs = []
                    } label: {
                        Text("Fertig").font(.caption.weight(.semibold)).foregroundStyle(.blue)
                    }
                    .padding(.trailing, 12)
                } else {
                    Button {
                        isBulkEditing = true
                    } label: {
                        Text("Bearbeiten").font(.caption.weight(.semibold)).foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .background(Color(.systemBackground))
    }

    // Editable row for existing ImportedTransactions
    private func editableRow(_ tx: ImportedTransaction) -> some View {
        let isSelected = bulkSelectedIDs.contains(tx.id)
        return Button {
            if isBulkEditing {
                if isSelected { bulkSelectedIDs.remove(tx.id) } else { bulkSelectedIDs.insert(tx.id) }
            } else {
                editingImportedTx = tx
            }
        } label: {
            HStack(spacing: 12) {
                // Bulk checkbox
                if isBulkEditing {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.4))
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                }

                ZStack {
                    Circle().fill(tx.category.color.opacity(0.12)).frame(width: 36, height: 36)
                    Image(systemName: tx.category.systemImage)
                        .font(.caption.weight(.medium)).foregroundStyle(tx.category.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tx.merchantName)
                        .font(.subheadline.weight(.medium)).lineLimit(1).foregroundStyle(.primary)
                    Text(tx.date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(tx.rawAmount, format: .currency(code: tx.currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tx.isIncome ? Color.green : Color.primary)
                    if !isBulkEditing {
                        HStack(spacing: 3) {
                            Text(tx.category.localizedName)
                                .font(.caption2).foregroundStyle(tx.category.color)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 7)).foregroundStyle(.tertiary)
                        }
                    } else {
                        Text(tx.category.rawValue)
                            .font(.caption2).foregroundStyle(tx.category.color)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(isSelected && isBulkEditing ? Color.blue.opacity(0.05) : Color.clear)
            .animation(.easeInOut(duration: 0.1), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bulk edit

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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private func applyBulkCategory(_ category: TransactionCategory) {
        guard let batch = importedBatch else { return }
        for tx in batch.transactions where bulkSelectedIDs.contains(tx.id) {
            tx.category = category
        }
        bulkSelectedIDs = []
        isBulkEditing = false
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func monthDate(_ label: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM yy"
        fmt.locale = Locale.current
        return fmt.date(from: label)
    }
}

// MARK: - Category picker sheet

private struct CategoryPickerSheet: View {
    let transaction: ImportedTransaction
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(transaction.merchantName)
                                .font(.subheadline.weight(.semibold))
                            Text(transaction.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(transaction.rawAmount, format: .currency(code: transaction.currencyCode))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(transaction.isIncome ? Color.green : Color.primary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Kategorie wählen") {
                    ForEach(TransactionCategory.allCases, id: \.self) { cat in
                        Button {
                            transaction.category = cat
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: cat.systemImage)
                                    .foregroundStyle(cat.color).frame(width: 24, alignment: .center)
                                Text(cat.localizedName).foregroundStyle(Color.primary)
                                Spacer()
                                if transaction.category == cat {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue).fontWeight(.semibold)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Kategorie ändern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Bulk category picker sheet

private struct BulkCategoryPickerSheet: View {
    let count: Int
    let onSelect: (TransactionCategory) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(String(format: NSLocalizedString("Kategorie für %lld Transaktionen", comment: ""), count)) {
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
            }
            .navigationTitle("\(count) Transaktionen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Recurring Pattern Row

private struct RecurringPatternRow: View {
    let pattern: RecurringPattern

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(pattern.category.color.opacity(0.15)).frame(width: 34, height: 34)
                Image(systemName: pattern.category.systemImage)
                    .font(.caption.weight(.medium)).foregroundStyle(pattern.category.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(pattern.merchantName).font(.subheadline.weight(.medium)).lineLimit(1)
                Text("\(pattern.occurrences)× in \(pattern.occurrences) Monaten")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(pattern.averageAmount, format: .currency(code: "CHF")
                    .notation(.compactName).precision(.fractionLength(0...1)))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                Text("Ø / Monat").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Transaction Row (read-only)

private struct TransactionRow: View {
    let transaction: BankTransaction

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(transaction.category.color.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: transaction.category.systemImage)
                    .font(.caption.weight(.medium)).foregroundStyle(transaction.category.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchantName).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(transaction.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(transaction.rawAmount, format: .currency(code: transaction.currencyCode))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(transaction.isIncome ? Color.green : Color.primary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
