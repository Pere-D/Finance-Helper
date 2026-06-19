import SwiftUI

struct BudgetEntryRow: View {
    let entry: BudgetEntry
    let defaultCurrency: String
    var showAccountName: Bool = true
    var yearlyMode: Bool = false
    var overrideAmount: Double? = nil
    var selectedMonth: Date? = nil

    private var currency: String { entry.account?.currency ?? defaultCurrency }

    private var displayAmount: Double {
        if let over = overrideAmount { return over }
        if yearlyMode {
            return entry.recurrence == .once ? entry.amount : entry.effectiveMonthlyAmount * 12.0
        }
        return entry.amount
    }

    private var periodLabel: String {
        if let month = selectedMonth {
            if entry.recurrence == .once {
                return entry.dueDate.formatted(.dateTime.day().month().year())
            }
            if let next = entry.nextDueDate(after: month) {
                return next.formatted(.dateTime.day().month())
            }
        }
        if yearlyMode && entry.recurrence != .once { return NSLocalizedString("period_yearly", comment: "") }
        return entry.recurrence.localizedName
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(entry.displayColor.opacity(0.14))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: entry.displaySymbolName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(entry.displayColor)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName)
                    .font(.body)
                    .foregroundStyle(entry.isActive ? .primary : .secondary)

                HStack(spacing: 6) {
                    if showAccountName, let accName = entry.account?.name {
                        Text(accName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let dest = entry.transferToAccount {
                        Text("→ \(dest.name)")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    if entry.isDueThisMonth {
                        Text(NSLocalizedString("due_this_month", comment: ""))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(entry.isIncomeEntry ? Color.green : Color.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((entry.isIncomeEntry ? Color.green : Color.orange).opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if !entry.isActive {
                        Text(NSLocalizedString("inactive", comment: ""))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    if entry.linkedGoalID != nil {
                        HStack(spacing: 3) {
                            Image(systemName: "target")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Sparziel")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.teal)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.teal.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(displayAmount.formatted(.currency(code: currency)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(entry.isIncomeEntry ? Color.green : .primary)
                    .contentTransition(.numericText())
                Text(periodLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(entry.isActive ? 1.0 : 0.5)
    }
}
