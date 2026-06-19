import SwiftUI
import Charts

struct CombinedFlowCard: View {
    let viewModel: DashboardViewModel
    let currency: String
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionHeader(
                    title: NSLocalizedString("monthly_cash_flow", comment: ""),
                    icon: "arrow.left.arrow.right"
                )
                let net = viewModel.monthlyNetCashFlow
                Text((net >= 0 ? "+" : "") + net.formatted(.currency(code: currency)))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(net >= 0 ? .green : .red)
                    .padding(.trailing, 16)
            }
            Divider()

            if viewModel.totalMonthlyIncome == 0 && viewModel.totalMonthlyExpenses == 0 && viewModel.totalMonthlySavings == 0 {
                Text(NSLocalizedString("no_entries", comment: ""))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding().frame(maxWidth: .infinity)
            } else {
                barContent
            }
        }
        .cardStyle()
    }

    // MARK: - Bar view

    private var barContent: some View {
        let maxTotal = max(
            viewModel.totalMonthlyIncome,
            viewModel.totalMonthlyExpenses + viewModel.totalMonthlySavings
        )
        return VStack(spacing: 16) {
            if viewModel.totalMonthlyIncome > 0 {
                CashFlowBarRow(
                    label: NSLocalizedString("monthly_income", comment: ""),
                    total: viewModel.totalMonthlyIncome,
                    maxTotal: maxTotal,
                    slices: viewModel.incomePieSlices(),
                    solidColor: .green,
                    currency: currency
                )
            }
            if viewModel.totalMonthlySavings > 0 {
                CashFlowBarRow(
                    label: NSLocalizedString("budget_category_savings", comment: ""),
                    total: viewModel.totalMonthlySavings,
                    maxTotal: maxTotal,
                    slices: viewModel.savingsPieSlices(),
                    solidColor: .teal,
                    currency: currency
                )
            }
            if viewModel.totalMonthlyExpenses > 0 {
                CashFlowBarRow(
                    label: NSLocalizedString("monthly_expenses", comment: ""),
                    total: viewModel.totalMonthlyExpenses,
                    maxTotal: maxTotal,
                    slices: viewModel.expensePieSlices(),
                    solidColor: nil,
                    currency: currency
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Bar Row

struct CashFlowBarRow: View {
    let label: String
    let total: Double
    let maxTotal: Double
    let slices: [DashboardViewModel.PieSlice]
    let solidColor: Color?
    let currency: String

    private var labelColor: Color { solidColor ?? .red }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(total.formatted(.currency(code: currency)))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(labelColor)
            }

            // Bar — GeometryReader is in overlay to avoid VStack sizing issues
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 12, maxHeight: 12)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        let activeWidth = maxTotal > 0 ? geo.size.width * CGFloat(total / maxTotal) : 0
                        if let solid = solidColor {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(solid.opacity(0.75))
                                .frame(width: activeWidth, height: 12)
                        } else {
                            HStack(spacing: 1.5) {
                                ForEach(slices) { slice in
                                    let fraction = total > 0 ? CGFloat(slice.amount / total) : 0
                                    let segWidth = max(0, activeWidth * fraction - 1.5)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(slice.displayColor)
                                        .frame(width: segWidth, height: 12)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

            if solidColor == nil && !slices.isEmpty {
                HStack(spacing: 0) {
                    ForEach(slices.prefix(4)) { slice in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(slice.displayColor)
                                .frame(width: 6, height: 6)
                            Text(slice.accountName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.trailing, 10)
                    }
                    if slices.count > 4 {
                        Text("+\(slices.count - 4)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
