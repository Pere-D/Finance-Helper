import SwiftUI
import Charts

struct GoalMarker: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let date: Date
    var icon: String = "mappin"
}

private struct MarkerOverlayItem: Identifiable {
    let id = UUID()
    let x: CGFloat
    let row: Int
    let markers: [GoalMarker]
    let isEntry: Bool
}

struct BalanceChartView: View {
    let totalData: [DashboardViewModel.ChartPoint]
    let stackedData: [DashboardViewModel.AccountChartPoint]
    let snapshots: [DashboardViewModel.BalanceSnapshot]
    let currency: String
    let months: Int
    var goalMarkers: [GoalMarker] = []
    var goalEntryMarkers: [GoalMarker] = []
    var historicalLine: [DashboardViewModel.ChartPoint] = []
    var historicalLineColor: Color = .accentColor
    var isInteractive: Bool = true

    @State private var selectedDate: Date? = Date()

    private let calendar = Calendar.current

    var body: some View {
        if totalData.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                Chart {
                    stackedAreaContent
                    stackedBucketLines
                    netWorthLineContent
                    zeroLine
                    todayMarker
                    goalMarkerLines
                    goalEntryMarkerLines
                    if let date = selectedDate {
                        selectionHighlight(date)
                        selectionDot(date)
                    }
                }
                .frame(height: 165)
                .chartYScale(domain: yDomain)
                .chartXScale(domain: xDomain)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let plotRect = proxy.plotFrame.map { geo[$0] } ?? .zero
                        let markerItems = computeMarkerPositions(proxy: proxy)
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .contentShape(Rectangle())
                                .simultaneousGesture(
                                    SpatialTapGesture()
                                        .onEnded { value in
                                            guard isInteractive else { return }
                                            let origin = proxy.plotFrame.map { geo[$0].origin } ?? .zero
                                            let xPos = value.location.x - origin.x
                                            guard xPos >= 0 else { return }
                                            if let date: Date = proxy.value(atX: xPos) {
                                                let allDates = totalData.map(\.date) + historicalLine.map(\.date)
                                                if let nearest = allDates.min(by: { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }) {
                                                    selectedDate = nearest
                                                }
                                            }
                                        }
                                )
                                .gesture(
                                    DragGesture(minimumDistance: 8)
                                        .onChanged { value in
                                            guard isInteractive else { return }
                                            let origin = proxy.plotFrame.map { geo[$0].origin } ?? .zero
                                            let xPos = value.location.x - origin.x
                                            guard xPos >= 0 else { return }
                                            if let date: Date = proxy.value(atX: xPos) {
                                                let allDates = totalData.map(\.date) + historicalLine.map(\.date)
                                                let nearest = allDates.min {
                                                    abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date))
                                                }
                                                if let nearest { selectedDate = nearest }
                                            }
                                        }
                                )

                            ForEach(markerItems) { item in
                                HStack(spacing: 2) {
                                    ForEach(item.markers) { m in
                                        Image(systemName: m.icon)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(m.color)
                                            .padding(5)
                                            .background(m.color.opacity(item.isEntry ? 0.12 : 0.15))
                                            .clipShape(Circle())
                                    }
                                }
                                .offset(
                                    x: plotRect.minX + item.x - 11.5,
                                    y: plotRect.minY + CGFloat(item.row) * 27 + 2
                                )
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom, values: .stride(by: axisStrideUnit, count: axisStrideCount)) { _ in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.1))
                        AxisValueLabel(format: xAxisLabelFormat)
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.08))
                        if let v = value.as(Double.self) {
                            AxisValueLabel {
                                Text(v, format: .number.notation(.compactName))
                                    .font(.caption2)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .id(months)
                .animation(nil, value: months)
                .animation(nil, value: selectedDate)
                .transaction { $0.animation = nil }
                .onChange(of: months) { selectedDate = Date() }

                selectionPanel(for: selectedDate ?? Date())
            }
        }
    }

    // MARK: - Chart content

    @ChartContentBuilder private var stackedAreaContent: some ChartContent {
        // Single gradient fill derived from the same netWorthLineData as the line mark,
        // guaranteeing perfect alignment regardless of magnitude of changes.
        ForEach(netWorthLineData) { pt in
            AreaMark(
                x: .value("Month", pt.date, unit: xUnit),
                yStart: .value("Zero", 0.0),
                yEnd: .value("Balance", pt.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.primary.opacity(0.10), Color.primary.opacity(0.01)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.linear)
        }
        // Debt overlay: red band between net worth and total assets
        ForEach(snapshots.filter { $0.assetTotal > $0.netWorth }) { snap in
            AreaMark(
                x: .value("Month", snap.date, unit: xUnit),
                yStart: .value("NetWorth", snap.netWorth),
                yEnd: .value("AssetTotal", snap.assetTotal)
            )
            .foregroundStyle(Color.red.opacity(0.28))
            .interpolationMethod(.linear)
        }
    }

    private struct NetWorthPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    /// Merges historical balance points with forecast net worth snapshots into one
    /// continuous array, eliminating any date gap at the today boundary.
    private var netWorthLineData: [NetWorthPoint] {
        let visStart = historicalDisplayStart
        var points: [NetWorthPoint] = []
        for pt in historicalLine where pt.date >= visStart {
            points.append(NetWorthPoint(date: pt.date, value: pt.balance))
        }
        for snap in snapshots {
            let alreadyCovered = historicalLine.contains {
                calendar.isDate($0.date, equalTo: snap.date, toGranularity: xGranularity)
            }
            if !alreadyCovered {
                points.append(NetWorthPoint(date: snap.date, value: snap.netWorth))
            }
        }
        return points.sorted { $0.date < $1.date }
    }

    // Historical net worth points (from historicalLine data only)
    private var historicalNetWorthPoints: [NetWorthPoint] {
        netWorthLineData.filter { pt in
            historicalLine.contains {
                calendar.isDate($0.date, equalTo: pt.date, toGranularity: xGranularity)
            }
        }
    }

    // Future net worth points with a gentle sine-wave overlay to signal uncertainty
    private var wavyNetWorthFuture: [NetWorthPoint] {
        let future = snapshots
            .filter { snap in
                !historicalLine.contains {
                    calendar.isDate($0.date, equalTo: snap.date, toGranularity: xGranularity)
                }
            }
            .sorted { $0.date < $1.date }
        guard !future.isEmpty else { return [] }
        let n = future.count
        let amplitude = (future.map { abs($0.netWorth) }.max() ?? 1_000) * 0.013
        var result: [NetWorthPoint] = []
        // Anchor at last historical point so the two series connect seamlessly
        if let anchor = historicalLine.sorted(by: { $0.date < $1.date }).last {
            result.append(NetWorthPoint(date: anchor.date, value: anchor.balance))
        }
        for (i, snap) in future.enumerated() {
            let t = Double(i + 1) / Double(n)
            let wave = amplitude * sin(t * 5 * .pi)  // ~2.5 full oscillations
            result.append(NetWorthPoint(date: snap.date, value: snap.netWorth + wave))
        }
        return result
    }

    @ChartContentBuilder private var netWorthLineContent: some ChartContent {
        // Past: straight solid line
        ForEach(historicalNetWorthPoints) { pt in
            LineMark(
                x: .value("Month", pt.date, unit: xUnit),
                y: .value("Balance", pt.value),
                series: .value("Account", "__mainline__")
            )
            .foregroundStyle(Color.primary)
            .lineStyle(StrokeStyle(lineWidth: 2.5))
            .interpolationMethod(.linear)
            .symbolSize(0)
        }
        // Forecast: wavy catmullRom line
        ForEach(wavyNetWorthFuture) { pt in
            LineMark(
                x: .value("Month", pt.date, unit: xUnit),
                y: .value("Balance", pt.value),
                series: .value("Account", "__mainline_fc__")
            )
            .foregroundStyle(Color.primary.opacity(0.9))
            .lineStyle(StrokeStyle(lineWidth: 2.5))
            .interpolationMethod(.catmullRom)
            .symbolSize(0)
        }
    }

    // MARK: - Stacked bucket lines (forecast only)

    private func bucketOrder(_ pt: DashboardViewModel.AccountChartPoint) -> Int {
        if pt.accountType == .altersvorsorge { return 0 }
        if pt.accountType == .investment || pt.accountType == .krypto || pt.accountType == .depot { return 1 }
        return 2
    }

    private struct StackedLinePoint: Identifiable {
        let id = UUID()
        let date: Date
        let cumulativeBalance: Double
        let color: Color
        let seriesName: String
    }

    private var stackedLineData: [StackedLinePoint] {
        guard !stackedData.isEmpty else { return [] }
        let allDates = Array(Set(stackedData.map(\.date))).sorted()
        var result: [StackedLinePoint] = []
        for date in allDates {
            let pts = stackedData
                .filter { calendar.isDate($0.date, equalTo: date, toGranularity: xGranularity) }
                .sorted { bucketOrder($0) < bucketOrder($1) }
            var cum = 0.0
            for pt in pts {
                cum += pt.balance
                result.append(StackedLinePoint(
                    date: pt.date,
                    cumulativeBalance: cum,
                    color: pt.displayColor,
                    seriesName: pt.accountName
                ))
            }
        }
        return result
    }

    // Shared-phase sine wave per date index: all buckets shift identically so they never cross
    private var wavyStackedLineData: [StackedLinePoint] {
        guard !stackedLineData.isEmpty else { return [] }
        let sortedDates = Array(Set(stackedLineData.map(\.date))).sorted()
        let n = sortedDates.count
        let amplitude = (stackedLineData.map { abs($0.cumulativeBalance) }.max() ?? 1_000) * 0.013
        return stackedLineData.map { pt in
            guard let idx = sortedDates.firstIndex(where: {
                calendar.isDate($0, equalTo: pt.date, toGranularity: .month)
            }) else { return pt }
            let t = Double(idx) / max(1.0, Double(n - 1))
            let wave = amplitude * sin(t * 5 * .pi)
            return StackedLinePoint(date: pt.date, cumulativeBalance: pt.cumulativeBalance + wave,
                                    color: pt.color, seriesName: pt.seriesName)
        }
    }

    @ChartContentBuilder private var stackedBucketLines: some ChartContent {
        ForEach(wavyStackedLineData) { pt in
            LineMark(
                x: .value("Month", pt.date, unit: xUnit),
                y: .value("Balance", pt.cumulativeBalance),
                series: .value("Bucket", pt.seriesName)
            )
            .foregroundStyle(pt.color.opacity(0.75))
            .lineStyle(StrokeStyle(lineWidth: 1.2))
            .interpolationMethod(.catmullRom)
            .symbolSize(0)
        }
    }

    @ChartContentBuilder private var zeroLine: some ChartContent {
        RuleMark(y: .value("zero", 0))
            .foregroundStyle(Color.secondary.opacity(0.25))
            .lineStyle(StrokeStyle(lineWidth: 0.5))
    }

    @ChartContentBuilder private var todayMarker: some ChartContent {
        RuleMark(x: .value("today", Date(), unit: xUnit))
            .foregroundStyle(Color.secondary.opacity(0.4))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .annotation(position: .top, alignment: .trailing, spacing: 2) {
                Text("Heute")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
    }

    @ChartContentBuilder private var goalMarkerLines: some ChartContent {
        ForEach(groupedGoalMarkers, id: \.id) { group in
            RuleMark(x: .value("Goal", group.date, unit: xUnit))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
    }

    @ChartContentBuilder private func selectionHighlight(_ date: Date) -> some ChartContent {
        RuleMark(x: .value("sel", date, unit: xUnit))
            .foregroundStyle(Color.primary.opacity(0.08))
            .lineStyle(StrokeStyle(lineWidth: 10))
    }

    @ChartContentBuilder private func selectionDot(_ date: Date) -> some ChartContent {
        if let hist = historicalLine.first(where: { calendar.isDate($0.date, equalTo: date, toGranularity: xGranularity) }) {
            PointMark(x: .value("sel", hist.date, unit: xUnit), y: .value("sel", hist.balance))
                .foregroundStyle(Color(.systemBackground))
                .symbolSize(130)
            PointMark(x: .value("sel", hist.date, unit: xUnit), y: .value("sel", hist.balance))
                .foregroundStyle(Color.primary)
                .symbolSize(55)
        } else if let snap = snapshots.first(where: { calendar.isDate($0.date, equalTo: date, toGranularity: xGranularity) }) {
            PointMark(x: .value("sel", snap.date, unit: xUnit), y: .value("sel", snap.netWorth))
                .foregroundStyle(Color(.systemBackground))
                .symbolSize(130)
            PointMark(x: .value("sel", snap.date, unit: xUnit), y: .value("sel", snap.netWorth))
                .foregroundStyle(Color.primary)
                .symbolSize(55)
        } else if let pt = totalData.first(where: { calendar.isDate($0.date, equalTo: date, toGranularity: xGranularity) }) {
            PointMark(x: .value("sel", pt.date, unit: xUnit), y: .value("sel", pt.balance))
                .foregroundStyle(Color(.systemBackground))
                .symbolSize(130)
            PointMark(x: .value("sel", pt.date, unit: xUnit), y: .value("sel", pt.balance))
                .foregroundStyle(Color.primary)
                .symbolSize(55)
        }
    }

    // MARK: - Grouped goal markers (same month → side-by-side icons)

    private var groupedGoalMarkers: [(id: UUID, date: Date, markers: [GoalMarker])] {
        var groups: [(id: UUID, date: Date, markers: [GoalMarker])] = []
        for marker in goalMarkers {
            if let idx = groups.firstIndex(where: { calendar.isDate($0.date, equalTo: marker.date, toGranularity: xGranularity) }) {
                groups[idx].markers.append(marker)
            } else {
                groups.append((id: marker.id, date: marker.date, markers: [marker]))
            }
        }
        return groups
    }

    private var groupedGoalEntryMarkers: [(id: UUID, date: Date, markers: [GoalMarker])] {
        var groups: [(id: UUID, date: Date, markers: [GoalMarker])] = []
        for marker in goalEntryMarkers {
            if let idx = groups.firstIndex(where: { calendar.isDate($0.date, equalTo: marker.date, toGranularity: xGranularity) }) {
                groups[idx].markers.append(marker)
            } else {
                groups.append((id: marker.id, date: marker.date, markers: [marker]))
            }
        }
        return groups
    }

    @ChartContentBuilder private var goalEntryMarkerLines: some ChartContent {
        ForEach(groupedGoalEntryMarkers, id: \.id) { group in
            RuleMark(x: .value("GoalEntry", group.date, unit: xUnit))
                .foregroundStyle(Color.orange.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    // MARK: - Marker overlay positioning

    private func computeMarkerPositions(proxy: ChartProxy) -> [MarkerOverlayItem] {
        let slotWidth: CGFloat = 27  // icon circle diameter + small gap

        var raw: [(x: CGFloat, markers: [GoalMarker], isEntry: Bool)] = []
        for group in groupedGoalMarkers {
            if let x = proxy.position(forX: group.date) {
                raw.append((x, group.markers, false))
            }
        }
        for group in groupedGoalEntryMarkers {
            if let x = proxy.position(forX: group.date) {
                raw.append((x, group.markers, true))
            }
        }
        raw.sort { $0.x < $1.x }

        // Greedy row assignment: if a new item overlaps the last item in a row, move to the next row
        var rowNextX: [Int: CGFloat] = [:]
        return raw.map { item in
            var row = 0
            while let nextX = rowNextX[row], item.x < nextX {
                row += 1
            }
            rowNextX[row] = item.x + slotWidth
            return MarkerOverlayItem(x: item.x, row: row, markers: item.markers, isEntry: item.isEntry)
        }
    }

    // MARK: - Domain & axis helpers

    /// Start date of the visible historical window.
    /// Historical occupies ~1/5 of the x-axis: show (chartMonths / 4) past months, min 2.
    /// Without historical data the domain starts at today.
    private var historicalDisplayStart: Date {
        guard !historicalLine.isEmpty else {
            return totalData.first?.date ?? Date()
        }
        let todayStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let histMonths = max(2, months / 4)
        let start = calendar.date(byAdding: .month, value: -histMonths, to: todayStart) ?? todayStart
        // Never go earlier than the oldest available historical point
        let oldest = historicalLine.first?.date ?? start
        return start > oldest ? start : oldest
    }

    private var xDomain: ClosedRange<Date> {
        guard let last = totalData.last?.date else { return Date()...Date() }
        let dataStart = historicalDisplayStart
        let end: Date
        if xGranularity == .day {
            // Extra week so the last day label isn't clipped at the right edge
            end = calendar.date(byAdding: .day, value: 8, to: last) ?? last
        } else {
            let startOfLast = calendar.date(from: calendar.dateComponents([.year, .month], from: last)) ?? last
            // Add right padding equal to half the axis stride so the last label has breathing room
            let rightPad = min(3, max(1, axisStrideCount / 2))
            end = calendar.date(byAdding: .month, value: 1 + rightPad, to: startOfLast) ?? last
        }
        return dataStart...end
    }

    private var yDomain: ClosedRange<Double> {
        let visStart = historicalDisplayStart
        let visibleSnapshots = snapshots.filter { $0.date >= visStart }
        let visibleStack     = stackedData.filter { $0.date >= visStart }
        let visibleHist      = historicalLine.filter { $0.date >= visStart }
        let allValues = visibleStack.map(\.balance)
            + visibleSnapshots.map(\.netWorth)
            + visibleSnapshots.map(\.assetTotal)
            + visibleHist.map(\.balance)
            + [0.0]
        let maxV = allValues.max() ?? 0
        let minV = allValues.min() ?? 0
        let span = max(Swift.abs(maxV - minV), 1000)
        return (minV - span * 0.05)...(maxV + span * 0.32)
    }

    /// Auto-detect whether data is daily or monthly based on consecutive-point interval.
    private var xGranularity: Calendar.Component {
        guard totalData.count >= 2 else { return .month }
        let interval = totalData[1].date.timeIntervalSince(totalData[0].date)
        return interval < 86400 * 3 ? .day : .month
    }

    private var xUnit: Calendar.Component { xGranularity }

    private var axisStrideUnit: Calendar.Component {
        xGranularity == .day ? .day : .month
    }

    private var axisStrideCount: Int {
        if xGranularity == .day {
            return months <= 1 ? 7 : 14   // weekly or bi-weekly labels for daily views
        }
        switch months {
        case ..<7:     return 2
        case 7...18:   return 3
        case 19...36:  return 6
        case 37...60:  return 12
        default:       return 24
        }
    }

    private var xAxisLabelFormat: Date.FormatStyle {
        if xGranularity == .day {
            return .dateTime.day().month(.abbreviated)
        }
        return axisStrideCount >= 12
            ? .dateTime.year(.twoDigits)
            : .dateTime.month(.defaultDigits).year(.twoDigits)
    }

    private var strideCount: Int { axisStrideCount }

    // MARK: - Date navigation helpers

    private func prevDate(from date: Date) -> Date? {
        (totalData.map(\.date) + historicalLine.map(\.date))
            .sorted()
            .last { !calendar.isDate($0, equalTo: date, toGranularity: xGranularity) && $0 < date }
    }

    private func nextDate(from date: Date) -> Date? {
        (totalData.map(\.date) + historicalLine.map(\.date))
            .sorted()
            .first { !calendar.isDate($0, equalTo: date, toGranularity: xGranularity) && $0 > date }
    }

    // MARK: - Selection panel

    private func selectionPanel(for date: Date) -> some View {
        let pts = stackedData
            .filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
            .sorted { $0.balance > $1.balance }
        let totalPoint = totalData.first { calendar.isDate($0.date, equalTo: date, toGranularity: xGranularity) }
        let histPoint  = historicalLine.first { calendar.isDate($0.date, equalTo: date, toGranularity: xGranularity) }
        let forecastBalance = totalPoint?.balance ?? pts.reduce(0) { $0 + $1.balance }
        let assetTotal = pts.reduce(0) { $0 + $1.balance }
        let prev = prevDate(from: date)
        let next = nextDate(from: date)
        let isToday = calendar.isDate(date, equalTo: Date(), toGranularity: xGranularity)
        let hasForecast = totalPoint != nil || !pts.isEmpty

        return VStack(spacing: 0) {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        if let p = prev { selectedDate = p }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.bold))
                            .frame(width: 26, height: 26)
                            .background(Color.secondary.opacity(prev == nil ? 0.05 : 0.1))
                            .clipShape(Circle())
                    }
                    .disabled(prev == nil)
                    .foregroundStyle(prev == nil ? Color.secondary.opacity(0.4) : Color.primary)
                    .buttonStyle(.plain)

                    HStack(spacing: 5) {
                        Text(monthLabel(date))
                            .font(.subheadline.weight(.semibold))
                        if isToday {
                            Text(NSLocalizedString("today", comment: ""))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.75))
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    Button {
                        if let n = next { selectedDate = n }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .frame(width: 26, height: 26)
                            .background(Color.secondary.opacity(next == nil ? 0.05 : 0.1))
                            .clipShape(Circle())
                    }
                    .disabled(next == nil)
                    .foregroundStyle(next == nil ? Color.secondary.opacity(0.4) : Color.primary)
                    .buttonStyle(.plain)
                }

                // Net worth row
                let displayBalance = histPoint?.balance ?? (hasForecast ? forecastBalance : nil)
                if let balance = displayBalance {
                    HStack(spacing: 6) {
                        Canvas { context, size in
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: size.height / 2))
                            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                            context.stroke(path, with: .color(Color.primary),
                                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        }
                        .frame(width: 22, height: 10)
                        Text(NSLocalizedString("net_worth", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(balance.formatted(.currency(code: currency)))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(balance >= 0 ? Color.primary : Color.red)
                    }
                }

                if !pts.isEmpty {
                    let snap = snapshots.first { calendar.isDate($0.date, equalTo: date, toGranularity: xGranularity) }
                    let debt = snap.map { max(0, $0.assetTotal - $0.netWorth) } ?? 0
                    Divider()
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 4
                    ) {
                        ForEach(pts.prefix(6)) { pt in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(pt.displayColor)
                                    .frame(width: 6, height: 6)
                                Text(pt.accountName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                HStack(spacing: 3) {
                                    Text(compactAmount(pt.balance))
                                        .font(.caption2.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(pt.displayColor)
                                    if assetTotal > 0 {
                                        Text(String(format: "%.0f%%", pt.balance / assetTotal * 100))
                                            .font(.caption2)
                                            .monospacedDigit()
                                            .foregroundStyle(pt.displayColor.opacity(0.6))
                                    }
                                }
                            }
                        }
                        if debt > 0 {
                            HStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.red.opacity(0.85))
                                    .frame(width: 4, height: 8)
                                Text(NSLocalizedString("bucket_debt", comment: ""))
                                    .font(.caption2)
                                    .foregroundStyle(Color.red.opacity(0.8))
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                HStack(spacing: 3) {
                                    Text(compactAmount(-debt))
                                        .font(.caption2.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.red)
                                    if assetTotal > 0 {
                                        Text(String(format: "%.0f%%", debt / assetTotal * 100))
                                            .font(.caption2)
                                            .monospacedDigit()
                                            .foregroundStyle(.red.opacity(0.6))
                                    }
                                }
                            }
                        }
                    }
                    if pts.count > 6 {
                        Text("+ \(pts.count - 6)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func compactAmount(_ value: Double) -> String {
        let abs = Swift.abs(value)
        let sign = value < 0 ? "-" : ""
        if abs >= 1_000_000 {
            return "\(sign)\(String(format: abs / 1_000_000 >= 10 ? "%.0f" : "%.1f", abs / 1_000_000))M"
        } else if abs >= 1_000 {
            return "\(sign)\(String(format: abs / 1_000 >= 10 ? "%.0f" : "%.1f", abs / 1_000))k"
        }
        return "\(sign)\(String(format: "%.0f", abs))"
    }

    private func monthLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = xGranularity == .day ? "d. MMMM yyyy" : "MMMM yyyy"
        return fmt.string(from: date)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle).foregroundStyle(.secondary.opacity(0.4))
            Text(NSLocalizedString("no_accounts", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
