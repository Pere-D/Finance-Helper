import SwiftUI
import SwiftData

private let accountTypeOrder: [AccountType] = [
    .girokonto, .geschaeftskonto, .bargeld,
    .sparkonto, .tagesgeld, .festgeld,
    .investment, .depot, .krypto, .altersvorsorge,
    .immobilie,
    .kreditkarte, .kredit, .autokredit, .hypothek
]

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases
    @Query(sort: \Account.createdAt) private var allAccounts: [Account]
    @AppStorage("active_profile_id") private var activeProfileID: String = ""
    @AppStorage("default_currency") private var defaultCurrency = "EUR"
    @State private var showingAddAccount  = false
    @State private var showingKassensturz = false
    @State private var showingPaywall = false

    private var accounts: [Account] { allAccounts.filter { $0.profileID == activeProfileID } }

    private var groupedAccounts: [(AccountType, [Account])] {
        var dict: [AccountType: [Account]] = [:]
        for account in accounts { dict[account.type, default: []].append(account) }
        return accountTypeOrder.compactMap { type in
            guard let group = dict[type], !group.isEmpty else { return nil }
            return (type, group)
        }
    }

    private var totalAssets: Double {
        accounts.filter { !$0.type.isLiability && $0.isVisible }
            .reduce(0) { $0 + max(0, $1.balance) }
    }

    private var totalLiabilities: Double {
        let fromLiabilities = accounts.filter { $0.type.isLiability && $0.isVisible }
            .reduce(0) { $0 + max(0, $1.balance) }
        let fromImmobilien = accounts.filter { $0.type == .immobilie && $0.isVisible }
            .reduce(0) { $0 + max(0, $1.hypothekBetrag) }
        return fromLiabilities + fromImmobilien
    }

    private var netWorth: Double { totalAssets - totalLiabilities }

    var body: some View {
        NavigationStack {
            Group {
                if accounts.isEmpty {
                    emptyState
                } else {
                    contentList
                }
            }
            .background(AnimatedPatternBackground())
            .navigationTitle(NSLocalizedString("accounts", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                            Text("Zurück")
                        }
                        .foregroundStyle(Color(.label))
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 16) {
                        if !accounts.isEmpty {
                            Button { showingKassensturz = true } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(Color(.label))
                            }
                        }
                        Button { attemptAddAccount() } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(Color(.label))
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                AddEditAccountView()
            }
            .sheet(isPresented: $showingKassensturz) {
                KassensturzSheet(accounts: accounts)
            }
            .fullScreenCover(isPresented: $showingPaywall) {
                PaywallView().environment(purchases)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "creditcard")
                .font(.system(size: 52))
                .foregroundStyle(.secondary.opacity(0.5))
            VStack(spacing: 6) {
                Text(NSLocalizedString("no_accounts", comment: ""))
                    .font(.title3.weight(.semibold))
                Text(NSLocalizedString("add_first_account", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button { attemptAddAccount() } label: {
                Label(NSLocalizedString("add_account", comment: ""), systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.blue).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Content

    private var contentList: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard
                ForEach(groupedAccounts, id: \.0) { type, group in
                    accountGroupCard(type: type, accounts: group)
                }
                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Gesamtvermögen", systemImage: "chart.bar.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: NSLocalizedString("accounts_count_fmt", comment: ""), accounts.count))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            Text(netWorth.formatted(.currency(code: defaultCurrency)))
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(netWorth >= 0 ? Color.primary : Color.red)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.numericText())
            if totalLiabilities > 0 {
                Divider().padding(.vertical, 2)
                HStack(spacing: 14) {
                    summaryStat(label: "Vermögen", value: totalAssets, color: .green)
                    Divider().frame(height: 32)
                    summaryStat(label: "Schulden", value: -totalLiabilities, color: .red)
                }
            }
        }
        .padding(16)
        .cardStyle(cornerRadius: 14)
    }

    private func summaryStat(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.formatted(.currency(code: defaultCurrency).notation(.compactName)))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Account group card

    private func accountGroupCard(type: AccountType, accounts: [Account]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: type.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(type.typeColor)
                Text(type.localizedName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(accounts.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            Divider().padding(.leading, 14)
            ForEach(Array(accounts.enumerated()), id: \.element.id) { idx, account in
                NavigationLink(destination: AccountDetailView(account: account)) {
                    AccountRow(account: account)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        withAnimation { modelContext.delete(account) }
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
                if idx < accounts.count - 1 {
                    Divider().padding(.leading, 70)
                }
            }
        }
        .cardStyle(cornerRadius: 14)
    }

    private func attemptAddAccount() {
        if !purchases.isPremium && accounts.count >= 3 {
            showingPaywall = true
        } else {
            showingAddAccount = true
        }
    }
}

// MARK: - Account Row

struct AccountRow: View {
    @Bindable var account: Account

    var body: some View {
        HStack(spacing: 14) {
            let knownBank = KnownBank.forProvider(account.provider)
            ZStack {
                if let kb = knownBank, kb.hasLogoAsset {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(knownBank.map { $0.brandColor.opacity(account.isVisible ? 0.12 : 0.06) }
                              ?? account.effectiveColor.opacity(account.isVisible ? 0.12 : 0.06))
                }
                if let kb = knownBank, kb.hasLogoAsset {
                    Image(kb.id)
                        .resizable().scaledToFit()
                        .padding(6)
                        .opacity(account.isVisible ? 1.0 : 0.4)
                } else if let kb = knownBank {
                    Text(kb.shortLabel)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(account.isVisible ? kb.brandColor : kb.brandColor.opacity(0.4))
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .padding(4)
                } else {
                    Image(systemName: account.effectiveSystemImage)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(account.isVisible ? account.effectiveColor : account.effectiveColor.opacity(0.4))
                }
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(account.isVisible ? .primary : .secondary)
                let provider = account.provider.trimmingCharacters(in: .whitespaces)
                if !provider.isEmpty {
                    Text(provider)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if account.type.isLiability {
                VStack(alignment: .trailing, spacing: 2) {
                    Text((-account.balance).formatted(.currency(code: account.currency)))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.red)
                        .contentTransition(.numericText())
                    if account.monthlyExpenses > 0 {
                        Text(account.monthlyExpenses.formatted(.currency(code: account.currency))
                             + " / " + NSLocalizedString("month_abbrev", comment: ""))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    if let months = account.estimatedPayoffMonths {
                        Text(String(format: NSLocalizedString("payoff_in_months", comment: ""), months))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            } else if account.type == .immobilie && account.hypothekBetrag > 0 {
                // Show equity (Netto-Vermögen) as the primary figure
                VStack(alignment: .trailing, spacing: 2) {
                    Text((account.balance - account.hypothekBetrag).formatted(.currency(code: account.currency)))
                        .font(.body.weight(.semibold))
                        .foregroundStyle((account.balance - account.hypothekBetrag) >= 0 ? Color.primary : .red)
                        .contentTransition(.numericText())
                    Text("Marktwert \(account.balance.formatted(.currency(code: account.currency).notation(.compactName)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(account.balance.formatted(.currency(code: account.currency)))
                        .font(.body.weight(.semibold))
                        .contentTransition(.numericText())
                    if account.monthlyCashFlow != 0 {
                        HStack(spacing: 2) {
                            Image(systemName: account.monthlyCashFlow >= 0 ? "arrow.up" : "arrow.down")
                                .font(.caption2)
                            Text(abs(account.monthlyCashFlow).formatted(.currency(code: account.currency)))
                                .font(.caption2)
                                .contentTransition(.numericText())
                        }
                        .foregroundStyle(account.monthlyCashFlow >= 0 ? .green : .red)
                    }
                }
            }
            Button {
                account.isVisible.toggle()
            } label: {
                Image(systemName: account.isVisible ? "eye" : "eye.slash")
                    .font(.body.weight(.medium))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(account.isVisible ? Color.secondary : Color.secondary.opacity(0.5))
                    .frame(width: 36, height: 36)
                    .background(account.isVisible ? Color.clear : Color.secondary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    AccountsView()
        .modelContainer(for: [Account.self, MonthlyEntry.self, BudgetEntry.self, UserProfile.self], inMemory: true)
}
