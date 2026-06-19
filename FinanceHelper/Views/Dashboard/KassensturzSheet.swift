import SwiftUI

struct KassensturzSheet: View {
    @Environment(\.dismiss) private var dismiss
    let accounts: [Account]

    @State private var editedBalances: [UUID: String] = [:]

    private var liquidAccounts:     [Account] { accounts.filter { $0.type.isLiquid || $0.type == .festgeld } }
    private var investmentAccounts: [Account] { accounts.filter { $0.type.isInvestment } }
    private var liabilityAccounts:  [Account] { accounts.filter { $0.type.isLiability } }

    private var totalDelta: Double {
        accounts.reduce(0) { sum, acc in
            let text = editedBalances[acc.id] ?? ""
            let val = Double(text.replacingOccurrences(of: ",", with: ".")) ?? acc.balance
            return sum + (val - acc.balance)
        }
    }

    private var hasDelta: Bool {
        accounts.contains { acc in
            let text = editedBalances[acc.id] ?? ""
            let val = Double(text.replacingOccurrences(of: ",", with: ".")) ?? acc.balance
            return val != acc.balance
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !liquidAccounts.isEmpty {
                    Section(NSLocalizedString("bucket_liquid", comment: "")) {
                        ForEach(liquidAccounts) { account in
                            KassensturzRow(account: account, editedText: balanceBinding(for: account))
                        }
                    }
                }
                if !investmentAccounts.isEmpty {
                    Section(NSLocalizedString("bucket_investment", comment: "")) {
                        ForEach(investmentAccounts) { account in
                            KassensturzRow(account: account, editedText: balanceBinding(for: account))
                        }
                    }
                }
                if !liabilityAccounts.isEmpty {
                    Section(NSLocalizedString("bucket_debt", comment: "")) {
                        ForEach(liabilityAccounts) { account in
                            KassensturzRow(account: account, editedText: balanceBinding(for: account))
                        }
                    }
                }
                if hasDelta {
                    Section {
                        HStack {
                            Text(NSLocalizedString("total_delta", comment: ""))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            let prefix = totalDelta >= 0 ? "+" : ""
                            Text(prefix + totalDelta.formatted(.currency(code: accounts.first?.currency ?? "EUR")))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(totalDelta >= 0 ? .green : .red)
                                .contentTransition(.numericText())
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("kassensturz", comment: ""))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", comment: "")) {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .disabled(!hasDelta)
                }
            }
        }
        .onAppear { initBalances() }
    }

    private func balanceBinding(for account: Account) -> Binding<String> {
        Binding(
            get: { editedBalances[account.id] ?? formatBalance(account.balance) },
            set: { editedBalances[account.id] = $0 }
        )
    }

    private func formatBalance(_ value: Double) -> String {
        let formatted = String(value)
        return formatted
    }

    private func initBalances() {
        for account in accounts {
            editedBalances[account.id] = formatBalance(account.balance)
        }
    }

    private func saveChanges() {
        for account in accounts {
            guard let text = editedBalances[account.id],
                  let newBalance = Double(text.replacingOccurrences(of: ",", with: "."))
            else { continue }
            account.balance = newBalance
        }
    }
}

// MARK: - Row

struct KassensturzRow: View {
    let account: Account
    @Binding var editedText: String

    private var parsedValue: Double {
        Double(editedText.replacingOccurrences(of: ",", with: ".")) ?? account.balance
    }

    private var delta: Double { parsedValue - account.balance }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(account.type.typeColor.opacity(0.12))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: account.type.systemImage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(account.type.typeColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.subheadline)
                if abs(delta) > 0.001 {
                    let prefix = delta >= 0 ? "+" : ""
                    Text(prefix + delta.formatted(.currency(code: account.currency)))
                        .font(.caption2)
                        .foregroundStyle(delta >= 0 ? .green : .red)
                        .contentTransition(.numericText())
                }
            }

            Spacer()

            TextField("0.00", text: $editedText)
                .decimalPadKeyboard()
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(abs(delta) > 0.001
                    ? (delta >= 0 ? Color.green : Color.red)
                    : Color.primary)
        }
    }
}
