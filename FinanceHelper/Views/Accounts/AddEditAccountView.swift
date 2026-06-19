import SwiftUI
import SwiftData

struct AddEditAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomAccountType.createdAt) private var customTypes: [CustomAccountType]
    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    var account: Account?

    @AppStorage("default_currency") private var defaultCurrency = "EUR"
    @AppStorage("active_profile_id") private var activeProfileID: String = ""

    @State private var name: String = ""
    @State private var provider: String = ""
    @State private var type: AccountType = .girokonto
    @State private var balance: Double = 0
    @State private var balanceText: String = ""
    @State private var currency: String = ""
    @State private var growthRate: Double = 0
    @State private var kaufpreisText: String = ""
    @State private var hypothekText: String = ""
    @State private var hypothekZinssatzText: String = ""
    @State private var kaufdatum: Date = Date()
    @State private var hasKaufdatum: Bool = false
    @State private var expandedCategory: String? = nil
    @State private var selectedCustomType: CustomAccountType? = nil
    @State private var showingAddCustomType = false
    @State private var showingBankPicker = false
    @FocusState private var providerFocused: Bool

    private var isNew: Bool { account == nil }
    private var effectiveType: AccountType { selectedCustomType?.bucket.baseAccountType ?? type }

    @ViewBuilder
    private var immobilieDetailsSection: some View {
        // Objekt: Purchase details
        Section {
            LabeledContent {
                TextField("", text: $kaufpreisText)
                    .decimalPadKeyboard()
                    .multilineTextAlignment(.trailing)
                    .onChange(of: kaufpreisText) { _, v in
                        let f = filterDecimalInput(v)
                        if kaufpreisText != f { kaufpreisText = f }
                    }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("property_purchase_price", comment: ""))
                    Text("Ursprünglicher Kaufpreis der Immobilie")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(NSLocalizedString("property_purchase_date", comment: ""), isOn: $hasKaufdatum)
            if hasKaufdatum {
                DatePicker("", selection: $kaufdatum, displayedComponents: .date)
                    .labelsHidden()
            }
            LabeledContent {
                HStack(spacing: 6) {
                    TextField("2.0", value: $growthRate, format: .number.precision(.fractionLength(0...2)))
                        .decimalPadKeyboard()
                        .multilineTextAlignment(.trailing)
                    Text(NSLocalizedString("growth_rate_suffix", comment: ""))
                        .foregroundStyle(.secondary)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("property_appreciation_rate", comment: ""))
                    Text("Durchschnittliche jährl. Wertsteigerung (CH ≈ 2 %)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(NSLocalizedString("property_details", comment: ""))
        }

        // Hypothek: Financing details
        Section {
            LabeledContent {
                TextField("", text: $hypothekText)
                    .decimalPadKeyboard()
                    .multilineTextAlignment(.trailing)
                    .onChange(of: hypothekText) { _, v in
                        let f = filterDecimalInput(v)
                        if hypothekText != f { hypothekText = f }
                    }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Restschuld (Hypothek)")
                    Text("Aktuell ausstehender Hypothekbetrag")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledContent {
                HStack(spacing: 4) {
                    TextField("", text: $hypothekZinssatzText)
                        .decimalPadKeyboard()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                        .onChange(of: hypothekZinssatzText) { _, v in
                            let f = filterDecimalInput(v)
                            if hypothekZinssatzText != f { hypothekZinssatzText = f }
                        }
                    Text("%").foregroundStyle(.secondary)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hypothekarzinssatz")
                    Text("Aktueller Zinssatz deiner Hypothek")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Hypothek")
        } footer: {
            Text("Aus Zinssatz × Restschuld ÷ 12 werden die monatlichen Zinskosten automatisch berechnet.")
        }
    }

    @ViewBuilder
    private func providerChip(_ p: String) -> some View {
        Button { provider = p } label: {
            Text(p)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(provider == p ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .foregroundStyle(provider == p ? Color.accentColor : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(provider == p ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var balanceLabel: String {
        if effectiveType.isLiability { return NSLocalizedString("remaining_debt", comment: "") }
        if effectiveType == .immobilie { return NSLocalizedString("property_market_value", comment: "") }
        return NSLocalizedString("balance", comment: "")
    }

    private var suggestedProviders: [String] {
        let current = account?.id
        return allAccounts
            .filter { $0.profileID == activeProfileID && $0.id != current }
            .map { $0.provider.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    @ViewBuilder
    private func builtInTypeRow(_ t: AccountType) -> some View {
        let isSelected = type == t && selectedCustomType == nil
        Button {
            type = t
            selectedCustomType = nil
            expandedCategory = nil
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: t.systemImage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    )
                Text(t.localizedName).foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.primary)
                }
            }
        }
    }

    @ViewBuilder
    private func customTypeRow(_ ct: CustomAccountType) -> some View {
        let isSelected = selectedCustomType?.id == ct.id
        Button {
            selectedCustomType = ct
            type = ct.bucket.baseAccountType
            expandedCategory = nil
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: ct.symbolName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(ct.name).foregroundStyle(.primary)
                    Text(ct.bucket.localizedName).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.primary)
                }
            }
        }
    }

    // bucket: which AccountBucket's custom types appear in this category (nil = none)
    private var typeCategories: [(name: String, icon: String, types: [AccountType], bucket: AccountBucket?)] {
        [
            (NSLocalizedString("category_bank", comment: ""), "building.columns",
             [.girokonto, .geschaeftskonto, .sparkonto, .tagesgeld, .festgeld, .bargeld], .liquid),
            (NSLocalizedString("category_credit", comment: ""), "creditcard.fill",
             [.kreditkarte, .kredit, .autokredit], .debt),
            (NSLocalizedString("category_investment", comment: ""), "chart.line.uptrend.xyaxis",
             [.investment, .depot, .krypto], .investment),
            (NSLocalizedString("category_provision", comment: ""), "umbrella.fill",
             [.altersvorsorge], nil),
            (AccountType.immobilie.localizedName, "house.fill",
             [.immobilie], nil),
        ]
    }

    private func expandedBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { expandedCategory == name },
            set: { isOpen in expandedCategory = isOpen ? name : nil }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FormLabeledTextField(
                        label: NSLocalizedString("account_name", comment: ""),
                        placeholder: NSLocalizedString("account_name_placeholder", comment: ""),
                        text: $name
                    )
                    Button {
                        showingBankPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Text(NSLocalizedString("provider", comment: "Kontoanbieter"))
                                .foregroundStyle(.primary)
                                .fixedSize()
                            Spacer()
                            if let kb = KnownBank.all.first(where: { $0.name == provider }) {
                                if kb.hasLogoAsset {
                                    Image(kb.id)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 20)
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Color.white.clipShape(RoundedRectangle(cornerRadius: 6)))
                                } else {
                                    Text(kb.shortLabel)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                            } else if !provider.isEmpty {
                                Text(provider)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("UBS, Raiffeisen…")
                                    .foregroundStyle(Color(.placeholderText))
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    let chips = suggestedProviders
                    if !chips.isEmpty {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 90, maximum: 180), spacing: 6)],
                            alignment: .leading,
                            spacing: 6
                        ) {
                            ForEach(chips, id: \.self) { p in providerChip(p) }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Balance + Currency as separate rows so the Picker doesn't steal taps
                Section {
                    LabeledContent {
                        TextField("0", text: $balanceText)
                            .decimalPadKeyboard()
                            .multilineTextAlignment(.trailing)
                            .onChange(of: balanceText) { _, v in
                                let f = filterDecimalInput(v, allowMinus: true)
                                if balanceText != f { balanceText = f }
                            }
                    } label: {
                        if effectiveType == .immobilie {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(balanceLabel)
                                Text("Aktueller Schätzwert / Verkehrswert")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text(balanceLabel)
                        }
                    }
                    Picker(NSLocalizedString("currency", comment: ""), selection: $currency) {
                        ForEach(CurrencyService.supportedCurrencies, id: \.self) { c in
                            Text("\(CurrencyService.currencyFlags[c] ?? "") \(c)").tag(c)
                        }
                    }
                } footer: {
                    if !effectiveType.isLiability && effectiveType != .immobilie {
                        Text(NSLocalizedString("account_income_entry_hint", comment: ""))
                    }
                }

                // Immobilie-specific fields appear directly below Marktwert
                if effectiveType == .immobilie {
                    immobilieDetailsSection
                }

                // Account Type — collapsible groups with custom types integrated
                Section(NSLocalizedString("account_type", comment: "Konto-Typ")) {
                    ForEach(typeCategories, id: \.name) { category in
                        let hasSelectedBuiltIn = category.types.contains(type) && selectedCustomType == nil
                        let hasSelectedCustom = category.bucket.map { b in selectedCustomType?.bucket == b } ?? false
                        let isActive = hasSelectedBuiltIn || hasSelectedCustom

                        DisclosureGroup(isExpanded: expandedBinding(for: category.name)) {
                            ForEach(category.types, id: \.self) { t in
                                builtInTypeRow(t)
                            }
                            if let bucket = category.bucket {
                                ForEach(customTypes.filter { $0.bucket == bucket }) { ct in
                                    customTypeRow(ct)
                                }
                            }
                        } label: {
                            Label {
                                Text(category.name)
                                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                            } icon: {
                                Image(systemName: category.icon)
                                    .foregroundStyle(isActive ? Color.primary : .secondary)
                            }
                        }
                    }

                    Button {
                        showingAddCustomType = true
                    } label: {
                        Label(NSLocalizedString("create_custom_type", comment: ""), systemImage: "plus.circle")
                            .foregroundStyle(Color.accentColor)
                    }
                }

                // Liability-specific: monthly rate derived from linked budget entries (read-only)
                if effectiveType.isLiability {
                    Section {
                        if let acc = account {
                            LabeledContent(NSLocalizedString("monthly_repayment", comment: "")) {
                                Text(acc.monthlyExpenses.formatted(.currency(code: acc.currency)))
                                    .foregroundStyle(acc.monthlyExpenses > 0 ? .primary : .secondary)
                            }
                        }
                    } footer: {
                        Text(NSLocalizedString("monthly_repayment_from_entries_hint", comment: ""))
                    }
                }

                // Investment-specific: growth rate
                if effectiveType.isInvestment {
                    Section {
                        LabeledContent(NSLocalizedString("annual_growth_rate", comment: "")) {
                            HStack(spacing: 6) {
                                TextField("7.0", value: $growthRate, format: .number.precision(.fractionLength(0...2)))
                                    .decimalPadKeyboard()
                                    .multilineTextAlignment(.trailing)
                                Text(NSLocalizedString("growth_rate_suffix", comment: ""))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text(NSLocalizedString("annual_growth_rate_footer", comment: ""))
                    }
                }
            }
            .navigationTitle(isNew
                ? NSLocalizedString("add_account", comment: "")
                : NSLocalizedString("edit_account", comment: ""))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", comment: "")) {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { populateFromAccount() }
        .sheet(isPresented: $showingBankPicker) {
            BankPickerSheet(selectedName: $provider)
        }
        .sheet(isPresented: $showingAddCustomType) {
            AddCustomAccountTypeView { newType in
                selectedCustomType = newType
                type = newType.bucket.baseAccountType
                // open the category that matches the new type's bucket
                expandedCategory = typeCategories.first { $0.bucket == newType.bucket }?.name
            }
        }
    }

    private func populateFromAccount() {
        if let account {
            name = account.name
            provider = account.provider
            type = account.type
            balance = account.balance
            balanceText = account.balance == 0 ? "" : formatBalance(account.balance)
            currency = account.currency
            growthRate = account.annualGrowthRate
            selectedCustomType = account.customAccountType
            kaufpreisText = account.kaufpreis > 0 ? formatBalance(account.kaufpreis) : ""
            hypothekText = account.hypothekBetrag > 0 ? formatBalance(account.hypothekBetrag) : ""
            hypothekZinssatzText = account.hypothekZinssatz > 0 ? formatBalance(account.hypothekZinssatz) : ""
            if let kd = account.kaufdatum {
                kaufdatum = kd
                hasKaufdatum = true
            }
        } else {
            currency = defaultCurrency
            balanceText = ""
        }
        if let ct = selectedCustomType {
            expandedCategory = typeCategories.first { $0.bucket == ct.bucket }?.name
        } else {
            expandedCategory = typeCategories.first { $0.types.contains(type) }?.name
        }
    }

    private func formatBalance(_ value: Double) -> String {
        let s = String(value)
        // Trim unnecessary trailing zeros: "1000.0" → "1000", "1000.50" → "1000.5"
        if s.hasSuffix(".0") { return String(s.dropLast(2)) }
        return s
    }

    private func parsedBalanceValue() -> Double {
        let normalized = balanceText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return Double(normalized) ?? 0
    }

    private func filterDecimalInput(_ v: String, allowMinus: Bool = false) -> String {
        let allowed: (Character) -> Bool = { $0.isNumber || $0 == "." || $0 == "," || (allowMinus && $0 == "-") }
        var filtered = String(v.filter(allowed))
        let seps = filtered.filter { $0 == "." || $0 == "," }
        if seps.count > 1, let last = filtered.lastIndex(where: { $0 == "." || $0 == "," }) {
            filtered.remove(at: last)
        }
        return filtered
    }

    private func parsedKaufpreis() -> Double {
        let normalized = kaufpreisText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(normalized) ?? 0
    }

    private func parsedHypothek() -> Double {
        let normalized = hypothekText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(normalized) ?? 0
    }

    private func parsedHypothekZinssatz() -> Double {
        let normalized = hypothekZinssatzText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(normalized) ?? 0
    }

    private func save() {
        let parsedBalance = parsedBalanceValue()
        let parsedGrowthRate = max(0, growthRate)
        let usesGrowth = effectiveType.isInvestment || effectiveType == .immobilie
        if let account {
            account.name = name.trimmingCharacters(in: .whitespaces)
            account.provider = provider.trimmingCharacters(in: .whitespaces)
            account.type = effectiveType
            account.balance = parsedBalance
            account.currency = currency
            account.customAccountType = selectedCustomType
            account.annualGrowthRate = usesGrowth ? parsedGrowthRate : 0
            if effectiveType == .immobilie {
                account.kaufpreis = parsedKaufpreis()
                account.hypothekBetrag = parsedHypothek()
                account.hypothekZinssatz = parsedHypothekZinssatz()
                account.kaufdatum = hasKaufdatum ? kaufdatum : nil
            }
        } else {
            let newAccount = Account(
                name: name.trimmingCharacters(in: .whitespaces),
                type: effectiveType,
                balance: parsedBalance,
                currency: currency
            )
            newAccount.provider = provider.trimmingCharacters(in: .whitespaces)
            newAccount.customAccountType = selectedCustomType
            newAccount.annualGrowthRate = usesGrowth ? parsedGrowthRate : 0
            newAccount.profileID = activeProfileID
            if effectiveType == .immobilie {
                newAccount.kaufpreis = parsedKaufpreis()
                newAccount.hypothekBetrag = parsedHypothek()
                newAccount.hypothekZinssatz = parsedHypothekZinssatz()
                newAccount.kaufdatum = hasKaufdatum ? kaufdatum : nil
            }
            modelContext.insert(newAccount)
        }
    }
}

// MARK: - Create Custom Account Type

struct AddCustomAccountTypeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var onSave: (CustomAccountType) -> Void

    @State private var name = ""
    @State private var symbolName = "tag.fill"
    @State private var bucket: AccountBucket = .liquid

    private let symbols = [
        "tag.fill", "star.fill", "house.fill", "car.fill", "airplane", "cart.fill",
        "creditcard.fill", "banknote.fill", "building.columns.fill", "briefcase.fill",
        "gift.fill", "heart.fill", "bitcoinsign.circle.fill", "chart.line.uptrend.xyaxis",
        "gamecontroller.fill", "music.note", "book.fill", "leaf.fill",
        "wrench.and.screwdriver.fill", "camera.fill", "pills.fill", "cross.circle.fill",
        "figure.walk", "pawprint.fill", "flame.fill", "drop.fill"
    ]

    private let columns = Array(repeating: GridItem(.flexible()), count: 5)

    var body: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("account_name", comment: "")) {
                    TextField(NSLocalizedString("account_name_placeholder", comment: ""), text: $name)
                }

                Section("Symbol") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(symbols, id: \.self) { sym in
                            Button {
                                symbolName = sym
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(sym == symbolName
                                              ? Color.primary.opacity(0.12)
                                              : Color.secondary.opacity(0.08))
                                    Image(systemName: sym)
                                        .font(.system(size: 18))
                                        .foregroundStyle(sym == symbolName ? Color.primary : .secondary)
                                }
                                .frame(height: 46)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.4), lineWidth: sym == symbolName ? 2 : 0)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                }

                Section(NSLocalizedString("custom_type_bucket", comment: "Kategorie")) {
                    ForEach(AccountBucket.allCases, id: \.self) { b in
                        Button {
                            bucket = b
                        } label: {
                            HStack {
                                Label(b.localizedName, systemImage: b.systemImage)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if bucket == b {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(b.color)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("create_custom_type", comment: "Eigenen Typ erstellen…"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", comment: "")) {
                        let ct = CustomAccountType(
                            name: name.trimmingCharacters(in: .whitespaces),
                            symbolName: symbolName,
                            color: .gray,
                            bucket: bucket
                        )
                        modelContext.insert(ct)
                        onSave(ct)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Labeled text row

// Isolated view so parent form doesn't re-render on every keystroke
private struct FormLabeledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .fixedSize()
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
        }
    }
}

// MARK: - Bank Picker Sheet

struct BankPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedName: String
    @State private var searchText = ""
    @State private var customText = ""

    private let gridColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var filteredBanks: [KnownBank] {
        KnownBank.all.filter { $0.matches(searchText) }
    }

    private var isCustomSelected: Bool {
        !selectedName.isEmpty && !KnownBank.all.contains {
            $0.name.localizedCaseInsensitiveCompare(selectedName) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Bank suchen…", text: $searchText).autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        // Custom entry card — always first
                        CustomBankCard(text: $customText, isSelected: isCustomSelected) { trimmed in
                            selectedName = trimmed
                            dismiss()
                        }

                        if filteredBanks.isEmpty {
                            // Empty search result placeholder spans both columns via separate view below
                        } else {
                            ForEach(filteredBanks) { bank in
                                BankPickerCard(bank: bank, isSelected: selectedName == bank.name) {
                                    selectedName = bank.name
                                    dismiss()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)

                    if filteredBanks.isEmpty && !searchText.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "building.columns")
                                .font(.system(size: 36)).foregroundStyle(.secondary.opacity(0.5))
                            Text("Keine Bank gefunden")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { ProfilePill() }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }.foregroundStyle(.primary)
                }
            }
            .onAppear {
                if isCustomSelected { customText = selectedName }
            }
        }
    }
}

private struct CustomBankCard: View {
    @Binding var text: String
    let isSelected: Bool
    let onConfirm: (String) -> Void
    @FocusState private var isFocused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }
    private var isActive: Bool { isFocused || !trimmed.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                isActive ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.08)

                if trimmed.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "building.badge.plus")
                            .font(.title2)
                            .foregroundStyle(isFocused ? Color.accentColor : .secondary)
                        Text("Eigene Bank")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isFocused ? Color.accentColor : .secondary)
                    }
                } else {
                    Text(trimmed)
                        .font(.system(.subheadline, design: .rounded).weight(.black))
                        .foregroundStyle(Color.accentColor)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5).lineLimit(3)
                        .padding(.horizontal, 8)
                }
            }
            .frame(height: 88)
            .onTapGesture { isFocused = true }

            HStack(spacing: 6) {
                TextField("Name eingeben…", text: $text)
                    .focused($isFocused)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit {
                        guard !trimmed.isEmpty else { return }
                        onConfirm(trimmed)
                    }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.35))
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected || isActive ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: isSelected || isActive ? 2 : 1)
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isFocused)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: trimmed.isEmpty)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
    }
}

private struct BankPickerCard: View {
    let bank: KnownBank
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    Color.secondary.opacity(isSelected ? 0.12 : 0.07)
                    if bank.hasLogoAsset {
                        Image(bank.id)
                            .resizable().scaledToFit().padding(10)
                    } else {
                        Text(bank.shortLabel)
                            .font(.system(.title2, design: .rounded).weight(.black))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6).lineLimit(2)
                            .padding(.horizontal, 8)
                    }
                }
                .frame(height: 88)

                HStack(spacing: 6) {
                    Text(bank.name)
                        .font(.caption.weight(.semibold)).foregroundStyle(.primary)
                        .lineLimit(2).minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.35))
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.primary.opacity(0.5) : Color.secondary.opacity(0.25),
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
    }
}

#Preview {
    AddEditAccountView()
        .modelContainer(for: [Account.self, CustomAccountType.self], inMemory: true)
}
