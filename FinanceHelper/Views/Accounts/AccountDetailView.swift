import SwiftUI
import SwiftData

struct AccountDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var account: Account
    @State private var showingDeleteAccountConfirm = false
    @State private var showingAddBudgetEntry = false
    @State private var showingEditAccount = false
    @State private var budgetEntryToEdit: BudgetEntry?


    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    var body: some View {
        List {
            if account.type == .immobilie {
                immobilieNettoSection
                immobilieFinanzierungSection
                immobilie3aSection
                immobilieObjektSection
            } else {
                balanceSection
            }
            budgetEntriesSection
            deleteSection
        }
        .scrollContentBackground(.hidden)
        .background(AnimatedPatternBackground())
        .navigationTitle(account.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingEditAccount = true } label: {
                    Image(systemName: "square.and.pencil")
                }
                .foregroundStyle(Color(.label))
            }
        }
        .alert(NSLocalizedString("delete_account_confirm_title", comment: ""),
               isPresented: $showingDeleteAccountConfirm) {
            Button(NSLocalizedString("delete_account_confirm_button", comment: ""), role: .destructive) {
                modelContext.delete(account)
                dismiss()
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("delete_account_confirm_message", comment: ""))
        }
        .sheet(isPresented: $showingAddBudgetEntry) {
            AddEditBudgetEntryView(preselectedAccount: account)
        }
        .sheet(item: $budgetEntryToEdit) { entry in
            AddEditBudgetEntryView(entry: entry, preselectedAccount: account)
        }
        .sheet(isPresented: $showingEditAccount) {
            AddEditAccountView(account: account)
        }
    }

    // MARK: - Immobilie Sections

    // Legacy: separate Hypothek accounts in the same profile (backward compat)
    private var profileHypotheken: [Account] {
        guard account.hypothekBetrag == 0 else { return [] }
        return allAccounts.filter { $0.profileID == account.profileID && $0.type == .hypothek && $0.balance > 0 }
    }

    private var profileVorsorgeAccounts: [Account] {
        allAccounts.filter { $0.profileID == account.profileID && $0.type == .altersvorsorge }
    }

    private var linked3aAccount: Account? {
        guard !account.linked3aAccountID.isEmpty else { return nil }
        return allAccounts.first { $0.id.uuidString == account.linked3aAccountID }
    }

    private var profileMonthlyIncome: Double {
        allAccounts
            .filter { $0.profileID == account.profileID }
            .reduce(0) { $0 + $1.monthlyIncome }
    }

    // Monthly housing cost base for Tragbarkeit: actual entries or estimated from Zinssatz + 1% Nebenkosten
    private var tragbarkeitBase: Double {
        if account.monthlyExpenses > 0 { return account.monthlyExpenses }
        if account.monatlicheHypothekZinsen > 0 {
            return account.monatlicheHypothekZinsen + (account.balance * 0.01 / 12)
        }
        return 0
    }

    private var equity3aAdjusted: Double {
        let totalHypothek = account.hypothekBetrag > 0
            ? account.hypothekBetrag
            : profileHypotheken.reduce(0.0) { $0 + $1.balance }
        return (account.balance - totalHypothek) + (linked3aAccount?.balance ?? 0)
    }

    private var belehnungsgrad3aAdjusted: Double {
        guard account.balance > 0 else { return 0 }
        let totalHypothek = account.hypothekBetrag > 0
            ? account.hypothekBetrag
            : profileHypotheken.reduce(0.0) { $0 + $1.balance }
        return max(0, totalHypothek - (linked3aAccount?.balance ?? 0)) / account.balance * 100
    }

    // MARK: Netto-Position

    private var immobilieNettoSection: some View {
        Section {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(account.effectiveColor.opacity(0.12))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: account.effectiveSystemImage)
                            .font(.body)
                            .foregroundStyle(account.effectiveColor)
                    )
                TextField(NSLocalizedString("account_name_placeholder", comment: ""), text: $account.name)
                    .font(.body.weight(.medium))
                Text(account.effectiveDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(account.effectiveColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(account.effectiveColor.opacity(0.12))
                    .clipShape(Capsule())
                    .lineLimit(1)
            }
            .padding(.vertical, 2)

            // Marktwert (editable)
            HStack {
                Text(NSLocalizedString("property_market_value", comment: ""))
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("0.00", value: $account.balance, format: .number)
                    .decimalPadKeyboard()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)

            // Restschuld / Hypothek (editable)
            HStack {
                Text("Restschuld (Hypothek)")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("", value: $account.hypothekBetrag, format: .number)
                    .decimalPadKeyboard()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                    .foregroundStyle(account.hypothekBetrag > 0 ? .red : .secondary)
            }
            .font(.subheadline)

            // Legacy: separate Hypothek accounts (backward compat)
            if account.hypothekBetrag == 0 {
                ForEach(profileHypotheken) { hypo in
                    HStack {
                        Label(hypo.name.isEmpty ? "Hypothek" : hypo.name,
                              systemImage: AccountType.hypothek.systemImage)
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(hypo.balance.formatted(.currency(code: account.currency)))
                            .font(.subheadline.weight(.medium)).foregroundStyle(.red)
                    }
                }
            }

            // Netto-Vermögen (prominent computed)
            let totalH = account.hypothekBetrag > 0
                ? account.hypothekBetrag
                : profileHypotheken.reduce(0.0) { $0 + $1.balance }
            let nettoVermoegen = account.balance - totalH
            HStack {
                Text("Netto-Vermögen")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(nettoVermoegen.formatted(.currency(code: account.currency)))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(nettoVermoegen >= 0 ? .green : .red)
                    .contentTransition(.numericText())
            }

            // Monatlicher Cashflow
            HStack {
                Text(NSLocalizedString("monthly_cash_flow", comment: ""))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(account.monthlyCashFlow.formatted(.currency(code: account.currency)))
                    .fontWeight(.semibold)
                    .foregroundStyle(account.monthlyCashFlow >= 0 ? .green : .red)
                    .contentTransition(.numericText())
            }
            .font(.subheadline)

            Picker(NSLocalizedString("currency", comment: ""), selection: $account.currency) {
                ForEach(CurrencyService.supportedCurrencies, id: \.self) { c in
                    Text("\(CurrencyService.currencyFlags[c] ?? "") \(c)").tag(c)
                }
            }
        } header: {
            Text(NSLocalizedString("account_overview", comment: ""))
        }
    }

    // MARK: Finanzierung

    @ViewBuilder
    private var immobilieFinanzierungSection: some View {
        let totalHypothek: Double = account.hypothekBetrag > 0
            ? account.hypothekBetrag
            : profileHypotheken.reduce(0.0) { $0 + $1.balance }
        let belehnungsgrad = account.balance > 0 ? totalHypothek / account.balance * 100 : 0.0
        let tragbarkeitRatio = profileMonthlyIncome > 0 && tragbarkeitBase > 0
            ? tragbarkeitBase / profileMonthlyIncome
            : 0.0
        Section {
            // Zinssatz (editable)
            HStack {
                Text("Zinssatz")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("", value: $account.hypothekZinssatz, format: .number.precision(.fractionLength(0...2)))
                    .decimalPadKeyboard()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 60)
                    .foregroundStyle(account.hypothekZinssatz > 0 ? .primary : .secondary)
                Text("%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            // Monatliche Zinsen (computed)
            if account.monatlicheHypothekZinsen > 0 {
                HStack {
                    Text("Monatl. Zinsen")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(account.monatlicheHypothekZinsen.formatted(.currency(code: account.currency)))
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                        .contentTransition(.numericText())
                }
                .font(.subheadline)
            }

            // Belehnungsgrad (LTV)
            if totalHypothek > 0 && account.balance > 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Belehnungsgrad")
                        Text("Empfehlung: max. 80 %")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.1f %%", belehnungsgrad))
                        .fontWeight(.semibold)
                        .foregroundStyle(belehnungsgrad > 80 ? .red : belehnungsgrad > 66 ? .orange : .green)
                        .contentTransition(.numericText())
                }
                .font(.subheadline)
            }

            // Tragbarkeit
            if tragbarkeitRatio > 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tragbarkeit")
                        Text("Empfehlung: max. 33 %")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.1f %%", tragbarkeitRatio * 100))
                        .fontWeight(.semibold)
                        .foregroundStyle(tragbarkeitRatio > 0.33 ? .red : tragbarkeitRatio > 0.25 ? .orange : .green)
                        .contentTransition(.numericText())
                }
                .font(.subheadline)
            }
        } header: {
            Text("Finanzierung")
        } footer: {
            if account.monthlyExpenses == 0 && tragbarkeitBase > 0 {
                Text("Tragbarkeit basiert auf einer Schätzung. Füge Einträge (Zinsen, Nebenkosten) hinzu für genaue Werte.")
                    .font(.caption)
            }
        }
    }

    // MARK: Indirekte Amortisation

    @ViewBuilder
    private var immobilie3aSection: some View {
        let vorsorge = profileVorsorgeAccounts
        let linked = linked3aAccount
        Section {
            if vorsorge.isEmpty {
                Text("Kein Vorsorgekonto (3a) vorhanden.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Picker("Verknüpfte 3a", selection: $account.linked3aAccountID) {
                    Text("Keine").tag("")
                    ForEach(vorsorge) { acc in
                        Text(acc.name.isEmpty ? "3a Konto" : acc.name).tag(acc.id.uuidString)
                    }
                }
            }
            if let linked {
                HStack {
                    Text("3a Guthaben")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(linked.balance.formatted(.currency(code: account.currency)))
                        .fontWeight(.semibold).foregroundStyle(.teal)
                        .contentTransition(.numericText())
                }
                .font(.subheadline)
                HStack {
                    Text("Eigenkapital inkl. 3a")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(equity3aAdjusted.formatted(.currency(code: account.currency)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(equity3aAdjusted >= 0 ? .green : .red)
                        .contentTransition(.numericText())
                }
                if account.balance > 0 && account.hypothekBetrag > 0 {
                    HStack {
                        Text("Belehnungsgrad inkl. 3a")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f %%", belehnungsgrad3aAdjusted))
                            .fontWeight(.semibold)
                            .foregroundStyle(belehnungsgrad3aAdjusted > 80 ? .red : belehnungsgrad3aAdjusted > 66 ? .orange : .green)
                            .contentTransition(.numericText())
                    }
                    .font(.subheadline)
                }
            }
        } header: {
            Text("Indirekte Amortisation")
        } footer: {
            Text("Bei der indirekten Amortisation wird Vorsorgekapital (3a) angespart und bei Fälligkeit zur Hypothektilgung eingesetzt.")
                .font(.caption)
        }
    }

    // MARK: Objekt

    @ViewBuilder
    private var immobilieObjektSection: some View {
        Section {
            HStack {
                Text(NSLocalizedString("property_purchase_price", comment: ""))
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("0.00", value: $account.kaufpreis, format: .number)
                    .decimalPadKeyboard()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            if account.kaufpreis > 0 {
                let gain = account.balance - account.kaufpreis
                let gainPct = gain / account.kaufpreis * 100
                HStack {
                    Text(NSLocalizedString("property_value_gain", comment: ""))
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(gain.formatted(.currency(code: account.currency)))
                            .fontWeight(.semibold)
                            .foregroundStyle(gain >= 0 ? .green : .red)
                            .contentTransition(.numericText())
                        Text(String(format: gain >= 0 ? "+%.1f%%" : "%.1f%%", gainPct))
                            .font(.caption)
                            .foregroundStyle(gain >= 0 ? .green : .red)
                            .contentTransition(.numericText())
                    }
                }
                .font(.subheadline)
            }

            if let kd = account.kaufdatum {
                HStack {
                    Text(NSLocalizedString("property_purchase_date", comment: ""))
                        .foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("", selection: Binding(
                        get: { kd },
                        set: { account.kaufdatum = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                }
                .font(.subheadline)
            }

            HStack {
                Text(NSLocalizedString("property_appreciation_rate", comment: ""))
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("2.0", value: $account.annualGrowthRate, format: .number.precision(.fractionLength(0...2)))
                    .decimalPadKeyboard()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 60)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                Text("%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        } header: {
            Text(NSLocalizedString("property_details", comment: ""))
        }
    }

    // MARK: - Balance Section

    private var balanceSection: some View {
        Section {
            // Icon + name + category pill
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(account.effectiveColor.opacity(0.12))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: account.effectiveSystemImage)
                            .font(.body)
                            .foregroundStyle(account.effectiveColor)
                    )
                TextField(NSLocalizedString("account_name_placeholder", comment: ""), text: $account.name)
                    .font(.body.weight(.medium))
                Text(account.effectiveDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(account.effectiveColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(account.effectiveColor.opacity(0.12))
                    .clipShape(Capsule())
                    .lineLimit(1)
            }
            .padding(.vertical, 2)

            // Provider (editable)
            HStack {
                Text(NSLocalizedString("provider", comment: ""))
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("UBS, Raiffeisen…", text: $account.provider)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .foregroundStyle(.primary)
            }
            .font(.subheadline)

            // Balance (editable)
            HStack {
                Text(account.type.isLiability
                     ? NSLocalizedString("remaining_debt", comment: "")
                     : NSLocalizedString("current_balance", comment: ""))
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("0.00", value: $account.balance, format: .number)
                    .decimalPadKeyboard()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .foregroundStyle(account.type.isLiability ? .red : .primary)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)

            // Currency (editable)
            Picker(NSLocalizedString("currency", comment: ""), selection: $account.currency) {
                ForEach(CurrencyService.supportedCurrencies, id: \.self) { c in
                    Text("\(CurrencyService.currencyFlags[c] ?? "") \(c)").tag(c)
                }
            }

            if account.type.isLiability {
                HStack {
                    Text(NSLocalizedString("monthly_repayment", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(account.monthlyExpenses.formatted(.currency(code: account.currency))
                         + " / " + NSLocalizedString("month_abbrev", comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(account.monthlyExpenses > 0 ? .primary : .secondary)
                }
                if let months = account.estimatedPayoffMonths {
                    HStack {
                        Text(NSLocalizedString("payoff_estimate", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: NSLocalizedString("payoff_in_months", comment: ""), months))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                HStack {
                    Text(NSLocalizedString("monthly_cash_flow", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(account.monthlyCashFlow.formatted(.currency(code: account.currency)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(account.monthlyCashFlow >= 0 ? .green : .red)
                        .contentTransition(.numericText())
                }
            }

            if account.type.isInvestment {
                HStack {
                    Text(NSLocalizedString("annual_growth_rate", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("7.0", value: $account.annualGrowthRate, format: .number)
                        .decimalPadKeyboard()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 60)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                    Text("%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(NSLocalizedString("account_overview", comment: ""))
        }
    }

    // MARK: - Budget Entries Section

    private var activeBudgetEntries: [BudgetEntry] {
        let outgoing = account.budgetEntries.filter(\.isActive)
        let incoming = account.incomingBudgetTransfers.filter(\.isActive)
        return (outgoing + incoming)
            .sorted {
                if $0.isDueThisMonth != $1.isDueThisMonth { return $0.isDueThisMonth }
                return $0.amount > $1.amount
            }
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteAccountConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Label(NSLocalizedString("delete_account_confirm_button", comment: ""), systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(.red)
                .padding(.vertical, 4)
            }
        }
        .listRowBackground(Color.red.opacity(0.08))
    }

    private var budgetEntriesSection: some View {
        Section {
            if activeBudgetEntries.isEmpty {
                Text(NSLocalizedString("no_planned_entries", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeBudgetEntries) { entry in
                    BudgetEntryRow(entry: entry, defaultCurrency: account.currency, showAccountName: false)
                        .contentShape(Rectangle())
                        .onTapGesture { budgetEntryToEdit = entry }
                }
                .onDelete { offsets in
                    withAnimation {
                        offsets.forEach { modelContext.delete(activeBudgetEntries[$0]) }
                    }
                }
            }

            Button {
                showingAddBudgetEntry = true
            } label: {
                Label(NSLocalizedString("plan_entry", comment: ""), systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Text(NSLocalizedString("budget_entries_section", comment: ""))
                Spacer()
                if !activeBudgetEntries.isEmpty {
                    let thisMonth = activeBudgetEntries.filter(\.isDueThisMonth)
                    if !thisMonth.isEmpty {
                        Text(String(format: NSLocalizedString("due_this_month_count", comment: ""), thisMonth.count))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        } footer: {
            if !activeBudgetEntries.isEmpty {
                let inflow = activeBudgetEntries.filter {
                    ($0.account?.id == account.id && $0.isIncomeEntry) ||
                    ($0.transferToAccount?.id == account.id)
                }.reduce(0) { $0 + $1.effectiveMonthlyAmount }
                let savings = activeBudgetEntries.filter {
                    $0.account?.id == account.id && $0.isSavingsEntry
                }.reduce(0) { $0 + $1.effectiveMonthlyAmount }
                let expenses = activeBudgetEntries.filter {
                    $0.account?.id == account.id && !$0.isIncomeEntry && !$0.isSavingsEntry && $0.transferToAccount == nil
                }.reduce(0) { $0 + $1.effectiveMonthlyAmount }
                if inflow > 0 || savings > 0 || expenses > 0 {
                    HStack(spacing: 12) {
                        if inflow > 0 {
                            Text("+\(inflow.formatted(.currency(code: account.currency)))")
                                .foregroundStyle(.green)
                                .contentTransition(.numericText())
                        }
                        if savings > 0 {
                            Text("\(NSLocalizedString("budget_category_savings", comment: "")): \(savings.formatted(.currency(code: account.currency)))")
                                .foregroundStyle(.teal)
                                .contentTransition(.numericText())
                        }
                        if expenses > 0 {
                            Text("−\(expenses.formatted(.currency(code: account.currency)))")
                                .foregroundStyle(.red)
                                .contentTransition(.numericText())
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AccountDetailView(account: Account(name: "Girokonto", type: .girokonto, balance: 3500, currency: "EUR"))
    }
    .modelContainer(for: [Account.self, MonthlyEntry.self], inMemory: true)
}
