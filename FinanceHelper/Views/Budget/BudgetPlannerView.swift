import SwiftUI
import SwiftData
import Charts

// MARK: - Shared data type

struct BudgetFlowItem: Identifiable {
    var id: String { name }
    let name: String
    let amount: Double
    let color: Color
}

struct BudgetGroupItem: Identifiable {
    var id: String { group.rawValue }
    let group: BudgetCategoryGroup
    let name: String
    let amount: Double
    let color: Color
}

private enum SummaryTileCategory: String, Identifiable {
    case expenses, savings, investments
    var id: String { rawValue }
}

private struct TileDetailEntry: Identifiable {
    let id: UUID
    let name: String
    let symbolName: String
    let color: Color
    let amount: Double
    let recurrenceLabel: String
}

// MARK: - Display mode

private enum BudgetDisplayMode: Equatable {
    case average, yearly, specific

    var label: String {
        switch self {
        case .average:  return "Ø Monat"
        case .yearly:   return NSLocalizedString("period_yearly", comment: "")
        case .specific: return NSLocalizedString("period_monthly", comment: "")
        }
    }
}

// MARK: - Sheet enum

private enum BudgetSheet: Identifiable {
    case addEntry
    case editEntry(BudgetEntry)
    case budgetViz

    var id: String {
        switch self {
        case .addEntry:  return "addEntry"
        case .editEntry: return "editEntry"
        case .budgetViz: return "budgetViz"
        }
    }
}

// MARK: - Budget category colors (aligned with WealthBucketsView palette)

private extension Color {
    static let budgetExpense    = Color(red: 0.73, green: 0.22, blue: 0.22) // muted red  — matches debtColor
    static let budgetSavings    = Color(red: 0.22, green: 0.47, blue: 0.85) // corporate blue — matches liquidColor
    static let budgetInvestment = Color(red: 0.07, green: 0.53, blue: 0.47) // petrol/teal — matches investmentColor
}

// MARK: - Main View

struct BudgetPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchases
    @Query(sort: \BudgetEntry.createdAt) private var allEntriesRaw: [BudgetEntry]
    @Query(sort: \ImportedTransaction.date) private var allImportedTransactionsRaw: [ImportedTransaction]
    @AppStorage("active_profile_id") private var activeProfileID: String = ""

    @AppStorage("default_currency") private var defaultCurrency = "EUR"
    @AppStorage("bg_theme") private var rawTheme = BackgroundTheme.emerald.rawValue
    @State private var activeSheet: BudgetSheet? = nil

    private var themeAccent: Color { BackgroundTheme(rawValue: rawTheme)?.primary ?? .blue }
    @State private var showingPaywall = false
    @State private var showingSettings = false
    @State private var showingAccounts = false
    @State private var showingFAB = false
    @State private var showInactive = false
    @State private var displayMode: BudgetDisplayMode = .specific
    @State private var selectedBudgetMonth: Date = {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return Calendar.current.date(from: c) ?? Date()
    }()
    @State private var tappedSummaryTile: SummaryTileCategory? = nil
    @State private var showingMonthPicker = false
    @State private var showingDeviations = false
    @State private var pendingHintAction: HintAction? = nil
    @State private var dismissedHintsSet: Set<String> = []

    private var dismissedHintsKey: String { "dismissed_hints_\(activeProfileID)" }
    
    private func loadDismissedHints() {
        let raw = UserDefaults.standard.string(forKey: dismissedHintsKey) ?? ""
        // Use semicolon to safely handle categories with commas (like Restaurant)
        dismissedHintsSet = Set(raw.split(separator: ";").map(String.init))
    }
    
    private func dismissHint(_ id: String) {
        dismissedHintsSet.insert(id)
        UserDefaults.standard.set(dismissedHintsSet.joined(separator: ";"), forKey: dismissedHintsKey)
    }

    private var allEntries: [BudgetEntry] { allEntriesRaw.filter { $0.profileID == activeProfileID } }

    private var primaryCurrency: String { defaultCurrency }

    private func convert(_ amount: Double, from: String, to: String) -> Double {
        CurrencyService.shared.convert(amount, from: from, to: to)
    }

    private func entryMonthlyAmount(_ entry: BudgetEntry) -> Double {
        convert(entry.effectiveMonthlyAmount, from: entry.account?.currency ?? primaryCurrency, to: primaryCurrency)
    }

    private func entryAmountForMonthRaw(_ entry: BudgetEntry, monthStart: Date) -> Double {
        let cal = Calendar.current
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let monthNum = cal.component(.month, from: monthStart)
        var base: Double
        switch entry.recurrence {
        case .monthly:
            base = entry.amount
        case .once:
            guard entry.dueDate >= monthStart && entry.dueDate < monthEnd else { return 0 }
            base = entry.amount
        case .quarterly, .semiannual, .yearly:
            guard let nextDue = entry.nextDueDate(after: monthStart), nextDue < monthEnd else { return 0 }
            base = entry.amount
        }
        if entry.isIncomeEntry {
            if entry.bonus13Enabled {
                let months = entry.bonus13Months
                if !months.isEmpty && months.contains(monthNum) {
                    base += entry.amount / Double(months.count)
                }
            }
            if entry.bonusFixedEnabled && entry.bonusFixedMonth == monthNum {
                base += entry.bonusFixedAmount
            }
        }
        return base
    }

    private func entryAmountForMonth(_ entry: BudgetEntry, monthStart: Date) -> Double {
        let curr = entry.account?.currency ?? primaryCurrency
        return convert(entryAmountForMonthRaw(entry, monthStart: monthStart), from: curr, to: primaryCurrency)
    }

    private func entryOccursInMonth(_ entry: BudgetEntry, monthStart: Date) -> Bool {
        let cal = Calendar.current
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        switch entry.recurrence {
        case .monthly: return true
        case .once:    return entry.dueDate >= monthStart && entry.dueDate < monthEnd
        case .quarterly, .semiannual, .yearly:
            guard let nextDue = entry.nextDueDate(after: monthStart) else { return false }
            return nextDue < monthEnd
        }
    }

    private func entryAmountForPeriod(_ entry: BudgetEntry) -> Double {
        switch displayMode {
        case .average:  return entryMonthlyAmount(entry)
        case .yearly:   return entryMonthlyAmount(entry) * 12.0
        case .specific: return entryAmountForMonth(entry, monthStart: selectedBudgetMonth)
        }
    }

    private func periodEntries(from list: [BudgetEntry]) -> [BudgetEntry] {
        guard displayMode == .specific else { return list }
        return list.filter { entryOccursInMonth($0, monthStart: selectedBudgetMonth) }
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedBudgetMonth, equalTo: Date(), toGranularity: .month)
    }

    private func navigateBudgetMonth(_ offset: Int) {
        selectedBudgetMonth = Calendar.current.date(byAdding: .month, value: offset, to: selectedBudgetMonth) ?? selectedBudgetMonth
    }

    private var selectedMonthLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        fmt.locale = Locale.current
        return fmt.string(from: selectedBudgetMonth)
    }

    private var displayedEntries: [BudgetEntry] {
        showInactive ? allEntries : allEntries.filter(\.isActive)
    }

    private var incomeEntries: [BudgetEntry] {
        allEntries.filter { $0.isIncomeEntry }.sorted { $0.displayName < $1.displayName }
    }

    private var savingsEntries: [BudgetEntry] {
        allEntries.filter { $0.isSavingsEntry && !$0.isInvestmentEntry }.sorted { $0.displayName < $1.displayName }
    }

    private var investmentEntries: [BudgetEntry] {
        allEntries.filter { $0.isInvestmentEntry }.sorted { $0.displayName < $1.displayName }
    }

    private var transferEntries: [BudgetEntry] {
        allEntries.filter { $0.transferToAccount != nil }.sorted { entryMonthlyAmount($0) > entryMonthlyAmount($1) }
    }

    /// The effective CategoryGroup of an entry, respecting the user-defined category's group when set.
    private func entryGroup(_ entry: BudgetEntry) -> CategoryGroup {
        entry.userCategory.map { $0.group } ?? entry.category.group
    }

    private var debtEntries: [BudgetEntry] {
        allEntries.filter {
            $0.transferToAccount == nil && !$0.isIncomeEntry && !$0.isSavingsEntry &&
            entryGroup($0) == .schulden
        }.sorted { entryMonthlyAmount($0) > entryMonthlyAmount($1) }
    }

    private var fixkostenEntries: [BudgetEntry] {
        allEntries.filter {
            $0.transferToAccount == nil && !$0.isIncomeEntry && !$0.isSavingsEntry &&
            entryGroup($0) == .fixkosten
        }.sorted { entryMonthlyAmount($0) > entryMonthlyAmount($1) }
    }

    private var lifestyleEntries: [BudgetEntry] {
        allEntries.filter { entry in
            guard !entry.isIncomeEntry && !entry.isSavingsEntry && entry.transferToAccount == nil else { return false }
            return entryGroup(entry) == .lifestyle
        }.sorted { entryMonthlyAmount($0) > entryMonthlyAmount($1) }
    }

    private var periodIncome: Double {
        displayedEntries.filter { $0.isIncomeEntry }.reduce(0) { $0 + entryAmountForPeriod($1) }
    }

    // Transfer to a liquid savings account (Sparkonto, Tagesgeld, Festgeld)
    private func isSavingsTransfer(_ entry: BudgetEntry) -> Bool {
        guard let dest = entry.transferToAccount else { return false }
        return dest.type == .sparkonto || dest.type == .tagesgeld || dest.type == .festgeld
    }

    // Transfer to an investment account (Depot, Investment, Krypto, Altersvorsorge)
    private func isInvestmentTransfer(_ entry: BudgetEntry) -> Bool {
        guard let dest = entry.transferToAccount else { return false }
        return dest.type.isInvestment
    }

    private var periodSavingsOnly: Double {
        displayedEntries.filter { ($0.isSavingsEntry && !$0.isInvestmentEntry) || isSavingsTransfer($0) }
            .reduce(0) { $0 + entryAmountForPeriod($1) }
    }

    private var periodInvestments: Double {
        displayedEntries.filter { $0.isInvestmentEntry || isInvestmentTransfer($0) }
            .reduce(0) { $0 + entryAmountForPeriod($1) }
    }

    private var periodSavings: Double { periodSavingsOnly + periodInvestments }

    private var periodExpenses: Double {
        displayedEntries.filter { !$0.isIncomeEntry && !$0.isSavingsEntry && $0.transferToAccount == nil }.reduce(0) { $0 + entryAmountForPeriod($1) }
    }

    private var expensePieItems: [BudgetFlowItem] {
        outflowGroupData.map { BudgetFlowItem(name: $0.name, amount: $0.amount, color: $0.color) }
    }

    private var sankeyIncomeItems: [(name: String, amount: Double, color: Color)] {
        var groups: [String: (Double, Color)] = [:]
        for entry in displayedEntries where entry.isIncomeEntry {
            let key = entry.displayName
            groups[key] = ((groups[key]?.0 ?? 0) + entryAmountForPeriod(entry), entry.displayColor)
        }
        return groups.map { (name: $0.key, amount: $0.value.0, color: $0.value.1) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }

    private var sankeyExpenseItems: [(name: String, amount: Double, color: Color)] {
        outflowGroupData.map { (name: $0.name, amount: $0.amount, color: $0.color) }
    }

    // Groups all non-income outflows by CategoryGroup.
    private var outflowGroupData: [BudgetGroupItem] {
        var totals: [CategoryGroup: Double] = [:]
        for entry in displayedEntries where !entry.isIncomeEntry {
            let grp: CategoryGroup
            if entry.isInvestmentEntry || isInvestmentTransfer(entry) {
                grp = .investieren
            } else if entry.isSavingsEntry || isSavingsTransfer(entry) {
                grp = .sparen
            } else if entry.transferToAccount != nil {
                continue  // non-savings/investment transfers excluded
            } else {
                grp = entryGroup(entry)
            }
            totals[grp, default: 0] += entryAmountForPeriod(entry)
        }
        return CategoryGroup.allCases
            .compactMap { grp -> BudgetGroupItem? in
                guard grp != .einkommen && grp != .intern, let total = totals[grp], total > 0 else { return nil }
                return BudgetGroupItem(group: grp, name: grp.localizedName, amount: total, color: grp.color)
            }
            .sorted { $0.amount > $1.amount }
    }

    private var outflowGroupEntries: [CategoryGroup: [TileDetailEntry]] {
        var result: [CategoryGroup: [TileDetailEntry]] = [:]
        for entry in displayedEntries where !entry.isIncomeEntry {
            let grp: CategoryGroup
            if entry.isInvestmentEntry || isInvestmentTransfer(entry) {
                grp = .investieren
            } else if entry.isSavingsEntry || isSavingsTransfer(entry) {
                grp = .sparen
            } else if entry.transferToAccount != nil {
                continue
            } else {
                grp = entryGroup(entry)
            }
            result[grp, default: []].append(TileDetailEntry(
                id: entry.id,
                name: entry.displayName,
                symbolName: entry.displaySymbolName,
                color: entry.displayColor,
                amount: entryAmountForPeriod(entry),
                recurrenceLabel: entry.recurrenceDisplayLabel
            ))
        }
        for key in result.keys { result[key]?.sort { $0.amount > $1.amount } }
        return result
    }

    var body: some View {
        List {
            if !allEntries.isEmpty { heroTilesSection }

            if periodIncome > 0 || periodExpenses > 0 {
                budgetVizCard
            }

            if !profileDeviationTransactions.isEmpty && !allEntries.isEmpty {
                deviationsCard
            }

            let visibleHints = budgetSuggestions.filter { !dismissedHintsSet.contains($0.id) }
            if !visibleHints.isEmpty {
                budgetSuggestionsSection(hints: visibleHints)
            }

            if !incomeEntries.isEmpty { incomeSection }
            if !debtEntries.isEmpty { debtSection }
            if !fixkostenEntries.isEmpty { fixkostenSection }
            if !lifestyleEntries.isEmpty { lifestyleSection }
            if !savingsEntries.isEmpty { savingsSection }
            if !investmentEntries.isEmpty { investmentsSection }
            if !transferEntries.isEmpty { transfersSection }
            if allEntries.isEmpty { emptyStateSection }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AnimatedPatternBackground())
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                    .tint(.primary)
            }
            ToolbarItem(placement: .principal) { ProfilePill() }
            ToolbarItem(placement: .primaryAction) {
                Button { showingAccounts = true } label: { Image(systemName: "creditcard") }
                    .tint(.primary)
            }
        }
        .overlay {
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
        }
        .overlay(alignment: .bottomTrailing) {
            budgetFAB
                .padding(.trailing, 20)
                .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            stickyHeader
        }
        .fullScreenCover(item: $tappedSummaryTile) { tile in
            TileDetailSheet(
                title: tileTitle(for: tile),
                color: tileColor(for: tile),
                entries: tileEntries(for: tile),
                total: tileTotal(for: tile),
                currency: primaryCurrency
            )
        }
        .fullScreenCover(item: $activeSheet) { sheet in
            switch sheet {
            case .addEntry:
                AddEditBudgetEntryView()
            case .editEntry(let entry):
                AddEditBudgetEntryView(entry: entry)
            case .budgetViz:
                BudgetVizSheet(entries: displayedEntries, currency: primaryCurrency)
            }
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallView().environment(purchases)
        }
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showingAccounts) {
            AccountsView()
        }
        .sheet(isPresented: $showingMonthPicker) {
            MonthPickerSheet(selectedMonth: $selectedBudgetMonth)
        }
        .fullScreenCover(isPresented: $showingDeviations) {
            BudgetDeviationSheet(
                entries: allEntries.filter(\.isActive),
                transactions: profileDeviationTransactions,
                currency: primaryCurrency
            )
        }
        .fullScreenCover(item: $pendingHintAction) { action in
            AddEditBudgetEntryView(
                presetCategory: action.category,
                presetAmount: action.amount
            )
        }
        .onAppear { loadDismissedHints() }
        .onChange(of: activeProfileID) { loadDismissedHints() }
    }

    private func attemptAddEntry() {
        if !purchases.isPremium && allEntries.count >= 10 {
            showingPaywall = true
        } else {
            activeSheet = .addEntry
        }
    }

    // MARK: - Floating Action Button

    private var budgetFAB: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if showingFAB {
                VStack(spacing: 0) {
                    fabMenuItem(
                        label: "Eintrag hinzufügen",
                        sublabel: nil,
                        icon: "doc.badge.plus",
                        color: Color(.label)
                    ) {
                        showingFAB = false
                        attemptAddEntry()
                    }
                    Divider().padding(.leading, 52)
                    fabMenuItem(
                        label: "Konto hinzufügen",
                        sublabel: nil,
                        icon: "plus.rectangle",
                        color: Color(.label)
                    ) {
                        showingFAB = false
                        showingAccounts = true
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

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                    showingFAB.toggle()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(themeAccent)
                        .frame(width: 50, height: 50)
                        .shadow(color: themeAccent.opacity(0.4), radius: 10, x: 0, y: 4)
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

    // MARK: - Sticky Header

    private var stickyHeader: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                // Top row: Income + Month Navigation + Year
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(NSLocalizedString("income", comment: ""))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Text(periodIncome.formatted(.currency(code: primaryCurrency)))
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        // Year label top right
                        Text(Calendar.current.component(.year, from: selectedBudgetMonth).description)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())

                        if displayMode == .specific {
                            HStack(spacing: 8) {
                                Button { withAnimation(.spring(response: 0.3)) { navigateBudgetMonth(-1) } } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, height: 28)
                                        .background(Color.secondary.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showingMonthPicker = true
                                } label: {
                                    let monthName = Calendar.current.monthSymbols[Calendar.current.component(.month, from: selectedBudgetMonth)-1]
                                    VStack(spacing: 0) {
                                        Text(monthName)
                                            .font(.subheadline.weight(.bold))
                                            .lineLimit(1)
                                        if isCurrentMonth {
                                            Text("Aktuell")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    .frame(minWidth: 70)
                                }
                                .buttonStyle(.plain)

                                Button { withAnimation(.spring(response: 0.3)) { navigateBudgetMonth(1) } } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, height: 28)
                                        .background(Color.secondary.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 4)

                // Bottom row: Display Mode Picker
                HStack(spacing: 8) {
                    modeButton(mode: .specific, label: NSLocalizedString("period_monthly", comment: ""))
                    
                    HStack(spacing: 0) {
                        modeButton(mode: .average, label: "Ø Monat")
                        Divider().frame(height: 14).padding(.horizontal, 4)
                        modeButton(mode: .yearly, label: "Ø Jahr")
                    }
                    .background(
                        (displayMode == .average || displayMode == .yearly)
                            ? Color.primary.opacity(0.08)
                            : Color.secondary.opacity(0.05)
                    )
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.regularMaterial)

            Divider()
        }
    }

    private func modeButton(mode: BudgetDisplayMode, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { displayMode = mode }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(displayMode == mode ? Color.primary.opacity(0.08) : Color.clear)
                .foregroundStyle(displayMode == mode ? Color.primary : Color.secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hero Tiles Section

    private var heroTilesSection: some View {
        let surplus = periodIncome - periodSavings - periodExpenses
        let isPositive = surplus >= 0
        let surplusColor: Color = isPositive ? .green : .red
        return Section {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    summaryTile(label: NSLocalizedString("expenses", comment: ""), amount: periodExpenses, color: .budgetExpense) { tappedSummaryTile = .expenses }
                    summaryTile(label: NSLocalizedString("budget_category_savings", comment: ""), amount: periodSavingsOnly, color: .budgetSavings) { tappedSummaryTile = .savings }
                }
                HStack(spacing: 10) {
                    summaryTile(label: NSLocalizedString("investments", comment: ""), amount: periodInvestments, color: .budgetInvestment) { tappedSummaryTile = .investments }
                    surplusTile(surplus: surplus, color: surplusColor)
                }
            }
            .padding(.vertical, 10)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private func summaryTile(label: String, amount: Double, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color.opacity(0.45))
                }
                Text(amount.formatted(.currency(code: primaryCurrency)))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(ScalePressButtonStyle())
    }

    private func surplusTile(surplus: Double, color: Color) -> some View {
        let label = surplus >= 0 ? NSLocalizedString("surplus", comment: "") : NSLocalizedString("deficit", comment: "")
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text((surplus >= 0 ? "+" : "") + surplus.formatted(.currency(code: primaryCurrency)))
                .font(.headline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Tile detail helpers

    private func tileEntries(for tile: SummaryTileCategory) -> [TileDetailEntry] {
        let raw: [BudgetEntry]
        switch tile {
        case .expenses:
            raw = displayedEntries.filter { !$0.isIncomeEntry && !$0.isSavingsEntry && $0.transferToAccount == nil }
        case .savings:
            raw = displayedEntries.filter { ($0.isSavingsEntry && !$0.isInvestmentEntry) || isSavingsTransfer($0) }
        case .investments:
            raw = displayedEntries.filter { $0.isInvestmentEntry || isInvestmentTransfer($0) }
        }
        return raw.map { e in
            TileDetailEntry(
                id: e.id,
                name: e.displayName,
                symbolName: e.displaySymbolName,
                color: e.displayColor,
                amount: entryAmountForPeriod(e),
                recurrenceLabel: e.recurrence.localizedName
            )
        }.sorted { $0.amount > $1.amount }
    }

    private func tileTotal(for tile: SummaryTileCategory) -> Double {
        switch tile {
        case .expenses:    return periodExpenses
        case .savings:     return periodSavingsOnly
        case .investments: return periodInvestments
        }
    }

    private func tileTitle(for tile: SummaryTileCategory) -> String {
        switch tile {
        case .expenses:    return NSLocalizedString("expenses", comment: "")
        case .savings:     return NSLocalizedString("budget_category_savings", comment: "")
        case .investments: return NSLocalizedString("investments", comment: "")
        }
    }

    private func tileColor(for tile: SummaryTileCategory) -> Color {
        switch tile {
        case .expenses:    return .budgetExpense
        case .savings:     return .budgetSavings
        case .investments: return .budgetInvestment
        }
    }

    // MARK: - Budget Viz Card

    private var budgetVizCard: some View {
        let surplus = periodIncome - periodExpenses - periodSavings
        return Section {
            Button { activeSheet = .budgetViz } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(NSLocalizedString("budget_viz_title", comment: ""), systemImage: "chart.pie.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }

                    if periodIncome > 0 {
                        GeometryReader { geo in
                            let w = geo.size.width
                            let rawExp  = max(0, CGFloat(periodExpenses   / periodIncome))
                            let rawSav  = max(0, CGFloat(periodSavingsOnly / periodIncome))
                            let rawInv  = max(0, CGFloat(periodInvestments / periodIncome))
                            let rawSurp = max(0, CGFloat(surplus           / periodIncome))
                            let total   = rawExp + rawSav + rawInv + rawSurp
                            let norm    = total > 1.0 ? 1.0 / total : 1.0
                            let expFrac  = rawExp  * norm
                            let savFrac  = rawSav  * norm
                            let invFrac  = rawInv  * norm
                            let surpFrac = rawSurp * norm
                            HStack(spacing: 2) {
                                if expFrac  > 0.005 { RoundedRectangle(cornerRadius: 2).fill(Color.budgetExpense.opacity(0.75)).frame(width: w * expFrac  - 1, height: 10) }
                                if savFrac  > 0.005 { RoundedRectangle(cornerRadius: 2).fill(Color.budgetSavings.opacity(0.75)).frame(width: w * savFrac  - 1, height: 10) }
                                if invFrac  > 0.005 { RoundedRectangle(cornerRadius: 2).fill(Color.budgetInvestment.opacity(0.75)).frame(width: w * invFrac  - 1, height: 10) }
                                if surpFrac > 0.005 { RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.35)).frame(width: w * surpFrac - 1, height: 10) }
                                Spacer(minLength: 0)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .frame(height: 10)
                    }

                    HStack(spacing: 0) {
                        if periodIncome > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("expenses", comment: "")).font(.caption2).foregroundStyle(.secondary)
                                Text(String(format: "%.0f%%", periodExpenses / periodIncome * 100))
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.budgetExpense).lineLimit(1)
                                    .contentTransition(.numericText())
                            }
                            if periodSavingsOnly > 0 {
                                Spacer()
                                VStack(alignment: .center, spacing: 2) {
                                    Text(NSLocalizedString("savings_rate", comment: "")).font(.caption2).foregroundStyle(.secondary)
                                    Text(String(format: "%.0f%%", periodSavingsOnly / periodIncome * 100))
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.budgetSavings).lineLimit(1)
                                        .contentTransition(.numericText())
                                }
                            }
                            if periodInvestments > 0 {
                                Spacer()
                                VStack(alignment: .center, spacing: 2) {
                                    Text(NSLocalizedString("investments", comment: "")).font(.caption2).foregroundStyle(.secondary)
                                    Text(String(format: "%.0f%%", periodInvestments / periodIncome * 100))
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.budgetInvestment).lineLimit(1)
                                        .contentTransition(.numericText())
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(surplus >= 0 ? NSLocalizedString("surplus", comment: "") : NSLocalizedString("deficit", comment: ""))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text((surplus >= 0 ? "+" : "") + String(format: "%.0f%%", surplus / periodIncome * 100))
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(surplus >= 0 ? .green : .red).lineLimit(1)
                                    .contentTransition(.numericText())
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        if periodExpenses > 0 { vizLegendDot(color: .budgetExpense, label: NSLocalizedString("expenses", comment: "")) }
                        if periodSavingsOnly > 0 { vizLegendDot(color: .budgetSavings, label: NSLocalizedString("budget_category_savings", comment: "")) }
                        if periodInvestments > 0 { vizLegendDot(color: .budgetInvestment, label: NSLocalizedString("investments", comment: "")) }
                        if surplus > 0 { vizLegendDot(color: .green.opacity(0.7), label: NSLocalizedString("surplus", comment: "")) }
                    }
                }
                .padding(14)
                .cardStyle(cornerRadius: 14)
            }
            .buttonStyle(ScalePressButtonStyle())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        } header: {
            Text(NSLocalizedString("budget_viz_title", comment: ""))
        }
    }

    private func vizLegendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Styled entry row helper

    @ViewBuilder
    private func styledEntryRow(_ entry: BudgetEntry) -> some View {
        BudgetEntryRow(
            entry: entry,
            defaultCurrency: primaryCurrency,
            yearlyMode: displayMode == .yearly,
            overrideAmount: (displayMode == .specific && entryOccursInMonth(entry, monthStart: selectedBudgetMonth))
                ? entryAmountForMonthRaw(entry, monthStart: selectedBudgetMonth) : nil,
            selectedMonth: displayMode == .specific ? selectedBudgetMonth : nil
        )
        .padding(12)
        .cardStyle(cornerRadius: 12)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .contentShape(Rectangle())
        .onTapGesture { activeSheet = .editEntry(entry) }
    }

    // MARK: - Income Section

    private var incomeSection: some View {
        let entries = incomeEntries
        return Section(NSLocalizedString("income_section", comment: "")) {
            ForEach(entries) { entry in styledEntryRow(entry) }
            .onDelete { offsets in withAnimation { offsets.forEach { modelContext.delete(entries[$0]) } } }
        }
    }

    // MARK: - Savings Section

    private var savingsSection: some View {
        let entries = savingsEntries
        return Section(NSLocalizedString("budget_category_savings", comment: "")) {
            ForEach(entries) { entry in styledEntryRow(entry) }
            .onDelete { offsets in withAnimation { offsets.forEach { modelContext.delete(entries[$0]) } } }
        }
    }

    // MARK: - Investments Section

    private var investmentsSection: some View {
        let entries = investmentEntries
        return Section(NSLocalizedString("investments", comment: "")) {
            ForEach(entries) { entry in styledEntryRow(entry) }
            .onDelete { offsets in withAnimation { offsets.forEach { modelContext.delete(entries[$0]) } } }
        }
    }

    // MARK: - Debt Section

    private var debtSection: some View {
        let entries = debtEntries
        return Section {
            ForEach(entries) { entry in styledEntryRow(entry) }
            .onDelete { offsets in withAnimation { offsets.forEach { modelContext.delete(entries[$0]) } } }
        } header: {
            Text(NSLocalizedString("budget_group_schulden", comment: ""))
        }
    }

    // MARK: - Fixkosten Section

    private var fixkostenSection: some View {
        let entries = fixkostenEntries
        return Section {
            ForEach(entries) { entry in styledEntryRow(entry) }
            .onDelete { offsets in withAnimation { offsets.forEach { modelContext.delete(entries[$0]) } } }
        } header: {
            Text(NSLocalizedString("budget_group_fixkosten", comment: ""))
        }
    }

    // MARK: - Lifestyle Section

    private var lifestyleSection: some View {
        let entries = lifestyleEntries
        return Section {
            ForEach(entries) { entry in styledEntryRow(entry) }
            .onDelete { offsets in withAnimation { offsets.forEach { modelContext.delete(entries[$0]) } } }
        } header: {
            Text(NSLocalizedString("budget_group_lifestyle", comment: ""))
        }
    }

    // MARK: - Transfers Section

    private var transfersSection: some View {
        let entries = transferEntries
        return Section(NSLocalizedString("transfer_section_header", comment: "")) {
            ForEach(entries) { entry in styledEntryRow(entry) }
            .onDelete { offsets in withAnimation { offsets.forEach { modelContext.delete(entries[$0]) } } }
        }
    }

    // MARK: - Empty State

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 14) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary.opacity(0.35))
                Text(NSLocalizedString("no_entries", comment: "")).font(.headline)
                Text(NSLocalizedString("no_entries_hint", comment: ""))
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Budget suggestions

    private struct BudgetHint: Identifiable {
        let id: String
        let icon: String
        let iconColor: Color
        let title: String
        let detail: String
        /// If set, tapping the hint opens AddEditBudgetEntryView prefilled with this category + amount.
        let presetCategory: BudgetCategory?
        let presetAmount: Double?
        /// Original transaction category for deep-linking
        let transactionCategory: TransactionCategory?

        var isActionable: Bool { presetCategory != nil }
    }

    private struct HintAction: Identifiable {
        let id = UUID()
        let category: BudgetCategory
        let amount: Double
    }

    /// All profile transactions (income + non-internal expenses), used for the deviation view.
    private var profileDeviationTransactions: [ImportedTransaction] {
        allImportedTransactionsRaw.filter {
            $0.profileID == activeProfileID && !$0.category.isInternal
        }
    }

    private var deviationsCard: some View {
        Section {
            Button { showingDeviations = true } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("Budget optimieren")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.indigo)
                            Text("TIPP")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(Color.indigo)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Text("Vergleiche dein Budget mit deinen echten Ausgaben")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.indigo.opacity(0.7))
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.indigo.opacity(0.14))
    }

    /// Profile-filtered, last-3-months imported transactions (used for analyse-based hints).
    private var recentTransactions: [ImportedTransaction] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        return allImportedTransactionsRaw.filter {
            $0.profileID == activeProfileID && $0.date >= cutoff && !$0.category.isInternal
        }
    }

    /// Per–transaction-category monthly averages from the last 3 months.
    /// Income categories use positive amounts only; expense categories use negative ones.
    private var txCategoryAverages: [TransactionCategory: Double] {
        var totals: [TransactionCategory: Double] = [:]
        for tx in recentTransactions {
            let cat = tx.category
            if cat == .einkommen {
                guard tx.isIncome else { continue }
            } else {
                guard tx.isExpense else { continue }
            }
            totals[cat, default: 0] += tx.amount
        }
        return totals.mapValues { $0 / 3.0 }
    }

    /// True if any existing active budget entry maps to the given TX category.
    private func hasBudgetEntry(for txCat: TransactionCategory) -> Bool {
        allEntries.contains { entry in
            guard entry.isActive else { return false }
            
            // 1. Check built-in category rollup
            if entry.userCategory == nil {
                return entry.category.rollsUpTo == txCat
            }
            
            // 2. Check user category for name matches
            if let uc = entry.userCategory {
                let name = uc.name.lowercased()
                let catName = txCat.rawValue.lowercased()
                if name.contains(catName) || catName.contains(name) { return true }
                
                // Special case for Restaurant/Dining
                if txCat == .restaurant && (name.contains("essen") || name.contains("ausgang")) {
                    return true
                }
            }
            
            return false
        }
    }

    private func totalPlannedFor(txCat: TransactionCategory) -> Double {
        allEntries.filter { entry in
            guard entry.isActive else { return false }
            if entry.userCategory == nil { return entry.category.rollsUpTo == txCat }
            if let uc = entry.userCategory {
                let name = uc.name.lowercased()
                let catName = txCat.rawValue.lowercased()
                return name.contains(catName) || catName.contains(name)
            }
            return false
        }.reduce(0) { $0 + entryMonthlyAmount($1) }
    }

    private var budgetSuggestions: [BudgetHint] {
        var hints: [BudgetHint] = []

        // --- Analyse-based per-category hints (Missing & Deviations) ---
        let averages = txCategoryAverages
        let ordered = averages.sorted { $0.value > $1.value }
        
        for (txCat, avg) in ordered {
            let roundedAvg = avg.rounded()
            guard roundedAvg >= 10 else { continue }
            
            let planned = totalPlannedFor(txCat: txCat)
            
            if planned == 0 {
                // Scenario: Missing entry
                let isIncome = txCat == .einkommen
                let title = isIncome
                    ? NSLocalizedString("Einkommen nicht geplant", comment: "")
                    : String(format: NSLocalizedString("Nicht geplant: %@", comment: ""), txCat.localizedName)
                let detail = String(format: NSLocalizedString("Ø %@/Monat laut Analyse. Als Eintrag anlegen?", comment: ""), roundedAvg.formatted(.currency(code: primaryCurrency).precision(.fractionLength(0))))
                hints.append(BudgetHint(
                    id: "analyse_\(txCat.rawValue)",
                    icon: txCat.systemImage,
                    iconColor: txCat.color,
                    title: title,
                    detail: detail,
                    presetCategory: txCat.suggestedBudgetCategory,
                    presetAmount: roundedAvg,
                    transactionCategory: txCat
                ))
            } else {
                // Scenario: Significant deviation
                let diff = abs(roundedAvg - planned)
                let pct = diff / planned
                
                if diff > 30 && pct > 0.15 { // Threshold: > 30 units AND > 15% deviation
                    hints.append(BudgetHint(
                        id: "deviation_\(txCat.rawValue)",
                        icon: "chart.bar.xaxis",
                        iconColor: .orange,
                        title: "Abweichung: \(txCat.rawValue)",
                        detail: "Geplant: \(planned.formatted(.currency(code: primaryCurrency).precision(.fractionLength(0)))). Analyse: Ø \(roundedAvg.formatted(.currency(code: primaryCurrency).precision(.fractionLength(0)))). Anpassen?",
                        presetCategory: txCat.suggestedBudgetCategory,
                        presetAmount: roundedAvg,
                        transactionCategory: txCat
                    ))
                }
            }
        }

        // --- Generic budget-health hints (only if entries exist) ---
        guard !allEntries.isEmpty else { return hints }

        if periodIncome > 0 && periodExpenses > periodIncome && savingsEntries.isEmpty && investmentEntries.isEmpty {
            hints.append(BudgetHint(id: "over_budget", icon: "exclamationmark.triangle", iconColor: .red,
                title: NSLocalizedString("Ausgaben übersteigen das Einkommen", comment: ""),
                detail: String(format: NSLocalizedString("Deine geplanten Ausgaben (%@) sind höher als dein Einkommen.", comment: ""), periodExpenses.formatted(.currency(code: primaryCurrency).precision(.fractionLength(0)))),
                presetCategory: nil, presetAmount: nil, transactionCategory: nil))
        }

        if periodIncome > 0 && (periodSavings / periodIncome) < 0.1 && !incomeEntries.isEmpty {
            hints.append(BudgetHint(id: "low_savings_rate", icon: "chart.line.uptrend.xyaxis", iconColor: .orange,
                title: NSLocalizedString("Sparquote unter 10%", comment: ""),
                detail: String(format: NSLocalizedString("Empfehlung: mindestens 10–20%% des Einkommens sparen oder investieren. Aktuell: %lld%%.", comment: ""), Int((periodSavings / periodIncome) * 100)),
                presetCategory: nil, presetAmount: nil, transactionCategory: nil))
        }

        if debtEntries.isEmpty == false && periodIncome > 0 {
            let debtTotal = debtEntries.reduce(0.0) { $0 + entryAmountForPeriod($1) }
            if debtTotal / periodIncome > 0.3 {
                hints.append(BudgetHint(id: "high_debt", icon: "creditcard.trianglebadge.exclamationmark", iconColor: .red,
                    title: NSLocalizedString("Hohe Schuldenlast", comment: ""),
                    detail: NSLocalizedString("Deine Schuldenrückzahlungen machen über 30% deines Einkommens aus. Das kann die finanzielle Flexibilität einschränken.", comment: ""),
                    presetCategory: nil, presetAmount: nil, transactionCategory: nil))
            }
        }

        return hints
    }

    private func budgetSuggestionsSection(hints: [BudgetHint]) -> some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(hints) { hint in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                ZStack {
                                    Circle().fill(hint.iconColor.opacity(0.12)).frame(width: 32, height: 32)
                                    Image(systemName: hint.icon)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(hint.iconColor)
                                }
                                Spacer()
                                Button {
                                    withAnimation { dismissHint(hint.id) }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .padding(6)
                                        .background(Color.secondary.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hint.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(hint.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            Spacer(minLength: 0)
                            
                            if hint.isActionable {
                                HStack(spacing: 8) {
                                    Button {
                                        if let cat = hint.presetCategory, let amt = hint.presetAmount {
                                            pendingHintAction = HintAction(category: cat, amount: amt)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle.fill")
                                            Text("Anlegen")
                                        }
                                        .font(.caption2.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(hint.iconColor.opacity(0.15))
                                        .foregroundStyle(hint.iconColor)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if let txCat = hint.transactionCategory {
                                        Button {
                                            NavigationRouter.shared.jumpToAnalyse(with: txCat)
                                        } label: {
                                            Image(systemName: "list.bullet.indent")
                                                .font(.caption2.weight(.bold))
                                                .frame(width: 36, height: 32)
                                                .background(Color.secondary.opacity(0.1))
                                                .foregroundStyle(.primary)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .frame(width: 180, height: 160)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 2)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            HStack {
                Image(systemName: "lightbulb.fill").foregroundStyle(.primary)
                Text("Hinweise")
            }
        }
    }
}

// MARK: - Budget Deviation Sheet

private struct BudgetDeviationSheet: View {
    let entries: [BudgetEntry]
    let transactions: [ImportedTransaction]
    let currency: String
    @Environment(\.dismiss) private var dismiss
    @State private var pendingCreate: CreateAction? = nil
    @State private var lookbackMonths: Int = 12
    @State private var pendingAnalyseCategory: TransactionCategory? = nil
    @State private var categoryAvgCache: [TransactionCategory: Double]? = nil

    private var filteredTransactions: [ImportedTransaction] {
        guard let cutoff = Calendar.current.date(byAdding: .month, value: -lookbackMonths, to: Date()) else {
            return transactions
        }
        return transactions.filter { $0.date >= cutoff }
    }

    struct CreateAction: Identifiable {
        let id = UUID()
        let category: BudgetCategory
        let amount: Double
    }

    private func convert(_ amount: Double, from: String) -> Double {
        CurrencyService.shared.convert(amount, from: from, to: currency)
    }

    private func entryMonthlyAmount(_ entry: BudgetEntry) -> Double {
        convert(entry.effectiveMonthlyAmount, from: entry.account?.currency ?? currency)
    }

    private var monthCount: Int {
        let cal = Calendar.current
        let keys = Set(filteredTransactions.map { tx -> String in
            let c = cal.dateComponents([.year, .month], from: tx.date)
            return "\(c.year ?? 0)-\(c.month ?? 0)"
        })
        return max(1, keys.count)
    }

    // Expense: average per month the category appears. Income: modal bucket in upper range.
    // Called from a background Task; takes a snapshot to avoid main-thread data races.
    private func computeCategoryAvg(txs: [ImportedTransaction]) -> [TransactionCategory: Double] {
        let cal = Calendar.current
        var result: [TransactionCategory: Double] = [:]

        var expenseByMonthCat: [TransactionCategory: [String: Double]] = [:]
        for tx in txs where tx.isExpense && !tx.category.isInternal && tx.category.group != .einkommen {
            let c = cal.dateComponents([.year, .month], from: tx.date)
            let key = "\(c.year ?? 0)-\(c.month ?? 0)"
            expenseByMonthCat[tx.category, default: [:]][key, default: 0] += convert(tx.amount, from: tx.currencyCode)
        }
        for (cat, monthlyTotals) in expenseByMonthCat {
            result[cat] = monthlyTotals.values.reduce(0, +) / Double(monthlyTotals.count)
        }

        var largestIncomeByMonthCat: [TransactionCategory: [String: Double]] = [:]
        for tx in txs where tx.isIncome && tx.category.group == .einkommen {
            let c = cal.dateComponents([.year, .month], from: tx.date)
            let key = "\(c.year ?? 0)-\(c.month ?? 0)"
            let amount = convert(tx.amount, from: tx.currencyCode)
            let existing = largestIncomeByMonthCat[tx.category, default: [:]][key] ?? 0
            largestIncomeByMonthCat[tx.category, default: [:]][key] = Swift.max(existing, amount)
        }
        for (cat, monthlyLargest) in largestIncomeByMonthCat {
            result[cat] = typicalIncome(from: Array(monthlyLargest.values))
        }

        return result
    }

    private var categoryAvg: [TransactionCategory: Double] { categoryAvgCache ?? [:] }

    // Budget amount planned for a given TransactionCategory
    private func plannedAmount(for txCat: TransactionCategory) -> Double {
        entries.filter { entry in
            guard entry.isActive else { return false }
            if entry.userCategory == nil { return entry.category.rollsUpTo == txCat }
            if let uc = entry.userCategory {
                let name = uc.name.lowercased()
                let catName = txCat.rawValue.lowercased()
                if name.contains(catName) || catName.contains(name) { return true }
                if txCat == .restaurant && (name.contains("essen") || name.contains("ausgang")) { return true }
            }
            return false
        }.reduce(0) { $0 + entryMonthlyAmount($1) }
    }

    struct CategoryRow: Identifiable {
        let id: TransactionCategory
        let txCat: TransactionCategory
        let actual: Double
        let budget: Double
        var delta: Double { actual - budget }
        var hasBudget: Bool { budget > 0 }
        var isIncome: Bool { txCat.group == .einkommen }
        // Income: green when actual ≥ budget; expense: green when actual ≤ budget
        var deltaColor: Color { isIncome ? (delta >= 0 ? .green : .red) : (delta <= 0 ? .green : .red) }
    }

    private var incomeRows: [CategoryRow] {
        categoryAvg
            .filter { $0.key.group == .einkommen }
            .map { (cat, avg) in CategoryRow(id: cat, txCat: cat, actual: avg, budget: plannedAmount(for: cat)) }
            .sorted { $0.actual > $1.actual }
    }

    private var expenseRows: [CategoryRow] {
        categoryAvg
            .filter { $0.key.group != .einkommen }
            .map { (cat, avg) in CategoryRow(id: cat, txCat: cat, actual: avg, budget: plannedAmount(for: cat)) }
            .sorted { $0.actual > $1.actual }
    }

    private var totalExpenseBudget: Double { expenseRows.reduce(0) { $0 + $1.budget } }
    private var totalExpenseActual: Double { expenseRows.reduce(0) { $0 + $1.actual } }
    private var totalExpenseDelta: Double { totalExpenseActual - totalExpenseBudget }

    var body: some View {
        NavigationStack {
            List {
                // Loading indicator while categoryAvg is being computed
                if categoryAvgCache == nil {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    }
                    .listRowBackground(Color.clear)
                }

                // Lookback period slider
                Section {
                    VStack(spacing: 6) {
                        HStack {
                            Text("Analysezeitraum")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("Letzte \(lookbackMonths) Monate")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.blue)
                                .contentTransition(.numericText())
                        }
                        Slider(value: Binding(
                            get: { Double(lookbackMonths) },
                            set: { lookbackMonths = Int($0.rounded()) }
                        ), in: 1...12, step: 1)
                        .tint(.blue)
                        Text("Je kürzer der Zeitraum, desto aktueller die Werte.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Expense summary bar
                if !expenseRows.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            HStack(spacing: 0) {
                                amountPill(label: "Geplant", amount: totalExpenseBudget, color: .primary)
                                Spacer()
                                amountPill(label: "Ausgegeben",
                                           amount: totalExpenseActual,
                                           color: totalExpenseActual > totalExpenseBudget ? .red : .green)
                            }
                            GeometryReader { geo in
                                let maxAmt = Swift.max(totalExpenseActual, totalExpenseBudget) * 1.05
                                let budgetFrac = maxAmt > 0 ? totalExpenseBudget / maxAmt : 1.0
                                let actualFrac = maxAmt > 0 ? min(totalExpenseActual / maxAmt, 1.0) : 0.0
                                let over = totalExpenseActual > totalExpenseBudget
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.1)).frame(height: 10)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill((over ? Color.red : Color.green).opacity(0.65))
                                        .frame(width: geo.size.width * CGFloat(actualFrac), height: 10)
                                    Rectangle().fill(Color.primary.opacity(0.5)).frame(width: 2, height: 14)
                                        .offset(x: geo.size.width * CGFloat(budgetFrac) - 1)
                                }
                            }
                            .frame(height: 10)
                            HStack {
                                Text("Abweichung gesamt")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Text((totalExpenseDelta >= 0 ? "+" : "")
                                     + totalExpenseDelta.formatted(.currency(code: currency).precision(.fractionLength(0))))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(totalExpenseDelta <= 0 ? .green : .red)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Ausgaben Übersicht")
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                // Income rows
                if !incomeRows.isEmpty {
                    Section {
                        ForEach(incomeRows) { row in categoryRow(row) }
                    } header: {
                        Text("Einnahmen")
                    } footer: {
                        Text("Typischer Monatswert aus deinen Transaktionen, Ausreisser werden herausgefiltert.")
                            .font(.caption)
                    }
                }

                // Expense rows
                if !expenseRows.isEmpty {
                    Section {
                        ForEach(expenseRows) { row in categoryRow(row) }
                    } header: {
                        Text("Ausgaben nach Kategorie")
                    } footer: {
                        Text(String(format: NSLocalizedString("budget_avg_months_hint", comment: ""), monthCount))
                            .font(.caption)
                    }
                }

                if expenseRows.isEmpty && incomeRows.isEmpty {
                    Section {
                        Text("Keine vergleichbaren Daten gefunden.\nImportiere Transaktionen in der Analyse-Ansicht.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Budget optimieren")
            .inlineNavigationTitle()
            .task(id: lookbackMonths) {
                categoryAvgCache = nil
                let txs = filteredTransactions
                let result = computeCategoryAvg(txs: txs)
                await MainActor.run { categoryAvgCache = result }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("done", comment: "")) { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
            .fullScreenCover(item: $pendingCreate) { action in
                AddEditBudgetEntryView(presetCategory: action.category, presetAmount: action.amount)
            }
            .alert(
                "Zur Analyseansicht wechseln?",
                isPresented: Binding(
                    get: { pendingAnalyseCategory != nil },
                    set: { if !$0 { pendingAnalyseCategory = nil } }
                )
            ) {
                Button("Weiter") {
                    if let cat = pendingAnalyseCategory {
                        let cutoff = Calendar.current.date(byAdding: .month, value: -lookbackMonths, to: Date())
                        dismiss()
                        NavigationRouter.shared.jumpToAnalyse(with: cat, dateFrom: cutoff)
                    }
                    pendingAnalyseCategory = nil
                }
                Button("Abbrechen", role: .cancel) {
                    pendingAnalyseCategory = nil
                }
            } message: {
                Text(String(format: NSLocalizedString("budget_leave_to_analyse_fmt", comment: ""), pendingAnalyseCategory?.rawValue ?? ""))
            }
        }
    }

    private func amountPill(label: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                .textCase(.uppercase).tracking(0.3)
            Text(amount.formatted(.currency(code: currency).precision(.fractionLength(0))))
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(color).minimumScaleFactor(0.55).lineLimit(1)
        }
    }

    private func categoryRow(_ row: CategoryRow) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(row.txCat.color.opacity(0.12))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: row.txCat.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(row.txCat.color)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(row.txCat.rawValue)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                // Ist vs Budget amounts side by side
                HStack(spacing: 14) {
                    Button {
                        pendingAnalyseCategory = row.txCat
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 3) {
                                Text("IST")
                                    .font(.caption2.weight(.semibold))
                                    .tracking(0.4)
                                Image(systemName: "arrow.up.right.circle")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                            Text(row.actual.formatted(.currency(code: currency).precision(.fractionLength(0))))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(row.hasBudget ? row.deltaColor : .primary)
                        }
                    }
                    .buttonStyle(.plain)
                    if row.hasBudget {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("BUDGET")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.4)
                            Text(row.budget.formatted(.currency(code: currency).precision(.fractionLength(0))))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Kein Budget geplant")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }

                // Mini comparison bar (only when budget exists)
                if row.hasBudget {
                    GeometryReader { geo in
                        let maxAmt = Swift.max(row.actual, row.budget) * 1.05
                        let budgetFrac = maxAmt > 0 ? CGFloat(row.budget / maxAmt) : 1.0
                        let actualFrac = maxAmt > 0 ? CGFloat(min(row.actual / maxAmt, 1.0)) : 0.0
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.1))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(row.deltaColor.opacity(0.6))
                                .frame(width: geo.size.width * actualFrac)
                            // Budget target line
                            Rectangle()
                                .fill(Color.primary.opacity(0.35))
                                .frame(width: 1.5)
                                .offset(x: geo.size.width * budgetFrac - 0.75)
                        }
                    }
                    .frame(height: 5)
                }
            }

            // Right side: delta or Anlegen button
            if row.hasBudget {
                let delta = row.delta
                VStack(alignment: .trailing, spacing: 1) {
                    Text(delta >= 0 ? "+" : "–")
                        .font(.caption2).foregroundStyle(row.deltaColor)
                    Text(abs(delta).formatted(.currency(code: currency).precision(.fractionLength(0))))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(row.deltaColor)
                }
                .frame(minWidth: 56, alignment: .trailing)
            } else {
                Button {
                    pendingCreate = CreateAction(
                        category: row.txCat.suggestedBudgetCategory,
                        amount: row.actual.rounded()
                    )
                } label: {
                    Label("Anlegen", systemImage: "plus.circle.fill")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(row.txCat.color.opacity(0.12))
                        .foregroundStyle(row.txCat.color)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func roundToGranularity(_ value: Double) -> Double {
        let granularity: Double
        if value > 10_000 { granularity = 500 }
        else if value > 2_000 { granularity = 100 }
        else if value > 500 { granularity = 50 }
        else { granularity = 10 }
        return (value / granularity).rounded() * granularity
    }

    private func typicalIncome(from monthlyTotals: [Double]) -> Double {
        guard !monthlyTotals.isEmpty else { return 0 }
        let maxVal = monthlyTotals.max() ?? 0
        let upperTotals = monthlyTotals.filter { $0 >= maxVal * 0.5 }
        guard !upperTotals.isEmpty else { return 0 }
        let rounded = upperTotals.map { roundToGranularity($0) }
        var freq: [Double: Int] = [:]
        for v in rounded { freq[v, default: 0] += 1 }
        guard let modalBucket = freq.max(by: { a, b in
            if a.value != b.value { return a.value < b.value }
            return a.key < b.key
        })?.key else { return 0 }
        // Average the actual (unrounded) monthly values that fall in the modal bucket
        let modalValues = upperTotals.filter { roundToGranularity($0) == modalBucket }
        return modalValues.reduce(0, +) / Double(modalValues.count)
    }
}

// MARK: - Tile Detail Sheet

private struct TileDetailSheet: View {
    let title: String
    let color: Color
    let entries: [TileDetailEntry]
    let total: Double
    let currency: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 4) {
                        Text(total.formatted(.currency(code: currency)))
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(color)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text(entries.count == 1
                             ? NSLocalizedString("1 Eintrag", comment: "")
                             : String(format: NSLocalizedString("%lld Einträge", comment: ""), entries.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    ForEach(entries) { entry in
                        let ratio = total > 0 ? entry.amount / total : 0
                        HStack(spacing: 12) {
                            Circle()
                                .fill(entry.color.opacity(0.14))
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Image(systemName: entry.symbolName)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(entry.color)
                                )
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(entry.name).font(.body)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(entry.amount.formatted(.currency(code: currency)))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(color)
                                        Text(String(format: "%.0f%%", ratio * 100))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(color.opacity(0.10))
                                            .frame(height: 5)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(color.opacity(0.65))
                                            .frame(width: max(4, geo.size.width * CGFloat(ratio)), height: 5)
                                    }
                                }
                                .frame(height: 5)
                                Text(entry.recurrenceLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if entries.isEmpty {
                    Section {
                        Text("Keine Einträge")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("done", comment: "")) { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Compact Card: Sankey

private struct FlowCardSankey: View {
    let incomeItems: [(name: String, amount: Double, color: Color)]
    let expenseItems: [(name: String, amount: Double, color: Color)]
    let currency: String
    @Environment(\.colorScheme) private var colorScheme

    private var totalIncome: Double { incomeItems.reduce(0) { $0 + $1.amount } }
    private var totalExpenses: Double { expenseItems.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(NSLocalizedString("cash_flow_section", comment: ""), systemImage: "arrow.left.arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

            BudgetSankeyCanvas(incomeItems: incomeItems, expenseItems: Array(expenseItems.prefix(4)), currency: currency)
                .frame(height: 126)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color.clear : Color(.systemBackground))
    }
}

// MARK: - Compact Card: Pie

private struct FlowCardPie: View {
    let items: [BudgetFlowItem]
    let currency: String
    @Environment(\.colorScheme) private var colorScheme

    private var total: Double { items.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(NSLocalizedString("expenses_by_category", comment: ""), systemImage: "chart.pie.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            HStack(alignment: .center, spacing: 14) {
                Chart(items) { item in
                    SectorMark(angle: .value("Amount", item.amount), innerRadius: .ratio(0.56), angularInset: 1.5)
                        .foregroundStyle(item.color).cornerRadius(3)
                }
                .chartLegend(.hidden)
                .frame(width: 88, height: 88)
                .overlay {
                    Text(total.formatted(.currency(code: currency).notation(.compactName).precision(.fractionLength(0))))
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: 46)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items.prefix(4)) { item in
                        HStack(spacing: 5) {
                            Circle().fill(item.color).frame(width: 7, height: 7)
                            Text(item.name).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Text(item.amount.formatted(.currency(code: currency).notation(.compactName).precision(.fractionLength(0))))
                                .font(.caption2.weight(.semibold)).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color.clear : Color(.systemBackground))
    }
}

// MARK: - Compact Card: Balance

private struct FlowCardBalance: View {
    let income: Double
    let expenses: Double
    let savings: Double
    let currency: String
    @Environment(\.colorScheme) private var colorScheme

    private var net: Double { income - expenses - savings }
    private var maxVal: Double { max(income, expenses, 1) }
    private var savingsRate: Double { income > 0 ? max(0, savings / income * 100) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(NSLocalizedString("net", comment: ""), systemImage: "chart.bar.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 9) {
                compactBarRow(label: NSLocalizedString("income", comment: ""), amount: income, color: .green)
                compactBarRow(label: NSLocalizedString("expenses", comment: ""), amount: expenses, color: .budgetExpense)

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("net", comment: "")).font(.caption2).foregroundStyle(.secondary)
                        Text((net >= 0 ? "+" : "") + net.formatted(.currency(code: currency)))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(net >= 0 ? .green : .red)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer()
                    if income > 0 && savings > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(NSLocalizedString("savings_rate", comment: "")).font(.caption2).foregroundStyle(.secondary)
                            Text(String(format: "%.0f%%", savingsRate))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(savingsRate >= 20 ? .green : savingsRate >= 10 ? .orange : .red)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 10)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color.clear : Color(.systemBackground))
    }

    private func compactBarRow(label: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(amount.formatted(.currency(code: currency))).font(.caption2.weight(.bold)).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.7))
                    .frame(width: geo.size.width * CGFloat(amount / maxVal))
            }
            .frame(height: 9)
        }
    }
}

// MARK: - Budget Viz Sheet

private struct BudgetVizSheet: View {
    let entries: [BudgetEntry]
    let currency: String

    @Environment(\.dismiss) private var dismiss
    @State private var sheetMode: BudgetDisplayMode = .average
    @State private var sheetMonth: Date = {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return Calendar.current.date(from: c) ?? Date()
    }()
    @State private var showingMonthPicker = false

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(sheetMonth, equalTo: Date(), toGranularity: .month)
    }

    private func navigateMonth(_ offset: Int) {
        sheetMonth = Calendar.current.date(byAdding: .month, value: offset, to: sheetMonth) ?? sheetMonth
    }

    private var selectedMonthLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        fmt.locale = Locale.current
        return fmt.string(from: sheetMonth)
    }

    private static let fallbackRates: [String: Double] = [
        "EUR": 1.0, "USD": 1.08, "GBP": 0.86, "CHF": 0.96, "JPY": 162.0,
        "CAD": 1.47, "AUD": 1.64, "SEK": 11.50, "NOK": 11.70,
        "DKK": 7.46, "PLN": 4.25, "CZK": 25.30,
        "HUF": 395.0, "RON": 4.97, "HKD": 8.45, "SGD": 1.46,
        "CNY": 7.85, "INR": 90.0, "BRL": 5.85, "MXN": 19.5,
        "ZAR": 20.5, "TRY": 36.5, "AED": 3.97, "SAR": 4.05,
        "KRW": 1450.0, "IDR": 17200.0,
    ]

    private func convert(_ amount: Double, from: String, to: String) -> Double {
        guard from != to else { return amount }
        let fromRate = Self.fallbackRates[from] ?? 1.0
        let toRate = Self.fallbackRates[to] ?? 1.0
        return amount / fromRate * toRate
    }

    private func entryMonthlyAmount(_ entry: BudgetEntry) -> Double {
        convert(entry.effectiveMonthlyAmount, from: entry.account?.currency ?? currency, to: currency)
    }

    private func entryAmountForMonthRaw(_ entry: BudgetEntry, monthStart: Date) -> Double {
        let cal = Calendar.current
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let monthNum = cal.component(.month, from: monthStart)
        var base: Double
        switch entry.recurrence {
        case .monthly:
            base = entry.amount
        case .once:
            guard entry.dueDate >= monthStart && entry.dueDate < monthEnd else { return 0 }
            base = entry.amount
        case .quarterly, .semiannual, .yearly:
            guard let nextDue = entry.nextDueDate(after: monthStart), nextDue < monthEnd else { return 0 }
            base = entry.amount
        }
        if entry.isIncomeEntry {
            if entry.bonus13Enabled {
                let months = entry.bonus13Months
                if !months.isEmpty && months.contains(monthNum) { base += entry.amount / Double(months.count) }
            }
            if entry.bonusFixedEnabled && entry.bonusFixedMonth == monthNum { base += entry.bonusFixedAmount }
        }
        return base
    }

    private func entryAmountForMonth(_ entry: BudgetEntry, monthStart: Date) -> Double {
        convert(entryAmountForMonthRaw(entry, monthStart: monthStart), from: entry.account?.currency ?? currency, to: currency)
    }

    private func entryAmountForPeriod(_ entry: BudgetEntry) -> Double {
        switch sheetMode {
        case .average:  return entryMonthlyAmount(entry)
        case .yearly:   return entryMonthlyAmount(entry) * 12.0
        case .specific: return entryAmountForMonth(entry, monthStart: sheetMonth)
        }
    }

    private func isSavingsTransfer(_ entry: BudgetEntry) -> Bool {
        guard let dest = entry.transferToAccount else { return false }
        return dest.type == .sparkonto || dest.type == .tagesgeld || dest.type == .festgeld
    }

    private func isInvestmentTransfer(_ entry: BudgetEntry) -> Bool {
        guard let dest = entry.transferToAccount else { return false }
        return dest.type.isInvestment
    }

    private func entryGroup(_ entry: BudgetEntry) -> CategoryGroup {
        entry.userCategory.map { $0.group } ?? entry.category.group
    }

    private var income: Double {
        entries.filter { $0.isIncomeEntry }.reduce(0) { $0 + entryAmountForPeriod($1) }
    }

    private var savingsOnly: Double {
        entries.filter { ($0.isSavingsEntry && !$0.isInvestmentEntry) || isSavingsTransfer($0) }
            .reduce(0) { $0 + entryAmountForPeriod($1) }
    }

    private var investments: Double {
        entries.filter { $0.isInvestmentEntry || isInvestmentTransfer($0) }
            .reduce(0) { $0 + entryAmountForPeriod($1) }
    }

    private var expenses: Double {
        entries.filter { !$0.isIncomeEntry && !$0.isSavingsEntry && $0.transferToAccount == nil }
            .reduce(0) { $0 + entryAmountForPeriod($1) }
    }

    private var sankeyIncomeItems: [(name: String, amount: Double, color: Color)] {
        var groups: [String: (Double, Color)] = [:]
        for entry in entries where entry.isIncomeEntry {
            let key = entry.displayName
            groups[key] = ((groups[key]?.0 ?? 0) + entryAmountForPeriod(entry), entry.displayColor)
        }
        return groups.map { (name: $0.key, amount: $0.value.0, color: $0.value.1) }
            .filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
    }

    private var outflowGroupData: [BudgetGroupItem] {
        var totals: [CategoryGroup: Double] = [:]
        for entry in entries where !entry.isIncomeEntry {
            let grp: CategoryGroup
            if entry.isInvestmentEntry || isInvestmentTransfer(entry) { grp = .investieren }
            else if entry.isSavingsEntry || isSavingsTransfer(entry) { grp = .sparen }
            else if entry.transferToAccount != nil { continue }
            else { grp = entryGroup(entry) }
            totals[grp, default: 0] += entryAmountForPeriod(entry)
        }
        return CategoryGroup.allCases.compactMap { grp -> BudgetGroupItem? in
            guard grp != .einkommen && grp != .intern, let total = totals[grp], total > 0 else { return nil }
            return BudgetGroupItem(group: grp, name: grp.localizedName, amount: total, color: grp.color)
        }.sorted { $0.amount > $1.amount }
    }

    private var outflowGroupEntries: [CategoryGroup: [TileDetailEntry]] {
        var result: [CategoryGroup: [TileDetailEntry]] = [:]
        for entry in entries where !entry.isIncomeEntry {
            let grp: CategoryGroup
            if entry.isInvestmentEntry || isInvestmentTransfer(entry) { grp = .investieren }
            else if entry.isSavingsEntry || isSavingsTransfer(entry) { grp = .sparen }
            else if entry.transferToAccount != nil { continue }
            else { grp = entryGroup(entry) }
            result[grp, default: []].append(TileDetailEntry(
                id: entry.id, name: entry.displayName, symbolName: entry.displaySymbolName,
                color: entry.displayColor, amount: entryAmountForPeriod(entry),
                recurrenceLabel: entry.recurrenceDisplayLabel
            ))
        }
        for key in result.keys { result[key]?.sort { $0.amount > $1.amount } }
        return result
    }

    private var savings: Double { savingsOnly + investments }
    private var net: Double { income - expenses - savings }
    private var maxBarVal: Double { max(income, expenses + savings, 1) }
    private var savingsRate: Double { income > 0 ? max(0, savingsOnly / income * 100) : 0 }
    private var investRate: Double { income > 0 ? max(0, investments / income * 100) : 0 }
    private var totalGroupExpenses: Double { outflowGroupData.reduce(0) { $0 + $1.amount } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modeSelector
                    heroStats
                    if !sankeyIncomeItems.isEmpty || !outflowGroupData.isEmpty { sankeyCard }
                    if !sankeyIncomeItems.isEmpty { incomeBreakdown }
                    if !outflowGroupData.isEmpty { expenseBreakdown }
                    if !outflowGroupData.isEmpty { pieCard }
                    balanceCard
                    if income > 0 && savings > 0 { savingsGauges }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
                .padding(.top, 4)
            }
            .background(AnimatedPatternBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle(NSLocalizedString("budget_viz_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("done", comment: "")) { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showingMonthPicker) {
            MonthPickerSheet(selectedMonth: $sheetMonth)
        }
        .presentationDetents([.large])
    }

    // MARK: Mode selector

    private var modeSelector: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { sheetMode = .specific }
                } label: {
                    Text(NSLocalizedString("period_monthly", comment: ""))
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(sheetMode == .specific ? Color.primary.opacity(0.08) : Color.secondary.opacity(0.06))
                        .foregroundStyle(sheetMode == .specific ? Color.primary : Color.secondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(ScalePressButtonStyle())

                HStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) { sheetMode = .average }
                    } label: {
                        Text("Ø Monat")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(sheetMode == .average ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(ScalePressButtonStyle())

                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: 14)

                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) { sheetMode = .yearly }
                    } label: {
                        Text("Ø Jahr")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(sheetMode == .yearly ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(ScalePressButtonStyle())
                }
                .padding(.horizontal, 4)
                .background(
                    (sheetMode == .average || sheetMode == .yearly)
                        ? Color.primary.opacity(0.08)
                        : Color.secondary.opacity(0.06)
                )
                .clipShape(Capsule())
            }

            if sheetMode == .specific {
                HStack {
                    Button { withAnimation { navigateMonth(-1) } } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { showingMonthPicker = true } label: {
                        VStack(spacing: 3) {
                            Text(selectedMonthLabel).font(.subheadline.weight(.semibold))
                            if isCurrentMonth {
                                Text("Aktuell")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Color.green.opacity(0.85))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { withAnimation { navigateMonth(1) } } label: {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .cardStyle(cornerRadius: 14)
    }

    // MARK: Hero stats
    private var heroStats: some View {
        return HStack(spacing: 0) {
            vizStatCell(
                label: NSLocalizedString("income", comment: ""),
                valueText: income.formatted(.currency(code: currency).notation(.compactName).precision(.fractionLength(0))),
                color: .green
            )
            Divider().frame(height: 36)
            vizStatCell(
                label: NSLocalizedString("expenses", comment: ""),
                valueText: expenses.formatted(.currency(code: currency).notation(.compactName).precision(.fractionLength(0))),
                color: .budgetExpense
            )
            Divider().frame(height: 36)
            vizStatCell(
                label: net >= 0 ? NSLocalizedString("surplus", comment: "") : NSLocalizedString("deficit", comment: ""),
                valueText: (net >= 0 ? "+" : "") + net.formatted(.currency(code: currency).notation(.compactName).precision(.fractionLength(0))),
                color: net >= 0 ? .green : .red
            )
        }
        .padding(.vertical, 14)
        .cardStyle(cornerRadius: 14)
    }

    private var sankeyExpenseEntries: [(name: String, amount: Double, color: Color)] {
        outflowGroupData.flatMap { grp in
            (outflowGroupEntries[grp.group] ?? []).map { entry in
                (name: entry.name, amount: entry.amount, color: entry.color)
            }
        }
        .sorted { $0.amount > $1.amount }
    }

    // MARK: Sankey
    private var sankeyCard: some View {
        let expItems = sankeyExpenseEntries
        let n = expItems.count + (net > 0.5 ? 1 : 0)
        let h = max(220, CGFloat(n) * 38 + 40)
        return VStack(alignment: .leading, spacing: 0) {
            vizSectionLabel(NSLocalizedString("cash_flow_section", comment: ""), icon: "arrow.left.arrow.right")
            BudgetSankeyCanvas(incomeItems: sankeyIncomeItems, expenseItems: expItems, currency: currency)
                .frame(height: h)
                .padding(.bottom, 8)
        }
        .cardStyle(cornerRadius: 14)
    }

    // MARK: Income breakdown
    private var incomeBreakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            vizSectionLabel(NSLocalizedString("income_section", comment: ""), icon: "banknote.fill")
            ForEach(sankeyIncomeItems, id: \.name) { item in
                HStack(spacing: 12) {
                    Circle().fill(item.color.opacity(0.15)).frame(width: 38, height: 38)
                        .overlay(Image(systemName: "banknote.fill").font(.system(size: 14, weight: .medium)).foregroundStyle(item.color))
                    Text(item.name).font(.subheadline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.amount.formatted(.currency(code: currency)))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                        if income > 0 {
                            Text(String(format: "%.0f%%", item.amount / income * 100))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                if item.name != sankeyIncomeItems.last?.name {
                    Divider().padding(.leading, 66)
                }
            }
            .padding(.bottom, 6)
        }
        .cardStyle(cornerRadius: 14)
    }

    // MARK: Expense breakdown with subcategories
    private var expenseBreakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            vizSectionLabel(NSLocalizedString("expense_section", comment: ""), icon: "arrow.down.circle.fill")
            ForEach(outflowGroupData) { grp in
                let grpEntries = outflowGroupEntries[grp.group] ?? []
                let ratio = totalGroupExpenses > 0 ? grp.amount / totalGroupExpenses : 0
                let incomeRatio = income > 0 ? grp.amount / income : 0
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Circle().fill(grp.color.opacity(0.14)).frame(width: 40, height: 40)
                            .overlay(Image(systemName: grp.group.systemImage).font(.system(size: 15, weight: .medium)).foregroundStyle(grp.color))
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(grp.name).font(.body.weight(.semibold))
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(grp.amount.formatted(.currency(code: currency)))
                                        .font(.subheadline.weight(.semibold))
                                    if income > 0 {
                                        Text(String(format: "%.0f%%", incomeRatio * 100))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(grp.color.opacity(0.10)).frame(height: 5)
                                    RoundedRectangle(cornerRadius: 3).fill(grp.color.opacity(0.65))
                                        .frame(width: max(4, geo.size.width * CGFloat(ratio)), height: 5)
                                }
                            }
                            .frame(height: 5)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    ForEach(grpEntries) { entry in
                        let entryRatio = grp.amount > 0 ? entry.amount / grp.amount : 0
                        HStack(spacing: 10) {
                            Spacer().frame(width: 16)
                            Circle().fill(entry.color.opacity(0.10)).frame(width: 32, height: 32)
                                .overlay(Image(systemName: entry.symbolName).font(.system(size: 12)).foregroundStyle(entry.color))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.name).font(.subheadline).foregroundStyle(.secondary)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(entry.amount.formatted(.currency(code: currency)))
                                            .font(.caption.weight(.semibold))
                                        Text(String(format: "%.0f%%", entryRatio * 100))
                                            .font(.caption2).foregroundStyle(.secondary)
                                        Text(entry.recurrenceLabel).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2).fill(grp.color.opacity(0.08)).frame(height: 3)
                                        RoundedRectangle(cornerRadius: 2).fill(grp.color.opacity(0.45))
                                            .frame(width: max(2, geo.size.width * CGFloat(entryRatio)), height: 3)
                                    }
                                }
                                .frame(height: 3)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        Divider().padding(.leading, 74)
                    }

                    if grp.id != outflowGroupData.last?.id {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 6)
        }
        .cardStyle(cornerRadius: 14)
    }

    // MARK: Pie chart
    private var pieCard: some View {
        let pieData = outflowGroupData.map { BudgetFlowItem(name: $0.name, amount: $0.amount, color: $0.color) }
        let total = pieData.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 0) {
            vizSectionLabel(NSLocalizedString("expenses_by_category", comment: ""), icon: "chart.pie.fill")
            HStack(alignment: .center, spacing: 16) {
                Chart(pieData) { item in
                    SectorMark(angle: .value("Amount", item.amount), innerRadius: .ratio(0.54), angularInset: 2)
                        .foregroundStyle(item.color).cornerRadius(4)
                }
                .chartLegend(.hidden)
                .frame(width: 140, height: 140)
                .overlay {
                    VStack(spacing: 2) {
                        Text(total.formatted(.currency(code: currency).notation(.compactName).precision(.fractionLength(0))))
                            .font(.headline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.5)
                        Text(NSLocalizedString("expenses", comment: "")).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 62).multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pieData) { item in
                        HStack(spacing: 8) {
                            Circle().fill(item.color).frame(width: 8, height: 8)
                            Text(item.name).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if total > 0 {
                                Text(String(format: "%.0f%%", item.amount / total * 100))
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .cardStyle(cornerRadius: 14)
    }

    // MARK: Balance bars
    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            vizSectionLabel(NSLocalizedString("net", comment: ""), icon: "chart.bar.fill")
            VStack(alignment: .leading, spacing: 12) {
                vizBarRow(label: NSLocalizedString("income", comment: ""), amount: income, maxVal: maxBarVal, color: .green)
                vizBarRow(label: NSLocalizedString("expenses", comment: ""), amount: expenses, maxVal: maxBarVal, color: .budgetExpense)
                if savingsOnly > 0 {
                    vizBarRow(label: NSLocalizedString("budget_category_savings", comment: ""), amount: savingsOnly, maxVal: maxBarVal, color: .budgetSavings)
                }
                if investments > 0 {
                    vizBarRow(label: NSLocalizedString("investments", comment: ""), amount: investments, maxVal: maxBarVal, color: .budgetInvestment)
                }
                Divider()
                HStack {
                    Text(NSLocalizedString("net", comment: "")).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text((net >= 0 ? "+" : "") + (income > 0 ? String(format: "%.0f%%", net / income * 100) : "—"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(net >= 0 ? .green : .red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .cardStyle(cornerRadius: 14)
    }

    // MARK: Savings gauges
    private var savingsGauges: some View {
        let srColor: Color = savingsRate >= 20 ? .green : savingsRate >= 10 ? .orange : .red
        let irColor: Color = investRate >= 15 ? .green : investRate >= 8 ? .orange : .purple
        return HStack(spacing: 0) {
            if savingsOnly > 0 {
                vizGaugeCell(label: NSLocalizedString("budget_category_savings", comment: ""), rate: savingsRate, amount: savingsOnly, color: srColor)
                if investments > 0 { Divider() }
            }
            if investments > 0 {
                vizGaugeCell(label: NSLocalizedString("investments", comment: ""), rate: investRate, amount: investments, color: irColor)
            }
        }
        .cardStyle(cornerRadius: 14)
    }

    // MARK: Helpers

    private func vizStatCell(label: String, valueText: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(valueText)
                .font(.subheadline.weight(.semibold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func vizSectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    private func vizBarRow(label: String, amount: Double, maxVal: Double, color: Color) -> some View {
        let pct = income > 0 ? String(format: "%.0f%%", amount / income * 100) : "—"
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(amount.formatted(.currency(code: currency)))
                        .font(.caption.weight(.bold)).foregroundStyle(color)
                    Text(pct).font(.caption2).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(0.75))
                    .frame(width: geo.size.width * CGFloat(amount / maxVal))
            }
            .frame(height: 12)
        }
    }

    private func vizGaugeCell(label: String, rate: Double, amount: Double, color: Color) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(CGFloat(rate / 100), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%.0f%%", rate))
                    .font(.caption2.weight(.semibold))
            }
            .frame(width: 56, height: 56)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }
}

// MARK: - Sankey Canvas (no fixed frame — caller sets height)
