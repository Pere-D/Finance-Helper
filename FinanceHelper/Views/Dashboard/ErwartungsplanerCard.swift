import SwiftUI
import Charts

struct ErwartungsplanerCard: View {
    let viewModel: DashboardViewModel
    let currency: String

    @Environment(PurchaseManager.self) private var purchases
    @State private var planMonths: Int = 36
    @State private var plannerData: [DashboardViewModel.PlannerPoint] = []
    @State private var showingPaywall = false

    private let segments: [(label: String, months: Int, premium: Bool)] = [
        ("1J", 12,  false),
        ("3J", 36,  false),
        ("5J", 60,  false),
        ("10J", 120, false),
        ("20J", 240, false),
    ]

    private var monthlyNet: Double {
        viewModel.totalMonthlyIncome
            - viewModel.totalMonthlyExpenses
            - viewModel.monthlySavingsForPlanner
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(
                title: NSLocalizedString("future_planner", comment: ""),
                icon: "wand.and.stars"
            )
            Divider()

            // Monthly budget metrics
            HStack(spacing: 0) {
                plannerMetric(label: NSLocalizedString("income", comment: ""),
                              amount: viewModel.totalMonthlyIncome, color: .green)
                Divider().frame(height: 34)
                plannerMetric(label: NSLocalizedString("expenses", comment: ""),
                              amount: viewModel.totalMonthlyExpenses, color: .red)
                Divider().frame(height: 34)
                plannerMetric(label: NSLocalizedString("budget_category_savings", comment: ""),
                              amount: viewModel.monthlySavingsForPlanner, color: .blue)
                Divider().frame(height: 34)
                plannerMetric(label: NSLocalizedString("surplus", comment: ""),
                              amount: monthlyNet,
                              color: monthlyNet >= 0 ? .green : .red)
            }
            .padding(.vertical, 12)

            Divider()

            // Time range picker
            HStack(spacing: 2) {
                ForEach(segments, id: \.months) { seg in
                    let isSelected = planMonths == seg.months
                    let locked = seg.premium && !purchases.isPremium
                    Button {
                        if locked {
                            showingPaywall = true
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) { planMonths = seg.months }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(seg.label)
                                .font(.caption2.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .primary : (locked ? .tertiary : .secondary))
                            if locked {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isSelected ? Color(.systemBackground) : Color.clear)
                                .shadow(color: isSelected ? .black.opacity(0.08) : .clear, radius: 2, x: 0, y: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.top, 10)

            // Projected end value
            if let last = plannerData.last {
                HStack(spacing: 6) {
                    Image(systemName: last.balance >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(last.balance >= 0 ? Color.green : Color.red)
                    Text("Prognose in \(planMonths / 12)J:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(last.balance.formatted(.currency(code: currency).notation(.compactName)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(last.balance >= 0 ? Color.green : Color.red)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Chart
            PlannerChartView(data: plannerData, currency: currency)
                .frame(height: 160)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 14)

            // Growth rate footnote
            Text(String(format: NSLocalizedString("planner_growth_footnote", comment: ""),
                        viewModel.averageInvestmentGrowthRate))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
        .cardStyle()
        .task(id: planMonths) {
            plannerData = viewModel.plannerProjection(months: planMonths)
        }
        .onAppear {
            plannerData = viewModel.plannerProjection(months: planMonths)
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallView().environment(purchases)
        }
    }

    private func plannerMetric(label: String, amount: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(amount.formatted(.currency(code: currency)
                .notation(.compactName)
                .precision(.fractionLength(0))))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Planner Chart with haptic scrubbing

struct PlannerChartView: View {
    let data: [DashboardViewModel.PlannerPoint]
    let currency: String

    @State private var selectedDate: Date? = nil

    private var selectedPoint: DashboardViewModel.PlannerPoint? {
        guard let d = selectedDate else { return nil }
        return data.min(by: { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) })
    }

    var body: some View {
        Chart {
            ForEach(data) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Balance", point.balance)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.25), Color.blue.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Balance", point.balance)
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
                .symbolSize(0)
            }

            ForEach(data.filter { $0.eventAmount != 0 }) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Balance", point.balance)
                )
                .foregroundStyle(point.eventAmount > 0 ? Color.green : Color.red)
                .symbolSize(40)
            }

            if let pt = selectedPoint {
                RuleMark(x: .value("Date", pt.date))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit, y: .disabled)) {
                        HStack(spacing: 5) {
                            Text(pt.date.formatted(.dateTime.month(.abbreviated).year()))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(pt.balance.formatted(.currency(code: currency).notation(.compactName)))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(pt.balance >= 0 ? Color.green : Color.red)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(d.formatted(.currency(code: currency)
                            .notation(.compactName)
                            .precision(.fractionLength(0))))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.year()).font(.caption2)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                guard !data.isEmpty, let anchor = proxy.plotFrame else { return }
                                let plotRect = geo[anchor]
                                let x = v.location.x - plotRect.origin.x
                                guard x >= 0, x <= plotRect.width else { return }
                                guard let date: Date = proxy.value(atX: x) else { return }
                                let nearest = data.min(by: {
                                    abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                })
                                if let nearest, nearest.date != selectedDate {
                                    selectedDate = nearest.date
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.3)) { selectedDate = nil }
                            }
                    )
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDate)
    }
}
