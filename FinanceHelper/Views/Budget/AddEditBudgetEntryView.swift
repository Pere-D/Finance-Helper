import SwiftUI
import SwiftData

private enum EntrySheet: Identifiable {
    case addAccount
    var id: String { "addAccount" }
}

private enum PendingAccountKind {
    case primary, transfer
}

private enum RecurrenceMode: Equatable {
    case once, monthly, custom
}

struct AddEditBudgetEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.createdAt) private var allAccountsRaw: [Account]
    @AppStorage("active_profile_id") private var activeProfileID: String = ""

    var entry: BudgetEntry? = nil
    var preselectedAccount: Account? = nil
    var presetCategory: BudgetCategory? = nil
    var presetAmount: Double? = nil
    var presetNotes: String? = nil
    var presetDueDate: Date? = nil
    var presetIsOnce: Bool = false
    var linkedGoalID: String? = nil

    @AppStorage("default_currency") private var defaultCurrency = "EUR"

    private var accounts: [Account] { allAccountsRaw.filter { $0.profileID == activeProfileID } }
    @State private var selectedCategory: BudgetCategory? = nil
    @State private var currencyOverride: String? = nil
    @State private var selectedUserCategory: UserBudgetCategory? = nil
    @State private var amountText: String = ""
    @State private var selectedAccount: Account? = nil
    @State private var recurrenceMode: RecurrenceMode = .monthly
    @State private var dueDay: Int = 25
    @State private var dueDate: Date = Date()
    @State private var customMonths: Set<Int> = [12]
    @State private var notes: String = ""
    @State private var isActive: Bool = true
    @State private var transferToAccount: Account? = nil
    @State private var showTransfer: Bool = false
    @State private var activeSheet: EntrySheet? = nil
    @State private var pendingAccountKind: PendingAccountKind? = nil
    @State private var showingCategoryPicker = false
    @State private var hasPopulated = false
    @FocusState private var amountFocused: Bool

    // Sonderzahlungen
    @State private var bonus13Enabled: Bool = false
    @State private var bonus13SelectedMonths: Set<Int> = [12]
    @State private var bonusFixedEnabled: Bool = false
    @State private var bonusFixedAmountText: String = ""
    @State private var bonusFixedMonth: Int = 6

    // Optional entry lifetime (recurring entries only)
    @State private var hasStartDate: Bool = false
    @State private var startDate: Date = Date()
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Date()

    private var isNew: Bool { entry == nil }
    private var hasCategory: Bool { selectedCategory != nil || selectedUserCategory != nil }

    private var isValid: Bool {
        let amount = (Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
        let hasCategory = selectedUserCategory != nil || selectedCategory != nil
        return amount && hasCategory
    }

    private var displayCurrency: String {
        currencyOverride ?? selectedAccount?.currency ?? defaultCurrency
    }

    private var displayCategoryName: String {
        selectedUserCategory?.name ?? selectedCategory?.localizedName ?? NSLocalizedString("choose_category", comment: "")
    }

    private var displayCategorySymbol: String {
        selectedUserCategory?.symbolName ?? selectedCategory?.systemImage ?? "questionmark.circle"
    }

    private var displayCategoryColor: Color {
        selectedUserCategory?.color ?? selectedCategory?.color ?? Color.secondary
    }

    var body: some View {
        NavigationStack {
            Form {
                if let acc = selectedAccount, acc.type.isLiability {
                    liabilityInfoSection(acc)
                }
                categorySection
                if hasCategory {
                    amountSection
                    recurrenceSection
                    accountSection
                    if recurrenceMode != .once {
                        timingSection
                    }
                    if isIncomeCategory {
                        bonusSection
                    }
                    transferSection
                    statusSection
                    notesSection
                }
                if !isNew {
                    deleteSection
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded { amountFocused = false })
            .navigationTitle(isNew
                ? NSLocalizedString("new_entry", comment: "")
                : NSLocalizedString("edit_booking", comment: ""))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }.foregroundStyle(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", comment: "")) { save(); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                        .foregroundStyle(isValid ? .primary : .secondary)
                }
            }
            .navigationDestination(isPresented: $showingCategoryPicker) {
                BudgetCategoryPickerView(
                    isEmbedded: true,
                    selectedBuiltin: selectedUserCategory == nil ? selectedCategory : nil,
                    selectedUser: selectedUserCategory,
                    onSelectBuiltin: { cat in
                        selectedCategory = cat
                        selectedUserCategory = nil
                    },
                    onSelectUser: { userCat in
                        selectedUserCategory = userCat
                        selectedCategory = nil
                    }
                )
            }
            .sheet(item: $activeSheet) { _ in
                AddEditAccountView()
            }
            .onChange(of: allAccountsRaw) { _, _ in
                guard let kind = pendingAccountKind else { return }
                pendingAccountKind = nil
                guard let newest = accounts.last else { return }
                switch kind {
                case .primary:  selectedAccount = newest
                case .transfer: transferToAccount = newest
                }
            }
            .onAppear {
                if !hasPopulated {
                    populate()
                    hasPopulated = true
                }
            }
        }
    }

    // MARK: - Form Sections

    private var categorySection: some View {
        Section(NSLocalizedString("category_section", comment: "")) {
            Button { showingCategoryPicker = true } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(displayCategoryColor.opacity(0.14))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: displayCategorySymbol)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(displayCategoryColor)
                        )
                    Text(displayCategoryName)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private var isIncomeCategory: Bool {
        if let uc = selectedUserCategory { return uc.isIncome }
        return selectedCategory?.group == .einkommen
    }

    private var bonusSection: some View {
        Section {
            Toggle(isOn: $bonus13Enabled) {
                Label("13. Monatslohn", systemImage: "banknote.fill")
            }
            if bonus13Enabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Auszahlungsmonate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                        spacing: 6
                    ) {
                        ForEach(1...12, id: \.self) { month in
                            let selected = bonus13SelectedMonths.contains(month)
                            Button {
                                if selected {
                                    if bonus13SelectedMonths.count > 1 {
                                        bonus13SelectedMonths.remove(month)
                                    }
                                } else {
                                    bonus13SelectedMonths.insert(month)
                                }
                            } label: {
                                Text(Self.shortMonthName(month))
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(selected ? Color.blue : Color.secondary.opacity(0.12))
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Toggle(isOn: $bonusFixedEnabled) {
                Label("Fixer Bonus", systemImage: "star.fill")
            }
            if bonusFixedEnabled {
                HStack {
                    TextField("Betrag", text: $bonusFixedAmountText)
                        .decimalPadKeyboard()
                        .focused($amountFocused)
                    Spacer()
                    Text(displayCurrency)
                        .foregroundStyle(.secondary)
                }
                Picker("Auszahlungsmonat", selection: $bonusFixedMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(Self.monthName(m)).tag(m)
                    }
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text("Sonderzahlungen")
        } footer: {
            if bonus13Enabled || bonusFixedEnabled {
                Text("Erscheinen als einmaliger Betrag im jeweiligen Monat der Prognose.")
                    .font(.caption)
            }
        }
    }

    private static func monthName(_ month: Int) -> String {
        DateFormatter().monthSymbols[month - 1]
    }

    private static func shortMonthName(_ month: Int) -> String {
        DateFormatter().shortMonthSymbols[month - 1]
    }

    private var accountSection: some View {
        let label = isIncomeCategory
            ? NSLocalizedString("receiving_account_label", comment: "")
            : NSLocalizedString("charge_account_label", comment: "")
        return Section(label) {
            Picker(label, selection: $selectedAccount) {
                Text(NSLocalizedString("no_account", comment: ""))
                    .tag(nil as Account?)
                ForEach(accounts) { acc in
                    Label(acc.name, systemImage: acc.type.systemImage)
                        .tag(acc as Account?)
                }
            }
            .pickerStyle(.menu)
            Button {
                pendingAccountKind = .primary
                activeSheet = .addAccount
            } label: {
                Label(NSLocalizedString("add_account", comment: ""), systemImage: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var amountSection: some View {
        Section(NSLocalizedString("amount_section", comment: "")) {
            HStack {
                TextField("0.00", text: $amountText)
                    .decimalPadKeyboard()
                    .focused($amountFocused)
                Spacer()
                Picker(displayCurrency, selection: Binding(
                    get: { currencyOverride ?? selectedAccount?.currency ?? defaultCurrency },
                    set: { newVal in
                        let base = selectedAccount?.currency ?? defaultCurrency
                        currencyOverride = newVal == base ? nil : newVal
                    }
                )) {
                    ForEach(CurrencyService.supportedCurrencies, id: \.self) { c in
                        Text("\(CurrencyService.currencyFlags[c] ?? "") \(c)").tag(c)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var recurrenceSection: some View {
        Section(NSLocalizedString("recurrence_section", comment: "")) {
            Picker(NSLocalizedString("interval", comment: ""), selection: $recurrenceMode) {
                Text(NSLocalizedString("budget_recurrence_once", comment: "")).tag(RecurrenceMode.once)
                Text(NSLocalizedString("budget_recurrence_monthly", comment: "")).tag(RecurrenceMode.monthly)
                Text("Monate wählen").tag(RecurrenceMode.custom)
            }
            .pickerStyle(.menu)

            if recurrenceMode == .once {
                DatePicker(NSLocalizedString("date_label", comment: ""), selection: $dueDate, displayedComponents: .date)
            } else if recurrenceMode == .monthly {
                Picker(NSLocalizedString("due_on", comment: ""), selection: $dueDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day).").tag(day)
                    }
                }
                .pickerStyle(.menu)
            } else {
                customMonthsGrid
            }
        }
    }

    private var customMonthsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Zahlungsmonate")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                let count = customMonths.count
                Text(String(format: NSLocalizedString("%lld× pro Jahr", comment: ""), count))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                spacing: 6
            ) {
                ForEach(1...12, id: \.self) { month in
                    let selected = customMonths.contains(month)
                    Button {
                        if selected {
                            if customMonths.count > 1 { customMonths.remove(month) }
                        } else {
                            customMonths.insert(month)
                        }
                    } label: {
                        Text(Self.shortMonthName(month))
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(selected ? Color.accentColor : Color.secondary.opacity(0.12))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var transferableAccounts: [Account] {
        accounts.filter { $0.id != selectedAccount?.id }
    }

    private var transferSection: some View {
        Section {
            Toggle(NSLocalizedString("transfer_toggle_label", comment: ""), isOn: Binding(
                get: { showTransfer },
                set: { newVal in
                    showTransfer = newVal
                    if !newVal { transferToAccount = nil }
                }
            ))
            if showTransfer {
                Picker(NSLocalizedString("target_account_label", comment: ""), selection: $transferToAccount) {
                    Text(NSLocalizedString("no_account", comment: "")).tag(nil as Account?)
                    ForEach(transferableAccounts) { acc in
                        Label(acc.name, systemImage: acc.type.systemImage)
                            .tag(acc as Account?)
                    }
                }
                .pickerStyle(.menu)
                Button {
                    pendingAccountKind = .transfer
                    activeSheet = .addAccount
                } label: {
                    Label(NSLocalizedString("add_account", comment: ""), systemImage: "plus.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                if transferToAccount != nil {
                    Label(
                        NSLocalizedString("transfer_info_label", comment: ""),
                        systemImage: "arrow.right.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(NSLocalizedString("target_account_label", comment: ""))
        } footer: {
            Text("Aktiviere diese Option, um Geld automatisch auf ein anderes Konto zu verschieben – z. B. für regelmäßiges Sparen oder Investieren. Der Betrag wird als Abgang vom Quellkonto und als Zugang beim Zielkonto gewertet.")
                .font(.caption)
        }
    }

    private var statusSection: some View {
        Section {
            Toggle(NSLocalizedString("budget_include_toggle", comment: ""), isOn: $isActive)
        } footer: {
            Text(NSLocalizedString("inactive_entry_hint", comment: ""))
                .font(.caption)
        }
    }

    private var notesSection: some View {
        Section(NSLocalizedString("notes_section", comment: "")) {
            TextField("Optional", text: $notes, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    private var timingSection: some View {
        Section {
            Toggle(isOn: $hasStartDate) {
                Label("Startdatum", systemImage: "calendar.badge.plus")
            }
            if hasStartDate {
                DatePicker("Gültig ab", selection: $startDate, displayedComponents: .date)
            }
            Toggle(isOn: Binding(
                get: { hasEndDate },
                set: { newVal in
                    hasEndDate = newVal
                    if !newVal { endDate = Date() }
                }
            )) {
                Label("Enddatum", systemImage: "calendar.badge.minus")
            }
            if hasEndDate {
                DatePicker("Gültig bis", selection: $endDate, in: (hasStartDate ? startDate : Date())..., displayedComponents: .date)
            }
        } header: {
            Text("Laufzeit")
        } footer: {
            if hasStartDate || hasEndDate {
                Text("Der Eintrag wird nur in den angegebenen Zeitraum berücksichtigt.")
                    .font(.caption)
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                if let e = entry { modelContext.delete(e) }
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Label(NSLocalizedString("delete_booking", comment: ""), systemImage: "trash")
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func liabilityInfoSection(_ acc: Account) -> some View {
        Section {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(acc.type.typeColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: acc.type.systemImage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(acc.type.typeColor)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(acc.name).font(.subheadline.weight(.medium))
                        Spacer()
                        Text((-acc.balance).formatted(.currency(code: acc.currency)))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    HStack(spacing: 10) {
                        if acc.monthlyExpenses > 0 {
                            Text(acc.monthlyExpenses.formatted(.currency(code: acc.currency))
                                 + " / " + NSLocalizedString("month_abbrev", comment: ""))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let months = acc.estimatedPayoffMonths {
                            Text(String(format: NSLocalizedString("payoff_in_months", comment: ""), months))
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Helpers

    private func populate() {
        if let e = entry {
            if let userCat = e.userCategory {
                selectedUserCategory = userCat
            } else {
                selectedCategory = e.category
            }
            let amt = e.amount
            amountText = amt == floor(amt) ? "\(Int(amt))" : String(format: "%.2f", amt)
            selectedAccount = e.account
            dueDay = e.dueDay
            dueDate = e.dueDate
            notes = e.notes
            // Recurrence mode
            switch e.recurrence {
            case .once:    recurrenceMode = .once
            case .monthly: recurrenceMode = .monthly
            default:       recurrenceMode = .custom
            }
            // Custom months: load stored or infer from dueDate + recurrence
            let storedMonths = e.dueMonths
            if !storedMonths.isEmpty {
                customMonths = Set(storedMonths)
            } else if e.recurrence != .once && e.recurrence != .monthly {
                let cal = Calendar.current
                let start = cal.component(.month, from: e.dueDate)
                let inferred: [Int]
                switch e.recurrence {
                case .semiannual: inferred = [start, ((start - 1 + 6) % 12) + 1].sorted()
                case .quarterly:  inferred = (0..<4).map { ((start - 1 + $0 * 3) % 12) + 1 }.sorted()
                default:          inferred = [start]
                }
                customMonths = Set(inferred)
            }
            isActive = e.isActive
            transferToAccount = e.transferToAccount
            showTransfer = e.transferToAccount != nil
            currencyOverride = e.currencyOverride
            bonus13Enabled = e.bonus13Enabled
            let months = e.bonus13Months
            bonus13SelectedMonths = Set(months.isEmpty ? [12] : months)
            bonusFixedEnabled = e.bonusFixedEnabled
            let fixedAmt = e.bonusFixedAmount
            bonusFixedAmountText = fixedAmt > 0 ? (fixedAmt == fixedAmt.rounded() ? "\(Int(fixedAmt))" : String(format: "%.2f", fixedAmt)) : ""
            bonusFixedMonth = e.bonusFixedMonth
            hasStartDate = e.startDate != nil
            startDate = e.startDate ?? Date()
            hasEndDate = e.endDate != nil
            endDate = e.endDate ?? Date()
        } else {
            selectedAccount = preselectedAccount
            if let preset = presetCategory {
                selectedCategory = preset
            }
            if let amt = presetAmount, amt > 0 {
                amountText = amt == amt.rounded() ? "\(Int(amt))" : String(format: "%.2f", amt)
            }
            if let n = presetNotes, !n.isEmpty {
                notes = n
            }
            if let d = presetDueDate {
                dueDate = d
            }
            if presetIsOnce {
                recurrenceMode = .once
            }
        }
    }

    private func save() {
        let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCategory = selectedCategory ?? .groceries
        let fixedBonusAmt = Double(bonusFixedAmountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let isIncome = isIncomeCategory

        // Derive stored recurrence + due info from mode
        let savedRecurrence: BudgetRecurrence
        let savedDueDay: Int
        let savedDueDate: Date
        let savedDueMonths: [Int]
        let cal = Calendar.current

        switch recurrenceMode {
        case .once:
            savedRecurrence = .once
            savedDueDay = 1
            savedDueDate = dueDate
            savedDueMonths = []
        case .monthly:
            savedRecurrence = .monthly
            savedDueDay = dueDay
            savedDueDate = dueDate
            savedDueMonths = []
        case .custom:
            let sorted = customMonths.sorted()
            savedDueMonths = sorted
            let count = sorted.count
            savedRecurrence = count >= 3 ? .quarterly : (count == 2 ? .semiannual : .yearly)
            savedDueDay = 15
            let firstMonth = sorted.first ?? 1
            let year = cal.component(.year, from: Date())
            savedDueDate = cal.date(from: DateComponents(year: year, month: firstMonth, day: 15)) ?? Date()
        }

        if let e = entry {
            e.userCategory = selectedUserCategory
            if selectedUserCategory == nil {
                e.category = resolvedCategory
            }
            e.amount = max(0, amount)
            e.account = selectedAccount
            e.recurrence = savedRecurrence
            e.dueDay = savedDueDay
            e.dueDate = savedDueDate
            e.dueMonths = savedDueMonths
            e.notes = cleanNotes
            e.isActive = isActive
            e.transferToAccount = transferToAccount
            e.currencyOverride = currencyOverride
            if isIncome {
                e.bonus13Enabled = bonus13Enabled
                e.bonus13Months = Array(bonus13SelectedMonths).sorted()
                e.bonusFixedEnabled = bonusFixedEnabled
                e.bonusFixedAmount = max(0, fixedBonusAmt)
                e.bonusFixedMonth = bonusFixedMonth
            } else {
                e.bonus13Enabled = false
                e.bonusFixedEnabled = false
            }
            e.startDate = (savedRecurrence != .once && hasStartDate) ? startDate : nil
            e.endDate = (savedRecurrence != .once && hasEndDate) ? endDate : nil
        } else {
            let newEntry = BudgetEntry(
                category: selectedUserCategory != nil ? .groceries : resolvedCategory,
                amount: max(0, amount),
                recurrence: savedRecurrence,
                dueDay: savedDueDay,
                dueDate: savedDueDate
            )
            newEntry.dueMonths = savedDueMonths
            newEntry.notes = cleanNotes
            newEntry.isActive = isActive
            newEntry.account = selectedAccount
            newEntry.userCategory = selectedUserCategory
            newEntry.transferToAccount = transferToAccount
            newEntry.currencyOverride = currencyOverride
            newEntry.profileID = activeProfileID
            newEntry.linkedGoalID = linkedGoalID
            if isIncome {
                newEntry.bonus13Enabled = bonus13Enabled
                newEntry.bonus13Months = Array(bonus13SelectedMonths).sorted()
                newEntry.bonusFixedEnabled = bonusFixedEnabled
                newEntry.bonusFixedAmount = max(0, fixedBonusAmt)
                newEntry.bonusFixedMonth = bonusFixedMonth
            }
            newEntry.startDate = (savedRecurrence != .once && hasStartDate) ? startDate : nil
            newEntry.endDate = (savedRecurrence != .once && hasEndDate) ? endDate : nil
            if let acc = selectedAccount {
                acc.budgetEntries.append(newEntry)
            }
            modelContext.insert(newEntry)
        }
    }
}

// MARK: - Category Picker

struct BudgetCategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("active_profile_id") private var activeProfileID: String = ""
    @Query(sort: \UserBudgetCategory.createdAt) private var allUserCategories: [UserBudgetCategory]

    var isEmbedded: Bool = false
    let selectedBuiltin: BudgetCategory?
    let selectedUser: UserBudgetCategory?
    let onSelectBuiltin: (BudgetCategory) -> Void
    let onSelectUser: (UserBudgetCategory) -> Void

    @State private var showingAddUserCategory = false
    @State private var userCategoryToEdit: UserBudgetCategory?
    @State private var searchText = ""

    private var isSearching: Bool { !searchText.isEmpty }

    private var userCategories: [UserBudgetCategory] {
        allUserCategories.filter { $0.profileID == activeProfileID }
    }

    private var searchBuiltins: [BudgetCategory] {
        let q = searchText.lowercased()
        return BudgetCategory.allCases.filter { cat in
            !cat.isLegacyCategory && cat.localizedName.lowercased().contains(q)
        }
    }

    private var searchUserCats: [UserBudgetCategory] {
        let q = searchText.lowercased()
        return userCategories.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        if isEmbedded {
            pickerContent
                .navigationTitle(NSLocalizedString("choose_category", comment: ""))
                .inlineNavigationTitle()
        } else {
            NavigationStack {
                pickerContent
                    .navigationTitle(NSLocalizedString("choose_category", comment: ""))
                    .inlineNavigationTitle()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                                .foregroundStyle(.primary)
                        }
                    }
            }
            .presentationDetents([.large])
        }
    }

    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private var pickerContent: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    TextField(NSLocalizedString("search_category_prompt", comment: ""), text: $searchText)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if isSearching {
                if searchBuiltins.isEmpty && searchUserCats.isEmpty {
                    Section {
                        Text(NSLocalizedString("no_results", comment: ""))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        LazyVGrid(columns: gridColumns, spacing: 10) {
                            ForEach(searchBuiltins, id: \.self) { cat in builtinCategoryCell(cat) }
                            ForEach(searchUserCats) { cat in userCategoryCell(cat) }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            } else {
                ForEach(BudgetCategoryGroup.allCases.filter { $0 != .intern }, id: \.self) { group in
                    groupSection(group)
                }
            }
            Section {
                Button {
                    showingAddUserCategory = true
                } label: {
                    Label(NSLocalizedString("new_custom_category", comment: ""), systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .sheet(isPresented: $showingAddUserCategory) {
            AddEditUserCategoryView()
        }
        .sheet(item: $userCategoryToEdit) { cat in
            AddEditUserCategoryView(category: cat)
        }
    }

    @ViewBuilder
    private func groupSection(_ group: BudgetCategoryGroup) -> some View {
        let builtins = BudgetCategory.pickerCategories(for: group)
        let cats = userCats(for: group)
        if !builtins.isEmpty || !cats.isEmpty {
            Section {
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(builtins, id: \.self) { cat in builtinCategoryCell(cat) }
                    ForEach(cats) { cat in userCategoryCell(cat) }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                HStack(spacing: 8) {
                    Image(systemName: group.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(group.color)
                    Text(group.localizedName)
                }
            }
        }
    }

    private func builtinCategoryCell(_ cat: BudgetCategory) -> some View {
        let isSelected = selectedBuiltin == cat && selectedUser == nil
        return Button {
            onSelectBuiltin(cat)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? cat.color : cat.color.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: cat.systemImage)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isSelected ? .white : cat.color)
                }
                Text(cat.localizedName)
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(isSelected ? cat.color : .primary)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func userCategoryCell(_ cat: UserBudgetCategory) -> some View {
        let isSelected = selectedUser?.id == cat.id
        return Button {
            onSelectUser(cat)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isSelected ? cat.color : cat.color.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: cat.symbolName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isSelected ? .white : cat.color)
                }
                Text(cat.name)
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(isSelected ? cat.color : .primary)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                userCategoryToEdit = cat
            } label: {
                Label(NSLocalizedString("edit", comment: ""), systemImage: "pencil")
            }
            Button(role: .destructive) {
                modelContext.delete(cat)
            } label: {
                Label(NSLocalizedString("delete", comment: ""), systemImage: "trash")
            }
        }
    }

    private func userCats(for group: BudgetCategoryGroup) -> [UserBudgetCategory] {
        switch group {
        case .einkommen:   return userCategories.filter { $0.isIncome }
        case .investieren: return userCategories.filter { !$0.isIncome && $0.isInvestment }
        case .sparen:      return userCategories.filter { !$0.isIncome && $0.isSavings && !$0.isInvestment }
        case .schulden:    return userCategories.filter { !$0.isIncome && !$0.isSavings && !$0.isInvestment && $0.groupRaw == "schulden" }
        case .fixkosten:   return userCategories.filter { !$0.isIncome && !$0.isSavings && !$0.isInvestment && $0.groupRaw == "fixkosten" }
        case .lifestyle:   return userCategories.filter { !$0.isIncome && !$0.isSavings && !$0.isInvestment && ($0.groupRaw == "lifestyle" || $0.groupRaw == "") }
        case .intern:      return []
        }
    }

}

// MARK: - Add/Edit User Category

struct AddEditUserCategoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("active_profile_id") private var activeProfileID: String = ""

    var category: UserBudgetCategory? = nil

    @State private var name: String = ""
    @State private var selectedGroup: BudgetCategoryGroup = .lifestyle
    @State private var selectedColor: CategoryColor = .blue
    @State private var symbolName: String = "tag.fill"
    @State private var showingSymbolPicker = false

    private var isNew: Bool { category == nil }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private static let groupSubtitles: [BudgetCategoryGroup: String] = [
        .einkommen:   NSLocalizedString("group_subtitle_einkommen", comment: ""),
        .schulden:    NSLocalizedString("group_subtitle_schulden", comment: ""),
        .fixkosten:   NSLocalizedString("group_subtitle_fixkosten", comment: ""),
        .lifestyle:   NSLocalizedString("group_subtitle_lifestyle", comment: ""),
        .sparen:      NSLocalizedString("group_subtitle_sparen", comment: ""),
        .investieren: NSLocalizedString("group_subtitle_investieren", comment: ""),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField(NSLocalizedString("category_name_placeholder", comment: ""), text: $name)
                }
                Section(NSLocalizedString("type_section", comment: "")) {
                    ForEach(BudgetCategoryGroup.allCases.filter { $0 != .intern }, id: \.self) { group in
                        Button {
                            selectedGroup = group
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(group.color.opacity(0.14))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Image(systemName: group.systemImage)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(group.color)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.localizedName)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    if let sub = Self.groupSubtitles[group] {
                                        Text(sub)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedGroup == group {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Symbol") {
                    Button {
                        showingSymbolPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(selectedColor.color.opacity(0.14))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: symbolName)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(selectedColor.color)
                                )
                            Text(NSLocalizedString("choose_symbol", comment: ""))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Section(NSLocalizedString("color_section", comment: "")) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 6),
                        spacing: 14
                    ) {
                        ForEach(CategoryColor.allCases, id: \.self) { colorCase in
                            Circle()
                                .fill(colorCase.color)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Group {
                                        if selectedColor == colorCase {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                )
                                .onTapGesture { selectedColor = colorCase }
                        }
                    }
                    .padding(.vertical, 6)
                }
                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            if let c = category { modelContext.delete(c) }
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Label(NSLocalizedString("delete_category", comment: ""), systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isNew
                ? NSLocalizedString("new_category", comment: "")
                : NSLocalizedString("edit_category_title", comment: ""))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }.foregroundStyle(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", comment: "")) { save(); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                        .foregroundStyle(isValid ? .primary : .secondary)
                }
            }
            .sheet(isPresented: $showingSymbolPicker) {
                SymbolPickerView(selectedSymbol: $symbolName)
            }
            .onAppear { populate() }
        }
    }

    private func populate() {
        guard let c = category else { return }
        name = c.name
        symbolName = c.symbolName
        selectedColor = c.categoryColor
        if c.isIncome { selectedGroup = .einkommen }
        else if c.isInvestment { selectedGroup = .investieren }
        else if c.isSavings { selectedGroup = .sparen }
        else { selectedGroup = BudgetCategoryGroup(rawValue: c.groupRaw) ?? .lifestyle }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let isIncomeVal    = selectedGroup == .einkommen
        let isSavingsVal   = selectedGroup == .sparen
        let isInvestVal    = selectedGroup == .investieren
        if let c = category {
            c.name = trimmed
            c.isIncome = isIncomeVal
            c.isSavings = isSavingsVal
            c.isInvestment = isInvestVal
            c.groupRaw = selectedGroup.rawValue
            c.symbolName = symbolName
            c.categoryColor = selectedColor
        } else {
            let newCat = UserBudgetCategory(
                name: trimmed,
                symbolName: symbolName,
                color: selectedColor,
                isIncome: isIncomeVal,
                isSavings: isSavingsVal,
                isInvestment: isInvestVal,
                group: selectedGroup,
                profileID: activeProfileID
            )
            modelContext.insert(newCat)
        }
    }
}

// MARK: - Symbol Picker

struct SymbolPickerView: View {
    @Binding var selectedSymbol: String
    @Environment(\.dismiss) private var dismiss

    private let symbols = [
        "tag.fill", "star.fill", "heart.fill", "bolt.fill", "cart.fill",
        "house.fill", "car.fill", "airplane", "bus.fill", "tram.fill",
        "bicycle", "figure.run", "dumbbell.fill", "fork.knife", "cup.and.saucer.fill",
        "gift.fill", "bag.fill", "pills.fill", "bandage.fill", "cross.fill",
        "book.fill", "graduationcap.fill", "pencil", "gamecontroller.fill", "tv.fill",
        "music.note", "camera.fill", "phone.fill", "wifi", "laptopcomputer",
        "creditcard.fill", "banknote.fill", "dollarsign.circle.fill", "percent", "chart.bar.fill",
        "building.2.fill", "building.columns.fill", "hammer.fill", "wrench.fill", "scissors",
        "umbrella.fill", "leaf.fill", "pawprint.fill", "paintbrush.fill", "theatermasks.fill",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 5),
                    spacing: 16
                ) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            selectedSymbol = symbol
                            dismiss()
                        } label: {
                            Image(systemName: symbol)
                                .font(.title2)
                                .frame(width: 54, height: 54)
                                .background(selectedSymbol == symbol
                                            ? Color.blue.opacity(0.15)
                                            : Color.secondary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(selectedSymbol == symbol ? .blue : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("choose_symbol_title", comment: ""))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
        }
        .presentationDetents([.large])
    }
}

#Preview {
    AddEditBudgetEntryView()
        .modelContainer(
            for: [Account.self, MonthlyEntry.self, BudgetEntry.self, UserBudgetCategory.self],
            inMemory: true
        )
}
