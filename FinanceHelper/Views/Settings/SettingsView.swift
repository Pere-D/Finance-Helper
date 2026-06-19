import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchases
    @AppStorage("default_currency") private var defaultCurrency = "EUR"
    @AppStorage("active_profile_id") private var activeProfileID: String = ""
    @AppStorage("bg_theme")       private var rawBgTheme    = BackgroundTheme.emerald.rawValue
    @AppStorage("bg_intensity")   private var bgIntensity   = 1.0
    @AppStorage("appearance_mode") private var appearanceMode = "system"
    @AppStorage("isICloudBackupEnabled") private var isICloudEnabled = true

    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \BudgetEntry.createdAt) private var budgetEntries: [BudgetEntry]
    @Query(sort: \UserBudgetCategory.createdAt) private var userCategories: [UserBudgetCategory]
    @Query(sort: \FinancialGoal.createdAt) private var financialGoals: [FinancialGoal]
    @Query(sort: \ImportedTransaction.date, order: .reverse) private var importedTransactions: [ImportedTransaction]
    @Query(sort: \UserTransactionCategory.name) private var txCategories: [UserTransactionCategory]


    // iCloud
    @State private var syncManager = CloudKitSyncManager()

    // Paywall
    @State private var showingPaywall = false

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    // CSV / PDF export and import
    @State private var showingExportWarning = false
    @State private var showingPDFExportWarning = false
    @State private var showingCSVImporter = false
    @State private var pendingCSVData: CSVImportData?
    @State private var showingCSVImportConfirm = false
    @State private var csvImportSummary = ""
    @State private var isImporting = false

    // Feedback
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingSuccess = false
    @State private var successMessage = ""

    private var currencyDisclaimerFooter: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue.opacity(0.7))
                .font(.caption)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("currency_disclaimer_title", comment: ""))
                    .font(.caption.weight(.medium))
                Text(NSLocalizedString("currency_disclaimer_body", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: General + Währung
                Section {
                    Picker(NSLocalizedString("default_currency_label", comment: ""), selection: $defaultCurrency) {
                        ForEach(CurrencyService.supportedCurrencies, id: \.self) { c in
                            Text("\(CurrencyService.currencyFlags[c] ?? "") \(c)").tag(c)
                        }
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(CurrencyService.shared.statusColor)
                            .frame(width: 7, height: 7)
                        Text(CurrencyService.shared.statusLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let date = CurrencyService.shared.lastSyncDate {
                            Text(date, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Nie")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await CurrencyService.shared.fetchExchangeRates() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    let rateCodes = ["CHF", "USD", "EUR", "GBP"].filter { $0 != defaultCurrency }
                    if !rateCodes.isEmpty {
                        Text(rateCodes.map { CurrencyService.shared.formattedRate(from: $0, to: defaultCurrency) }.joined(separator: "  ·  "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    #if os(iOS)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Label(NSLocalizedString("change_language", comment: ""), systemImage: "globe")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    #endif
                } header: {
                    Text(NSLocalizedString("settings", comment: ""))
                } footer: {
                    currencyDisclaimerFooter
                }

                // MARK: Appearance
                Section(NSLocalizedString("appearance_section", comment: "")) {
                    HStack(spacing: 8) {
                        ForEach([("system", "circle.lefthalf.filled", NSLocalizedString("appearance_system", comment: "")),
                                 ("light",  "sun.max.fill",           NSLocalizedString("appearance_light", comment: "")),
                                 ("dark",   "moon.fill",              NSLocalizedString("appearance_dark", comment: ""))],
                                id: \.0) { mode, icon, label in
                            let selected = appearanceMode == mode
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) { appearanceMode = mode }
                            } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: icon)
                                        .font(.system(size: 17))
                                        .foregroundStyle(selected ? .primary : .secondary)
                                    Text(label)
                                        .font(.caption2.weight(selected ? .semibold : .regular))
                                        .foregroundStyle(selected ? .primary : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selected ? Color.primary.opacity(0.08) : Color.secondary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(selected ? Color.primary.opacity(0.2) : Color.clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                    // Theme color picker
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(NSLocalizedString("appearance_background", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            if !purchases.isPremium {
                                Text("Pro")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .onTapGesture { showingPaywall = true }
                            }
                        }
                        ZStack(alignment: .topTrailing) {
                            VStack(spacing: 10) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(BackgroundTheme.allCases, id: \.self) { theme in
                                            let isSelected = rawBgTheme == theme.rawValue
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.15)) { rawBgTheme = theme.rawValue }
                                            } label: {
                                                VStack(spacing: 5) {
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .fill(LinearGradient(colors: [theme.primary, theme.secondary],
                                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                                                        .frame(width: 48, height: 38)
                                                        .overlay(RoundedRectangle(cornerRadius: 10)
                                                            .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2))
                                                        .opacity(purchases.isPremium ? 1.0 : 0.35)
                                                    Text(theme.label)
                                                        .font(.caption2)
                                                        .foregroundStyle(isSelected && purchases.isPremium ? .primary : .secondary)
                                                        .fontWeight(isSelected && purchases.isPremium ? .semibold : .regular)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(!purchases.isPremium)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                HStack(spacing: 8) {
                                    Image(systemName: "sun.min").font(.caption).foregroundStyle(.secondary).frame(width: 16)
                                    Slider(value: $bgIntensity, in: 0.3...2.0, step: 0.05)
                                        .disabled(!purchases.isPremium)
                                        .opacity(purchases.isPremium ? 1.0 : 0.35)
                                    Image(systemName: "sun.max").font(.caption).foregroundStyle(.secondary).frame(width: 16)
                                    if abs(bgIntensity - 1.0) > 0.04 && purchases.isPremium {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) { bgIntensity = 1.0 }
                                        } label: {
                                            Text("↺").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .transition(.opacity.combined(with: .scale))
                                    }
                                }
                            }
                            if !purchases.isPremium {
                                Color.clear.contentShape(Rectangle()).onTapGesture { showingPaywall = true }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: Finanzdaten Export & Import
                Section("Finanzdaten") {
                    premiumRow(label: "Finanzdaten exportieren (CSV)", icon: "tablecells") {
                        if purchases.isPremium { showingExportWarning = true } else { showingPaywall = true }
                    }
                    premiumRow(label: NSLocalizedString("csv_import_button", comment: ""), icon: "tablecells.badge.ellipsis") {
                        if purchases.isPremium { showingCSVImporter = true } else { showingPaywall = true }
                    }
                    premiumRow(label: NSLocalizedString("pdf_export_button", comment: ""), icon: "doc.richtext") {
                        if purchases.isPremium { showingPDFExportWarning = true } else { showingPaywall = true }
                    }
                }

                // MARK: iCloud
                Section {
                    if purchases.isPremium {
                        Toggle(isOn: $isICloudEnabled) {
                            Label(NSLocalizedString("icloud_backup_toggle", comment: ""), systemImage: "icloud")
                        }
                        .onChange(of: isICloudEnabled) { _, newValue in
                            if newValue { Task { await syncManager.enable(context: modelContext) } }
                            else { syncManager.disable() }
                        }
                    } else {
                        Button { showingPaywall = true } label: {
                            HStack {
                                Label(NSLocalizedString("icloud_backup_toggle", comment: ""), systemImage: "icloud")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("Pro").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if syncManager.isSyncing {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.75)
                            Text(NSLocalizedString("icloud_syncing", comment: ""))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else if let date = syncManager.lastSyncDate {
                        LabeledContent(NSLocalizedString("icloud_last_sync", comment: "")) {
                            Text(date, style: .relative).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("icloud_section", comment: ""))
                } footer: {
                    if let error = syncManager.syncError {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text(NSLocalizedString("icloud_footer", comment: ""))
                    }
                }

                // MARK: Feedback
                Section("Feedback") {
                    Button {
                        let subject = "Feature Anfrage – Finance Helper"
                        let body = "Hallo,\n\nich hätte folgende Feature-Idee:\n\n"
                        let urlString = "mailto:support@financehelper.ch?subject=\(subject)&body=\(body)"
                            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: urlString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Feature anfragen", systemImage: "lightbulb.fill")
                            .foregroundStyle(.primary)
                    }
                    Button {
                        let subject = "Feedback – Finance Helper"
                        let body = "Hallo,\n\nmein Feedback:\n\n"
                        let urlString = "mailto:support@financehelper.ch?subject=\(subject)&body=\(body)"
                            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: urlString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Feedback senden", systemImage: "envelope.fill")
                            .foregroundStyle(.primary)
                    }
                }

                // MARK: Info
                Section("Info") {
                    LabeledContent("Version") {
                        Text(appVersionString)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent(NSLocalizedString("settings_plan_label", comment: "")) {
                        Text(purchases.isPremium
                             ? NSLocalizedString("paywall_col_premium", comment: "")
                             : NSLocalizedString("plan_free", comment: ""))
                            .foregroundStyle(.secondary)
                    }
                    if !purchases.isPremium {
                        Button { showingPaywall = true } label: {
                            HStack {
                                Text(NSLocalizedString("upgrade_to_premium", comment: ""))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        openURL(URL(string: "https://financehelper.ch/datenschutz/")!)
                    } label: {
                        Label("Datenschutzerklärung", systemImage: "hand.raised.fill")
                            .foregroundStyle(.primary)
                    }
                    LabeledContent("Wechselkurse") {
                        Text("ExchangeRate-API")
                            .foregroundStyle(.secondary)
                    }
                }

            }
            .navigationTitle(NSLocalizedString("settings", comment: ""))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                            Text("Zurück")
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            // CSV importer
            .fileImporter(
                isPresented: $showingCSVImporter,
                allowedContentTypes: [.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { loadCSVFile(from: url) }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            // CSV import confirmation
            .confirmationDialog(csvImportSummary, isPresented: $showingCSVImportConfirm, titleVisibility: .visible) {
                Button(NSLocalizedString("confirm_import_button", comment: ""), role: .destructive) {
                    if let data = pendingCSVData { importCSV(data) }
                }
                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) { pendingCSVData = nil }
            } message: {
                Text(NSLocalizedString("confirm_import_message", comment: ""))
            }
            .alert(NSLocalizedString("error_title", comment: ""), isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert(NSLocalizedString("import_success_title", comment: ""), isPresented: $showingSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(successMessage)
            }
            .alert(NSLocalizedString("csv_export_warning_title", comment: ""), isPresented: $showingExportWarning) {
                Button(NSLocalizedString("csv_export_confirm_button", comment: ""), role: .destructive) { exportCSV() }
                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("csv_export_warning_body", comment: ""))
            }
            .alert(NSLocalizedString("csv_export_warning_title", comment: ""), isPresented: $showingPDFExportWarning) {
                Button(NSLocalizedString("csv_export_confirm_button", comment: ""), role: .destructive) { exportPDF() }
                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("csv_export_warning_body", comment: ""))
            }
            .fullScreenCover(isPresented: $showingPaywall) {
                PaywallView().environment(purchases)
            }
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.4)
                            .tint(.white)
                        Text("Wird importiert…")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .padding(28)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        .tint(Color(.label))
        .preferredColorScheme(preferredScheme)
    }

    // MARK: - PDF Export

    private func exportPDF() {
        let filteredAccounts    = accounts.filter { $0.profileID == activeProfileID }
        let filteredEntries     = budgetEntries.filter { $0.profileID == activeProfileID }
        let filteredGoals       = financialGoals.filter { $0.profileID == activeProfileID }
        let filteredCategories  = userCategories.filter { $0.profileID == activeProfileID }
        let filteredTx          = importedTransactions.filter { $0.profileID == activeProfileID }
        let url = PDFExportManager.generateReport(
            accounts: Array(filteredAccounts),
            budgetEntries: Array(filteredEntries),
            goals: Array(filteredGoals),
            userCategories: Array(filteredCategories),
            transactions: Array(filteredTx),
            currency: defaultCurrency
        )
        presentShareSheet(items: [url])
    }

    // MARK: - CSV Export

    private func exportCSV() {
        let filteredEntries     = budgetEntries.filter { $0.profileID == activeProfileID }
        let filteredAccounts    = accounts.filter { $0.profileID == activeProfileID }
        let filteredGoals       = financialGoals.filter { $0.profileID == activeProfileID }
        let filteredCategories  = userCategories.filter { $0.profileID == activeProfileID }
        let filteredTx          = importedTransactions.filter { $0.profileID == activeProfileID }
        let filteredTxCats      = txCategories.filter { $0.profileID == activeProfileID }
        let rules               = CustomRulesStore.load(profileID: activeProfileID)
        let csv = CSVExportManager.export(
            accounts: filteredAccounts,
            entries: filteredEntries,
            goals: filteredGoals,
            userCategories: filteredCategories,
            transactions: filteredTx,
            transactionCategories: filteredTxCats,
            categoryRules: rules,
            defaultCurrency: defaultCurrency
        )
        do {
            let url = try CSVExportManager.generateTempFile(csvString: csv)
            presentShareSheet(items: [url])
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    // MARK: - CSV Import

    private func loadCSVFile(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = NSLocalizedString("file_access_denied_msg", comment: "")
            showingError = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = NSLocalizedString("file_read_error_msg", comment: "")
            showingError = true
            return
        }

        switch CSVExportManager.parse(csvString: content) {
        case .success(let data):
            pendingCSVData = data
            let catCount   = data.userCategories.count
            let txCount    = data.transactions.count
            let txCatCount = data.transactionCategories.count
            let rulesCount = data.categoryRules.count
            let total = data.accounts.count + data.budgetEntries.count + data.goals.count
                      + catCount + txCount + txCatCount + rulesCount
            var parts = [
                String(format: NSLocalizedString("%lld Konten", comment: ""), data.accounts.count),
                String(format: NSLocalizedString("%lld Einträge", comment: ""), data.budgetEntries.count),
                String(format: NSLocalizedString("%lld Ziele", comment: ""), data.goals.count)
            ]
            if catCount   > 0 { parts.append(String(format: NSLocalizedString("%lld Kategorien", comment: ""), catCount)) }
            if txCount    > 0 { parts.append(String(format: NSLocalizedString("%lld Transaktionen", comment: ""), txCount)) }
            if txCatCount > 0 { parts.append(String(format: NSLocalizedString("%lld Tx-Kategorien", comment: ""), txCatCount)) }
            if rulesCount > 0 { parts.append(String(format: NSLocalizedString("%lld Regeln", comment: ""), rulesCount)) }
            csvImportSummary = String(format: NSLocalizedString("%lld Datensätze (%@)", comment: ""), total, parts.joined(separator: ", "))
            showingCSVImportConfirm = true
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func importCSV(_ data: CSVImportData) {
        isImporting = true
        pendingCSVData = nil
        // Snapshot query results before the Task so SwiftData doesn't fetch on a background thread
        let existingEntries  = Array(budgetEntries.filter { $0.profileID == activeProfileID })
        let existingAccounts = Array(accounts.filter { $0.profileID == activeProfileID })
        let existingGoals    = Array(financialGoals.filter { $0.profileID == activeProfileID })
        let existingTx       = Array(importedTransactions.filter { $0.profileID == activeProfileID })
        let existingTxCats   = Array(txCategories.filter { $0.profileID == activeProfileID })
        let existingCats     = Array(userCategories)
        let pid              = activeProfileID
        Task {
            do {
                let result = try CSVExportManager.importData(
                    data,
                    into: modelContext,
                    profileID: pid,
                    existingAccounts: existingAccounts,
                    existingEntries: existingEntries,
                    existingCategories: existingCats,
                    existingGoals: existingGoals,
                    existingTransactions: existingTx,
                    existingTxCategories: existingTxCats
                )
                var parts = [
                    String(format: NSLocalizedString("%lld Einträge", comment: ""), result.entries),
                    String(format: NSLocalizedString("%lld Konten", comment: ""), result.accounts),
                    String(format: NSLocalizedString("%lld Ziele", comment: ""), result.goals)
                ]
                if result.categories > 0           { parts.append(String(format: NSLocalizedString("%lld Kategorien", comment: ""), result.categories)) }
                if result.transactions > 0         { parts.append(String(format: NSLocalizedString("%lld Transaktionen", comment: ""), result.transactions)) }
                if result.transactionCategories > 0 { parts.append(String(format: NSLocalizedString("%lld Tx-Kategorien", comment: ""), result.transactionCategories)) }
                if result.categoryRules > 0        { parts.append(String(format: NSLocalizedString("%lld Regeln", comment: ""), result.categoryRules)) }
                successMessage = String(format: NSLocalizedString("%@ importiert", comment: ""), parts.joined(separator: ", "))
                showingSuccess = true
                if result.categoryRules > 0 {
                    NotificationCenter.default.post(name: .categoryRulesDidImport, object: nil)
                }
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
            isImporting = false
        }
    }

    // MARK: - Reusable row helpers

    @ViewBuilder
    private func premiumRow(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: icon).foregroundStyle(.primary)
                if !purchases.isPremium {
                    Spacer()
                    Text("Pro").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Share sheet (UIKit direct presentation — avoids SwiftUI sheet/UIKit conflict)

    private func presentShareSheet(items: [Any]) {
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              let rootVC = window.rootViewController else { return }
        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        topVC.present(activityVC, animated: true)
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Account.self, MonthlyEntry.self, BudgetEntry.self, UserBudgetCategory.self, UserProfile.self, FinancialGoal.self, CustomAccountType.self, HealthScoreSettings.self], inMemory: true)
}
