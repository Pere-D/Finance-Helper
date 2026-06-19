import SwiftUI

struct SectionHeader: View {
    let title: String
    let icon: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(.secondary)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

struct CashFlowRow: View {
    let label: String
    let value: Double
    let currency: String
    let color: Color
    var bold: Bool = false
    var body: some View {
        HStack {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: value >= 0 ? "plus" : "minus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                )
            Text(label)
                .font(bold ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            Text(abs(value).formatted(.currency(code: currency)))
                .font(bold ? .subheadline.weight(.bold) : .subheadline.weight(.medium))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}

struct AccountDashboardRow: View {
    @Bindable var account: Account
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(account.type.typeColor.opacity(account.isVisible ? 0.12 : 0.06))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: account.type.systemImage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(account.isVisible ? account.type.typeColor : account.type.typeColor.opacity(0.4))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(account.name).font(.subheadline.weight(.medium))
                    .foregroundStyle(account.isVisible ? .primary : .secondary)
                if account.monthlyCashFlow != 0 {
                    Text(account.monthlyCashFlow.formatted(.currency(code: account.currency))
                         + " / " + NSLocalizedString("month_abbrev", comment: ""))
                        .font(.caption2)
                        .foregroundStyle(account.monthlyCashFlow >= 0 ? .green : .red)
                        .contentTransition(.numericText())
                }
                if account.type.isLiability, let months = account.estimatedPayoffMonths {
                    Text(String(format: NSLocalizedString("payoff_in_months", comment: ""), months))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(account.balance.formatted(.currency(code: account.currency)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(account.isVisible
                                 ? (account.type.isLiability ? .red : .primary)
                                 : .secondary)
                .contentTransition(.numericText())
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { account.isVisible.toggle() }
            } label: {
                Image(systemName: account.isVisible ? "eye" : "eye.slash")
                    .font(.body.weight(.medium))
                    .foregroundStyle(account.isVisible ? Color.secondary : Color.secondary.opacity(0.5))
                    .frame(width: 36, height: 36)
                    .background(account.isVisible ? Color.clear : Color.secondary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}
