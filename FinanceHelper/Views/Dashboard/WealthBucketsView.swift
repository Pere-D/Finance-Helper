import SwiftUI
import Charts

// MARK: - Bucket enum

enum WealthBucket: String, Identifiable {
    case liquid, investment, pension, debt
    var id: String { rawValue }
}

// MARK: - Card

struct WealthBucketsCard: View {
    let viewModel: DashboardViewModel
    let currency: String
    var themeAccent: Color = .blue
    var onAddAccount: (() -> Void)? = nil
    var onAddBudgetEntry: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var tappedBucket: WealthBucket? = nil
    @State private var showBarChart = true

    private func bucketAccounts(_ bucket: WealthBucket) -> [Account] {
        viewModel.accounts.filter { acc in
            guard acc.isVisible else { return false }
            switch bucket {
            case .liquid:     return !acc.type.isLiability && (acc.type.isLiquid || acc.type == .festgeld)
            case .investment: return !acc.type.isLiability && (acc.type == .investment || acc.type == .krypto || acc.type == .depot || acc.type == .immobilie)
            case .pension:    return !acc.type.isLiability && acc.type == .altersvorsorge
            case .debt:       return acc.type.isLiability
            }
        }.sorted { abs($0.balance) > abs($1.balance) }
    }

    var body: some View {
        VStack(spacing: 14) {
            if viewModel.liquidTotal == 0 && viewModel.investmentTotal == 0
                && viewModel.pensionTotal == 0 && viewModel.totalLiabilities == 0 {
                VStack(spacing: 16) {
                    Image(systemName: "chart.pie")
                        .font(.largeTitle).foregroundStyle(.secondary.opacity(0.4))
                    VStack(spacing: 4) {
                        Text("Keine Vermögensaufteilung")
                            .font(.subheadline.weight(.semibold))
                        Text("Füge ein Konto oder einen Budgeteintrag hinzu, um deine Aufteilung zu sehen.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    VStack(spacing: 10) {
                        Button { onAddAccount?() } label: {
                            Label("Konto hinzufügen", systemImage: "plus.rectangle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(themeAccent).foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        Button { onAddBudgetEntry?() } label: {
                            Label("Budgeteintrag hinzufügen", systemImage: "doc.badge.plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.secondary.opacity(0.12)).foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showBarChart.toggle() }
                    } label: {
                        Image(systemName: showBarChart ? "chart.pie" : "chart.bar.xaxis")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if showBarChart {
                    AllocationBarView(
                        liquid: viewModel.liquidTotal,
                        investment: viewModel.investmentTotal,
                        pension: viewModel.pensionTotal,
                        debt: viewModel.totalLiabilities,
                        currency: currency,
                        onTap: { tappedBucket = $0 }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                } else {
                    AllocationDonutView(
                        liquid: viewModel.liquidTotal,
                        investment: viewModel.investmentTotal,
                        pension: viewModel.pensionTotal,
                        debt: viewModel.totalLiabilities,
                        currency: currency,
                        onTap: { tappedBucket = $0 }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(colorScheme == .dark ? Color.clear : Color(.systemBackground))
        .sheet(item: $tappedBucket) { bucket in
            BucketDetailSheet(
                bucket: bucket,
                accounts: bucketAccounts(bucket),
                currency: currency,
                viewModel: viewModel
            )
        }
    }
}

// MARK: - Provider Share Row

struct ProviderShareRow: View {
    let share: DashboardViewModel.ProviderBreakdown
    let currency: String

    var body: some View {
        HStack(spacing: 8) {
            Text(share.provider)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()
            Text(String(format: "%.0f%%", share.percentage))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .trailing)
                .contentTransition(.numericText())
            Text(share.total.formatted(.currency(code: currency)
                .notation(.compactName)
                .precision(.fractionLength(0))))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(minWidth: 52, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }
}

// MARK: - Donut Chart

private struct AllocationSlice: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
}

struct AllocationDonutView: View {
    let liquid: Double
    let investment: Double
    let pension: Double
    let debt: Double
    let currency: String
    var onTap: ((WealthBucket) -> Void)? = nil

    private var total: Double { liquid + investment + pension + debt }

    static let liquidColor     = Color(red: 0.22, green: 0.47, blue: 0.85)  // soft corporate blue
    static let investmentColor = Color(red: 0.07, green: 0.53, blue: 0.47)  // petrol / teal
    static let pensionColor    = Color(red: 0.44, green: 0.26, blue: 0.76)  // violet-indigo (distinct from blue)
    static let debtColor       = Color(red: 0.73, green: 0.22, blue: 0.22)  // muted, non-aggressive red

    private var slices: [AllocationSlice] {
        var result: [AllocationSlice] = []
        if liquid > 0     { result.append(AllocationSlice(name: NSLocalizedString("bucket_liquid", comment: ""),     value: liquid,     color: Self.liquidColor))     }
        if investment > 0 { result.append(AllocationSlice(name: NSLocalizedString("bucket_investment", comment: ""), value: investment, color: Self.investmentColor)) }
        if pension > 0    { result.append(AllocationSlice(name: NSLocalizedString("bucket_pension", comment: ""),   value: pension,    color: Self.pensionColor))    }
        if debt > 0       { result.append(AllocationSlice(name: NSLocalizedString("bucket_debt", comment: ""),       value: debt,       color: Self.debtColor))       }
        if result.isEmpty { result.append(AllocationSlice(name: "",                                                   value: 1,          color: Color.gray.opacity(0.2))) }
        return result
    }

    private struct LabelInfo: Identifiable {
        let id = UUID()
        let text: String
        let amount: Double
        let percentage: Double
        let color: Color
        let midAngleDeg: Double
        let isDebt: Bool
        let bucket: WealthBucket
    }

    private var sliceRanges: [(start: Double, end: Double, bucket: WealthBucket)] {
        guard total > 0 else { return [] }
        let items: [(Double, WealthBucket)] = [
            (liquid, .liquid), (investment, .investment),
            (pension, .pension), (debt, .debt),
        ].filter { $0.0 > 0 }
        var result: [(start: Double, end: Double, bucket: WealthBucket)] = []
        var cum = 0.0
        for (value, bucket) in items {
            let f = value / total
            result.append((start: cum * 360, end: (cum + f) * 360, bucket: bucket))
            cum += f
        }
        return result
    }

    private func bucket(atAngle angleDeg: Double) -> WealthBucket? {
        var a = angleDeg
        if a < 0 { a += 360 }
        if a >= 360 { a -= 360 }
        return sliceRanges.first { a >= $0.start && a < $0.end }?.bucket
    }

    private var labelInfos: [LabelInfo] {
        guard total > 0 else { return [] }
        let items: [(Double, String, Color, Bool, WealthBucket)] = [
            (liquid,     NSLocalizedString("bucket_liquid", comment: ""),     Self.liquidColor,     false, .liquid),
            (investment, NSLocalizedString("bucket_investment", comment: ""), Self.investmentColor, false, .investment),
            (pension,    NSLocalizedString("bucket_pension", comment: ""),    Self.pensionColor,    false, .pension),
            (debt,       NSLocalizedString("bucket_debt", comment: ""),       Self.debtColor,       true,  .debt),
        ].filter { $0.0 > 0 }
        var result: [LabelInfo] = []
        var cum = 0.0
        for (value, text, color, isDebt, bucket) in items {
            let f = value / total
            result.append(LabelInfo(text: text, amount: value, percentage: f * 100,
                                    color: color, midAngleDeg: (cum + f / 2) * 360 - 90,
                                    isDebt: isDebt, bucket: bucket))
            cum += f
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w / 2
            let cy = h / 2
            let chartR: CGFloat  = 85   // pie radius
            let lineStartR: CGFloat = chartR + 10
            let lineEndR: CGFloat   = chartR + 30
            let labelR: CGFloat     = chartR + 60  // labels well clear of pie

            ZStack {
                // Donut chart centered
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Value", slice.value),
                        innerRadius: .ratio(0.58),
                        angularInset: 1.5
                    )
                    .foregroundStyle(slice.color.opacity(0.75))
                    .cornerRadius(3)
                }
                .chartLegend(.hidden)
                .frame(width: chartR * 2, height: chartR * 2)
                .overlay(
                    Color.clear
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let center = CGPoint(x: chartR, y: chartR)
                                    let dx = value.location.x - center.x
                                    let dy = value.location.y - center.y
                                    let dist = sqrt(dx * dx + dy * dy)
                                    let innerR = chartR * 0.58
                                    guard dist >= innerR && dist <= chartR else { return }
                                    let angle = atan2(dy, dx) * 180 / .pi + 90
                                    if let hit = bucket(atAngle: angle) { onTap?(hit) }
                                }
                        )
                )
                .position(x: cx, y: cy)

                // Canvas: leader lines
                Canvas { ctx, _ in
                    for info in labelInfos {
                        let rad = info.midAngleDeg * .pi / 180
                        let x0 = cx + lineStartR * cos(rad)
                        let y0 = cy + lineStartR * sin(rad)
                        let x1 = cx + lineEndR * cos(rad)
                        let y1 = cy + lineEndR * sin(rad)
                        var linePath = Path()
                        linePath.move(to: CGPoint(x: x0, y: y0))
                        linePath.addLine(to: CGPoint(x: x1, y: y1))
                        ctx.stroke(linePath, with: .color(info.color.opacity(0.4)),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }
                }
                .frame(width: w, height: h)

                // Slice labels with white background box
                ForEach(labelInfos) { info in
                    let rad = info.midAngleDeg * .pi / 180
                    let lx = cx + labelR * cos(rad)
                    let ly = cy + labelR * sin(rad)
                    let isRight = cos(rad) >= 0
                    let amountStr = (info.isDebt ? -info.amount : info.amount)
                        .formatted(.currency(code: currency)
                            .notation(.compactName)
                            .precision(.fractionLength(0...1)))
                    VStack(alignment: isRight ? .leading : .trailing, spacing: 1) {
                        Text(info.text)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(info.color)
                        Text(amountStr)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(info.color)
                            .contentTransition(.numericText())
                        Text(String(format: "%.0f%%", info.percentage))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(info.color.opacity(0.7))
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(info.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .fixedSize()
                    .position(x: lx, y: ly)
                    .onTapGesture { onTap?(info.bucket) }
                }
            }
        }
    }
}

// MARK: - Bar Chart

struct AllocationBarView: View {
    let liquid: Double
    let investment: Double
    let pension: Double
    let debt: Double
    let currency: String
    var onTap: ((WealthBucket) -> Void)? = nil

    private var total: Double { liquid + investment + pension + debt }
    private var maxValue: Double { items.map(\.value).max() ?? 1 }

    private struct BarItem {
        let label: String
        let value: Double
        let color: Color
        let isDebt: Bool
        let bucket: WealthBucket
        let icon: String
    }

    private var items: [BarItem] {
        var result: [BarItem] = []
        if liquid > 0 {
            result.append(BarItem(label: NSLocalizedString("bucket_liquid", comment: ""),
                                  value: liquid, color: AllocationDonutView.liquidColor,
                                  isDebt: false, bucket: .liquid, icon: "banknote"))
        }
        if investment > 0 {
            result.append(BarItem(label: NSLocalizedString("bucket_investment", comment: ""),
                                  value: investment, color: AllocationDonutView.investmentColor,
                                  isDebt: false, bucket: .investment, icon: "chart.line.uptrend.xyaxis"))
        }
        if pension > 0 {
            result.append(BarItem(label: NSLocalizedString("bucket_pension", comment: ""),
                                  value: pension, color: AllocationDonutView.pensionColor,
                                  isDebt: false, bucket: .pension, icon: "umbrella.fill"))
        }
        if debt > 0 {
            result.append(BarItem(label: NSLocalizedString("bucket_debt", comment: ""),
                                  value: debt, color: AllocationDonutView.debtColor,
                                  isDebt: true, bucket: .debt, icon: "creditcard.fill"))
        }
        return result
    }

    private var assetItems: [BarItem] { items.filter { !$0.isDebt } }
    private var debtItems: [BarItem]  { items.filter {  $0.isDebt } }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(assetItems.indices, id: \.self) { i in
                barRow(assetItems[i])
            }
            if !debtItems.isEmpty && !assetItems.isEmpty {
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 0.5)
                    .padding(.vertical, 2)
            }
            ForEach(debtItems.indices, id: \.self) { i in
                barRow(debtItems[i])
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func barRow(_ item: BarItem) -> some View {
        let fraction = total > 0 ? item.value / total : 0
        let barFraction = maxValue > 0 ? item.value / maxValue : 0
        let displayAmount = (item.isDebt ? -item.value : item.value)
            .formatted(.currency(code: currency).notation(.compactName).precision(.fractionLength(0...1)))
        Button { onTap?(item.bucket) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(item.color.opacity(0.12)).frame(width: 26, height: 26)
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(item.color)
                    }
                    Text(item.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(displayAmount)
                            .font(.system(.subheadline, design: .rounded).weight(.black))
                            .foregroundStyle(item.color)
                            .contentTransition(.numericText())
                        Text(String(format: "%.0f%%", fraction * 100))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(item.color.opacity(0.08))
                            .frame(height: 22)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [item.color, item.color.opacity(0.65)],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: max(22, geo.size.width * CGFloat(barFraction)), height: 22)
                            .shadow(color: item.color.opacity(0.25), radius: 4, x: 0, y: 2)
                    }
                }
                .frame(height: 22)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bucket Detail Sheet

private struct BucketDetailSheet: View {
    let bucket: WealthBucket
    let accounts: [Account]
    let currency: String
    let viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch bucket {
        case .liquid:     return NSLocalizedString("bucket_liquid", comment: "")
        case .investment: return NSLocalizedString("bucket_investment", comment: "")
        case .pension:    return NSLocalizedString("bucket_pension", comment: "")
        case .debt:       return NSLocalizedString("bucket_debt", comment: "")
        }
    }

    private var color: Color {
        switch bucket {
        case .liquid:     return AllocationDonutView.liquidColor
        case .investment: return AllocationDonutView.investmentColor
        case .pension:    return AllocationDonutView.pensionColor
        case .debt:       return AllocationDonutView.debtColor
        }
    }

    private var total: Double {
        accounts.reduce(0) { $0 + viewModel.convert(max(0, $1.balance), from: $1.currency, to: currency) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 4) {
                        let displayTotal = bucket == .debt ? -total : total
                        Text(displayTotal.formatted(.currency(code: currency)))
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(color)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                        Text(String(format: NSLocalizedString("accounts_count_fmt", comment: ""), accounts.count))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    ForEach(accounts) { acc in
                        let converted = viewModel.convert(max(0, acc.balance), from: acc.currency, to: currency)
                        let share = total > 0 ? converted / total : 0
                        HStack(spacing: 12) {
                            Circle()
                                .fill(acc.effectiveColor.opacity(0.14))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: acc.effectiveSystemImage)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(acc.effectiveColor)
                                )
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(acc.name).font(.body)
                                        if !acc.provider.trimmingCharacters(in: .whitespaces).isEmpty {
                                            Text(acc.provider).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        let displayAmt = bucket == .debt ? -converted : converted
                                        Text(displayAmt.formatted(.currency(code: currency)))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(bucket == .debt ? .red : color)
                                            .contentTransition(.numericText())
                                        Text(String(format: "%.0f%%", share * 100))
                                            .font(.caption2).foregroundStyle(.secondary)
                                            .contentTransition(.numericText())
                                    }
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.10)).frame(height: 5)
                                        RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.65))
                                            .frame(width: max(4, geo.size.width * CGFloat(share)), height: 5)
                                    }
                                }
                                .frame(height: 5)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if accounts.isEmpty {
                    Section {
                        Text(NSLocalizedString("no_accounts", comment: ""))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("done", comment: "")) { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Bucket Tile

struct BucketTile: View {
    let icon: String
    let label: String
    let amount: Double
    let color: Color
    let currency: String
    var isDebt: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: icon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                let cents = (amount * 100).rounded()
                let rounded = cents / 100
                let displayAmount = isDebt ? (cents > 0 ? -rounded : 0.0) : rounded
                Text(displayAmount.formatted(.currency(code: currency)
                    .notation(.compactName)
                    .precision(.fractionLength(0...1))))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isDebt ? .red : color)
                    .contentTransition(.numericText())
            }
        }
    }
}
