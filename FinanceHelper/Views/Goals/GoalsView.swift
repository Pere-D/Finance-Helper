import SwiftUI
import SwiftData

// MARK: - Projection helper (top-level so DashboardView can also use it)

struct GoalProjectionResult {
    let achievableDate: Date?     // total assets (liquid + invest) >= goal — requires using all savings
    let recommendedDate: Date?    // liquid >= goal + 3×fixedCosts — 3-month emergency fund stays intact
    let optimalDate: Date?        // liquid >= goal + 6×fixedCosts — 6-month safety buffer
    let progressFraction: Double  // current total / goal, capped at 1
}

nonisolated func computeGoalProjection(
    targetAmount: Double,
    liquidCapital: Double,
    investCapital: Double,
    monthlyNetFlow: Double,
    growthRate: Double,
    monthlyFixedCosts: Double,
    startMonthOffset: Int = 0,
    includeInvestments: Bool = false,
    monthlyInvestContrib: Double = 0,
    oneTimeAdjustments: [Int: Double] = [:],
    emergencyMonths: Double = 3
) -> GoalProjectionResult {
    guard targetAmount > 0 else {
        return GoalProjectionResult(achievableDate: Date(), recommendedDate: Date(), optimalDate: Date(), progressFraction: 1.0)
    }
    let effectiveNow = includeInvestments ? (liquidCapital + investCapital) : liquidCapital
    let emergencyReserve = emergencyMonths * monthlyFixedCosts
    let thresholdN = targetAmount + emergencyReserve
    let threshold6 = targetAmount + 6 * monthlyFixedCosts
    // Progress represents how much of the goal amount is funded above the emergency reserve.
    // This gives correct sequential results: once goal N is achieved, startLiquid for goal N+1
    // equals the emergency reserve, so goal N+1 correctly shows 0% until new savings accumulate.
    let progress = min(1.0, max(0.0, effectiveNow - emergencyReserve) / max(1.0, targetAmount))
    let flow = max(0, monthlyNetFlow)
    let monthlyGrowth = growthRate / 100.0 / 12.0
    let cal = Calendar.current
    let now = Date()

    func projectedInvest(_ base: Double, months: Int) -> Double {
        guard months > 0 else { return base }
        if monthlyGrowth > 0 {
            let gf = pow(1.0 + monthlyGrowth, Double(months))
            return base * gf + monthlyInvestContrib * (gf - 1) / monthlyGrowth
        } else {
            return base + monthlyInvestContrib * Double(months)
        }
    }

    let totalNow = liquidCapital + investCapital
    var achievable: Date? = totalNow >= targetAmount ? cal.date(byAdding: .month, value: startMonthOffset, to: now) : nil
    var recommended: Date? = effectiveNow >= thresholdN ? cal.date(byAdding: .month, value: startMonthOffset, to: now) : nil
    var optimal: Date? = effectiveNow >= threshold6 ? cal.date(byAdding: .month, value: startMonthOffset, to: now) : nil

    if achievable == nil || recommended == nil || optimal == nil {
        var cumOneTime = 0.0
        for month in 1...360 {
            // One-time adjustments use absolute month offsets from "now"
            cumOneTime += oneTimeAdjustments[startMonthOffset + month] ?? 0
            let projLiquid = liquidCapital + Double(month) * flow + cumOneTime
            let projInvest = projectedInvest(investCapital, months: month)
            let projEffective = includeInvestments ? (projLiquid + projInvest) : projLiquid
            if achievable == nil && projLiquid + projInvest >= targetAmount {
                achievable = cal.date(byAdding: .month, value: startMonthOffset + month, to: now)
            }
            if recommended == nil && projEffective >= thresholdN {
                recommended = cal.date(byAdding: .month, value: startMonthOffset + month, to: now)
            }
            if optimal == nil && projEffective >= threshold6 {
                optimal = cal.date(byAdding: .month, value: startMonthOffset + month, to: now)
            }
            if achievable != nil && recommended != nil && optimal != nil { break }
        }
    }
    return GoalProjectionResult(achievableDate: achievable, recommendedDate: recommended, optimalDate: optimal, progressFraction: progress)
}

// MARK: - Sequential projection helper (top-level so DashboardView can also use it)

nonisolated func computeSequentialGoalProjections(
    goals: [FinancialGoal],
    liquidCapital: Double,
    investCapital: Double,
    monthlyNetFlow: Double,
    growthRate: Double,
    monthlyFixedCosts: Double,
    includeInvestments: Bool = false,
    monthlyInvestContrib: Double = 0,
    oneTimeAdjustments: [Int: Double] = [:],
    emergencyMonths: Double = 3,
    targetAmountOverrides: [UUID: Double] = [:],
    lockedDates: [UUID: Date] = [:]
) -> [(FinancialGoal, GoalProjectionResult)] {
    var results: [(FinancialGoal, GoalProjectionResult)] = []
    var startLiquid = liquidCapital
    var startInvest = investCapital
    var startMonthOffset = 0
    let flow = max(0, monthlyNetFlow)
    let monthlyGrowth = growthRate / 100.0 / 12.0
    let cal = Calendar.current
    let now = Date()

    func projectedInvest(_ base: Double, months: Int) -> Double {
        guard months > 0 else { return base }
        if monthlyGrowth > 0 {
            let gf = pow(1.0 + monthlyGrowth, Double(months))
            return base * gf + monthlyInvestContrib * (gf - 1) / monthlyGrowth
        } else {
            return base + monthlyInvestContrib * Double(months)
        }
    }

    for goal in goals {
        let proj = computeGoalProjection(
            targetAmount: targetAmountOverrides[goal.id] ?? goal.targetAmount,
            liquidCapital: startLiquid,
            investCapital: startInvest,
            monthlyNetFlow: monthlyNetFlow,
            growthRate: growthRate,
            monthlyFixedCosts: monthlyFixedCosts,
            startMonthOffset: startMonthOffset,
            includeInvestments: includeInvestments,
            monthlyInvestContrib: monthlyInvestContrib,
            oneTimeAdjustments: oneTimeAdjustments,
            emergencyMonths: emergencyMonths
        )
        results.append((goal, proj))

        // If a budget entry already commits this goal to a specific date, use that date
        // for the sequential deduction so subsequent goals see the correct starting position.
        let refDate = lockedDates[goal.id] ?? proj.recommendedDate ?? proj.achievableDate
        if let ref = refDate {
            let months = max(startMonthOffset, cal.dateComponents([.month], from: now, to: ref).month ?? startMonthOffset)
            let rel = months - startMonthOffset
            // Accumulate one-time adjustments that land within this goal's window
            let cumOT: Double = rel > 0
                ? (1...rel).reduce(0.0) { $0 + (oneTimeAdjustments[startMonthOffset + $1] ?? 0) }
                : 0
            let liquidAtGoal = startLiquid + Double(rel) * flow + cumOT
            let investAtGoal = projectedInvest(startInvest, months: rel)
            let effectiveTarget = targetAmountOverrides[goal.id] ?? goal.targetAmount
            if includeInvestments {
                let liquidUsed = min(liquidAtGoal, effectiveTarget)
                let investUsed = max(0, effectiveTarget - liquidAtGoal)
                startLiquid = max(0, liquidAtGoal - liquidUsed)
                startInvest = max(0, investAtGoal - investUsed)
            } else {
                startLiquid = max(0, liquidAtGoal - effectiveTarget)
                startInvest = investAtGoal
            }
            startMonthOffset = months
        }
    }
    return results
}

// MARK: - Goals View

struct GoalsView: View {
    let liquidCapital: Double
    let investCapital: Double
    let monthlyNetFlow: Double
    let growthRate: Double
    let monthlyFixedCosts: Double
    let monthlyInvestContrib: Double
    let oneTimeAdjustments: [Int: Double]
    let currency: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases
    @AppStorage("active_profile_id") private var activeProfileID: String = ""
    private let currencyService = CurrencyService.shared
    @Query(sort: [SortDescriptor(\FinancialGoal.priority), SortDescriptor(\FinancialGoal.createdAt)])
    private var allGoals: [FinancialGoal]

    @AppStorage("goals_include_investments") private var includeInvestments: Bool = false
    @AppStorage("goals_notgroschen_months") private var notgroschenMonths: Double = 3
    @State private var addGoalInput: AddGoalInput? = nil
    @State private var showingPaywall = false
    @State private var showingSettings = false
    @State private var editingGoal: FinancialGoal? = nil
    @State private var editMode: EditMode = .inactive

    private struct AddGoalInput: Identifiable {
        let id = UUID()
        let preselectedCategory: GoalCategory?
    }

    @Query(sort: \BudgetEntry.createdAt) private var allBudgetEntries: [BudgetEntry]

    private struct BudgetEntryPreset: Identifiable {
        let id = UUID()
        let category: BudgetCategory
        let amount: Double
        let notes: String
        let goalID: String
        let dueDate: Date?
    }
    @State private var budgetEntryPreset: BudgetEntryPreset? = nil

    private var goals: [FinancialGoal] {
        allGoals.filter { $0.profileID == activeProfileID && $0.isActive }
    }

    var body: some View {
        NavigationStack {
            Group {
                if goals.isEmpty {
                    categoryPickerContent
                } else {
                    goalsListContent
                }
            }
            .background(AnimatedPatternBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle(NSLocalizedString("goals_title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("done", comment: "")) {
                        if editMode == .active {
                            withAnimation { editMode = .inactive }
                        } else {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .tint(.primary)
                }
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if !goals.isEmpty {
                        Button {
                            withAnimation { editMode = editMode == .active ? .inactive : .active }
                        } label: {
                            Image(systemName: editMode == .active ? "checkmark" : "arrow.up.arrow.down")
                                .font(.subheadline)
                        }
                        .tint(.primary)
                    }
                    Button { showingSettings.toggle() } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .tint(.primary)
                }
                if !goals.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button { attemptAddGoal() } label: {
                            Image(systemName: "plus")
                        }
                        .tint(.primary)
                    }
                }
            }
            .fullScreenCover(item: $addGoalInput) { input in
                AddGoalSheet(existingGoals: goals, profileID: activeProfileID, currency: currency, preselectedCategory: input.preselectedCategory)
            }
            .fullScreenCover(item: $editingGoal) { goal in
                EditGoalSheet(goal: goal, allGoals: goals)
            }
            .fullScreenCover(isPresented: $showingPaywall) {
                PaywallView().environment(purchases)
            }
            .sheet(item: $budgetEntryPreset) { preset in
                AddEditBudgetEntryView(
                    presetCategory: preset.category,
                    presetAmount: preset.amount,
                    presetNotes: preset.notes,
                    presetDueDate: preset.dueDate,
                    presetIsOnce: true,
                    linkedGoalID: preset.goalID
                )
            }
            .sheet(isPresented: $showingSettings) { goalSettingsSheet }
        }
        .presentationDetents([.large])
    }

    // MARK: Category picker (empty state)

    private var categoryPickerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("goals_empty_title", comment: ""))
                        .font(.title3.weight(.bold))
                    Text(NSLocalizedString("goals_empty_subtitle", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(GoalCategory.allCases) { cat in
                        Button {
                            attemptAddGoal(category: cat)
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle().fill(cat.color.opacity(0.15)).frame(width: 48, height: 48)
                                    Image(systemName: cat.systemImage)
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(cat.color)
                                }
                                Text(cat.localizedName)
                                    .font(.caption2.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity)
                            .cardStyle(cornerRadius: 14)
                        }
                        .buttonStyle(ScalePressButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: Helpers

    private func attemptAddGoal(category: GoalCategory? = nil) {
        if !purchases.isPremium && goals.count >= 1 {
            showingPaywall = true
        } else {
            addGoalInput = AddGoalInput(preselectedCategory: category)
        }
    }

    // MARK: Sequential goal projections

    private func linkedBudgetEntry(for goal: FinancialGoal) -> BudgetEntry? {
        allBudgetEntries.first {
            $0.linkedGoalID == goal.id.uuidString && $0.profileID == activeProfileID && $0.isActive
        }
    }

    private func removeFromBudget(goal: FinancialGoal) {
        if let entry = linkedBudgetEntry(for: goal) {
            modelContext.delete(entry)
        }
    }

    private func budgetCategory(for goalCategory: GoalCategory) -> BudgetCategory {
        switch goalCategory {
        case .traumreise, .trips:
            return .urlaubRuecklage
        case .tech, .hobby, .fahrzeug, .wohnen, .haustier, .genuss, .lebensereign, .weiterbildung:
            return .grosseAnschaffungen
        case .startkapital, .custom:
            return .notgroschen
        }
    }

    private func addToBudget(goal: FinancialGoal, projection: GoalProjectionResult) {
        budgetEntryPreset = BudgetEntryPreset(
            category: budgetCategory(for: goal.category),
            amount: goal.targetAmount,
            notes: goal.name,
            goalID: goal.id.uuidString,
            dueDate: projection.recommendedDate
        )
    }

    private func convertedTarget(_ goal: FinancialGoal) -> Double {
        currencyService.convert(goal.targetAmount, from: goal.currency, to: currency)
    }

    private var lockedGoalDates: [UUID: Date] {
        Dictionary(uniqueKeysWithValues: allBudgetEntries.compactMap { entry -> (UUID, Date)? in
            guard entry.isActive, let idStr = entry.linkedGoalID,
                  let goal = goals.first(where: { $0.id.uuidString == idStr }) else { return nil }
            let due = entry.nextDueDate() ?? entry.dueDate
            return (goal.id, due)
        })
    }

    private func sequentialProjections() -> [(FinancialGoal, GoalProjectionResult)] {
        let overrides = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, convertedTarget($0)) })
        return computeSequentialGoalProjections(
            goals: goals,
            liquidCapital: liquidCapital,
            investCapital: investCapital,
            monthlyNetFlow: monthlyNetFlow,
            growthRate: growthRate,
            monthlyFixedCosts: monthlyFixedCosts,
            includeInvestments: includeInvestments,
            monthlyInvestContrib: monthlyInvestContrib,
            oneTimeAdjustments: oneTimeAdjustments,
            emergencyMonths: notgroschenMonths,
            targetAmountOverrides: overrides,
            lockedDates: lockedGoalDates
        )
    }

    // MARK: Goals list

    private var goalsListContent: some View {
        let projs = sequentialProjections()
        let projDict: [UUID: (GoalProjectionResult, Int)] = Dictionary(
            uniqueKeysWithValues: projs.enumerated().map { ($0.element.0.id, ($0.element.1, $0.offset)) }
        )
        return List {
            Section {
                ForEach(goals, id: \.id) { goal in
                    if let (proj, idx) = projDict[goal.id] {
                        GoalProjectionCard(
                            goal: goal, projection: proj, currency: currency, priorityIndex: idx,
                            convertedTargetAmount: convertedTarget(goal),
                            linkedEntry: linkedBudgetEntry(for: goal),
                            onAddToBudget: { addToBudget(goal: goal, projection: proj) },
                            onRemoveBudgetEntry: { removeFromBudget(goal: goal) }
                        )
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                        .onTapGesture { if editMode == .inactive { editingGoal = goal } }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    }
                }
                .onMove { from, to in
                    var ordered = goals
                    ordered.move(fromOffsets: from, toOffset: to)
                    for (idx, g) in ordered.enumerated() { g.priority = idx }
                }
                .onDelete { offsets in
                    offsets.map { goals[$0] }.forEach { $0.isActive = false }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
    }

    // MARK: Settings sheet

    private var goalSettingsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Notgroschen Reserve")
                        Spacer()
                        Text(notgroschenMonths == 0 ? "Kein Puffer" : "\(Int(notgroschenMonths)) Monat\(notgroschenMonths == 1 ? "" : "e")")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $notgroschenMonths, in: 0...6, step: 1)
                        .tint(.primary)
                    if notgroschenMonths > 0 {
                        let reserveAmount = notgroschenMonths * monthlyFixedCosts
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Monatliche Fixkosten")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(monthlyFixedCosts, format: .currency(code: "CHF"))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                            }
                            HStack {
                                Text("Reserve (\(Int(notgroschenMonths)) × \(Int(monthlyFixedCosts).formatted(.number)) CHF)")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(reserveAmount, format: .currency(code: "CHF"))
                                    .monospacedDigit()
                                    .foregroundStyle(.orange)
                                    .contentTransition(.numericText())
                            }
                        }
                        .font(.footnote)
                        .padding(.vertical, 4)
                    }
                } header: {
                    Label("Reserve", systemImage: "banknote")
                } footer: {
                    if notgroschenMonths == 0 {
                        Text("Kein Puffer — Ziel gilt als erreichbar sobald genug Kapital vorhanden ist.")
                    } else {
                        let months = Int(notgroschenMonths)
                        let unit = months == 1 ? NSLocalizedString("Monat", comment: "") : NSLocalizedString("Monate", comment: "")
                        Text(String(format: NSLocalizedString("Ziel gilt erst als erreichbar wenn zusätzlich %lld %@ Ausgaben als Reserve verbleiben.", comment: ""), months, unit))
                    }
                }

                Section {
                    Toggle(isOn: $includeInvestments) {
                        Label(NSLocalizedString("goals_include_investments", comment: ""), systemImage: "building.columns.fill")
                    }
                    .tint(.blue)
                } header: {
                    Label("Kapital", systemImage: "chart.bar.fill")
                }

                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                            .padding(.top, 2)
                        Text(NSLocalizedString("goals_legend_order_hint", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Hinweis", systemImage: "info.circle")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(AnimatedPatternBackground())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("done", comment: "")) { showingSettings = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Goal Projection Card

private struct GoalProjectionCard: View {
    let goal: FinancialGoal
    let projection: GoalProjectionResult
    let currency: String
    let priorityIndex: Int
    var convertedTargetAmount: Double? = nil
    var linkedEntry: BudgetEntry? = nil
    var onAddToBudget: () -> Void = {}
    var onRemoveBudgetEntry: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(goal.category.color.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: goal.category.systemImage)
                        .font(.title3)
                        .foregroundStyle(goal.category.color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .font(.headline.weight(.bold))
                    Text((convertedTargetAmount ?? goal.targetAmount).formatted(.currency(code: currency).notation(.compactName)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f%%", projection.progressFraction * 100))
                        .font(.system(.subheadline, design: .rounded).weight(.black))
                        .foregroundStyle(goal.category.color)
                        .contentTransition(.numericText())
                    Text("Fortschritt")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(goal.category.color.opacity(0.07))
                        .frame(height: 11)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [goal.category.color, goal.category.color.opacity(0.4)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(11, geo.size.width * CGFloat(projection.progressFraction)), height: 11)
                        .shadow(color: goal.category.color.opacity(0.3), radius: 6, x: 0, y: 0)
                }
            }
            .frame(height: 11)

            // Projection date — hidden when a budget entry already exists
            if linkedEntry == nil {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(projection.recommendedDate != nil ? Color.primary.opacity(0.7) : .secondary)
                        Text("Prognose")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let d = projection.recommendedDate {
                        let isNow = Calendar.current.compare(d, to: Date(), toGranularity: .month) != .orderedDescending
                        Text(isNow ? NSLocalizedString("goal_now", comment: "") : d.formatted(.dateTime.month(.wide).year()))
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(isNow ? .green : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background {
                                Capsule()
                                    .fill(isNow ? Color.green.opacity(0.1) : Color.primary.opacity(0.05))
                            }
                    } else {
                        Text("—")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 4)
            }

            if let entry = linkedEntry {
                let payDate = entry.nextDueDate() ?? entry.dueDate
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("Zahlung")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(payDate.formatted(.dateTime.month(.wide).year()))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            }

            Divider()

            if linkedEntry != nil {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Im Budget eingetragen")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button(action: onRemoveBudgetEntry) {
                        HStack(spacing: 3) {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .medium))
                            Text("Entfernen")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.red.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(action: onAddToBudget) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.caption2)
                        Text("Als Sparbetrag ins Budget")
                            .font(.caption2.weight(.medium))
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .cardStyle(cornerRadius: 14)
    }
}

// MARK: - Edit Goal Sheet

private struct EditGoalSheet: View {
    let goal: FinancialGoal
    let allGoals: [FinancialGoal]

    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: GoalCategory
    @State private var goalName: String
    @State private var amountText: String
    @State private var goalPosition: Int
    @State private var selectedPreset: Double? = nil

    init(goal: FinancialGoal, allGoals: [FinancialGoal]) {
        self.goal = goal
        self.allGoals = allGoals
        _selectedCategory = State(initialValue: goal.category)
        _goalName = State(initialValue: goal.name)
        let amt = goal.targetAmount
        _amountText = State(initialValue: amt == floor(amt) ? "\(Int(amt))" : String(format: "%.2f", amt))
        let idx = allGoals.firstIndex(where: { $0.id == goal.id }) ?? 0
        _goalPosition = State(initialValue: idx + 1)
    }

    private var parsedAmount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var canSave: Bool {
        !goalName.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(selectedCategory.color.opacity(0.15)).frame(width: 50, height: 50)
                            Image(systemName: selectedCategory.systemImage)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(selectedCategory.color)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedCategory.localizedName).font(.headline)
                            Text(selectedCategory.fullDescription).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(NSLocalizedString("goal_name_section", comment: "")) {
                    TextField(NSLocalizedString("goal_name_placeholder", comment: ""), text: $goalName)
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedCategory.suggestedAmounts, id: \.self) { amt in
                                Button {
                                    selectedPreset = amt
                                    amountText = amt == floor(amt) ? "\(Int(amt))" : String(format: "%.2f", amt)
                                } label: {
                                    Text(amt.formatted(.currency(code: goal.currency).precision(.fractionLength(0))))
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selectedPreset == amt
                                            ? selectedCategory.color.opacity(0.20)
                                            : Color.secondary.opacity(0.10))
                                        .foregroundStyle(selectedPreset == amt ? selectedCategory.color : .secondary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    HStack {
                        Text(goal.currency).foregroundStyle(.secondary).font(.subheadline)
                        TextField(NSLocalizedString("goal_amount_placeholder", comment: ""), text: $amountText)
                            .keyboardType(.decimalPad)
                            .onChange(of: amountText) { _, _ in selectedPreset = nil }
                    }
                } header: { Text(NSLocalizedString("goal_amount_section", comment: "")) }

                Section {
                    Stepper(
                        String(format: NSLocalizedString("goal_priority_stepper", comment: ""), goalPosition, allGoals.count),
                        value: $goalPosition,
                        in: 1...max(1, allGoals.count)
                    )
                } header: {
                    Text(NSLocalizedString("goal_priority_section", comment: ""))
                } footer: {
                    if goalPosition == 1 {
                        Text(NSLocalizedString("goal_priority_first_footer", comment: ""))
                            .font(.caption)
                    } else {
                        Text(String(format: NSLocalizedString("goal_priority_nth_footer", comment: ""), goalPosition - 1))
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("goal_edit_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Color.blue.opacity(0.03))
            .background(AnimatedPatternBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", comment: "")) { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        goal.name = goalName.trimmingCharacters(in: .whitespaces)
        goal.targetAmount = parsedAmount
        goal.categoryRaw = selectedCategory.rawValue

        let currentIdx = allGoals.firstIndex(where: { $0.id == goal.id }) ?? 0
        let targetIdx = goalPosition - 1
        if targetIdx != currentIdx {
            var ordered = Array(allGoals)
            ordered.remove(at: currentIdx)
            ordered.insert(goal, at: min(targetIdx, ordered.count))
            for (idx, g) in ordered.enumerated() { g.priority = idx }
        }
        dismiss()
    }
}

// MARK: - Add Goal Sheet

private struct AddGoalSheet: View {
    let existingGoals: [FinancialGoal]
    let profileID: String
    let currency: String
    let preselectedCategory: GoalCategory?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: GoalCategory?
    @State private var goalName: String = ""
    @State private var amountText: String = ""
    @State private var goalPosition: Int
    @State private var selectedPreset: Double? = nil

    private var effectiveCat: GoalCategory { selectedCategory ?? .custom }
    private var targetAmount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var canSave: Bool {
        !goalName.trimmingCharacters(in: .whitespaces).isEmpty && targetAmount > 0 && selectedCategory != nil
    }

    init(existingGoals: [FinancialGoal], profileID: String, currency: String, preselectedCategory: GoalCategory?) {
        self.existingGoals = existingGoals
        self.profileID = profileID
        self.currency = currency
        self.preselectedCategory = preselectedCategory
        _selectedCategory = State(initialValue: preselectedCategory)
        _goalName = State(initialValue: "")
        _goalPosition = State(initialValue: existingGoals.count + 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                if preselectedCategory == nil {
                    categoryPickerSection
                }

                if let cat = selectedCategory {
                    Section {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(cat.color.opacity(0.15)).frame(width: 50, height: 50)
                                Image(systemName: cat.systemImage)
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(cat.color)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(cat.localizedName).font(.headline)
                                Text(cat.fullDescription).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(NSLocalizedString("goal_name_section", comment: "")) {
                    TextField(effectiveCat.localizedName, text: $goalName)
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(effectiveCat.suggestedAmounts, id: \.self) { amt in
                                Button {
                                    selectedPreset = amt
                                    amountText = amt == floor(amt) ? "\(Int(amt))" : String(format: "%.2f", amt)
                                } label: {
                                    Text(amt.formatted(.currency(code: currency).precision(.fractionLength(0))))
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selectedPreset == amt
                                            ? effectiveCat.color.opacity(0.20)
                                            : Color.secondary.opacity(0.10))
                                        .foregroundStyle(selectedPreset == amt ? effectiveCat.color : .secondary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    HStack {
                        Text(currency).foregroundStyle(.secondary).font(.subheadline)
                        TextField(NSLocalizedString("goal_custom_amount_placeholder", comment: ""), text: $amountText)
                            .keyboardType(.decimalPad)
                            .onChange(of: amountText) { _, _ in selectedPreset = nil }
                    }
                } header: { Text(NSLocalizedString("goal_amount_section", comment: "")) }

                if existingGoals.count > 0 {
                    Section {
                        Stepper(
                            String(format: NSLocalizedString("goal_priority_stepper", comment: ""), goalPosition, existingGoals.count + 1),
                            value: $goalPosition,
                            in: 1...(existingGoals.count + 1)
                        )
                    } header: {
                        Text(NSLocalizedString("goal_priority_section", comment: ""))
                    } footer: {
                        if goalPosition == 1 {
                            Text(NSLocalizedString("goal_priority_first_footer", comment: ""))
                                .font(.caption)
                        } else {
                            Text(String(format: NSLocalizedString("goal_priority_nth_footer", comment: ""), goalPosition - 1))
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("goal_add_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Color.blue.opacity(0.03))
            .background(AnimatedPatternBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("add", comment: "")) { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var categoryPickerSection: some View {
        Section(NSLocalizedString("goal_category_section", comment: "")) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(GoalCategory.allCases) { cat in
                    Button {
                        selectedCategory = cat
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(selectedCategory == cat ? cat.color : Color.blue.opacity(0.08))
                                    .frame(width: 40, height: 40)
                                Image(systemName: cat.systemImage)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(selectedCategory == cat ? .white : cat.color)
                            }
                            Text(cat.localizedName)
                                .font(.caption2.weight(.medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(selectedCategory == cat ? cat.color : .secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func save() {
        let targetPriority = goalPosition - 1
        for g in existingGoals where g.priority >= targetPriority {
            g.priority += 1
        }
        let goal = FinancialGoal(
            profileID: profileID,
            name: goalName.trimmingCharacters(in: .whitespaces),
            category: effectiveCat,
            targetAmount: targetAmount,
            currency: currency
        )
        goal.priority = targetPriority
        modelContext.insert(goal)
        dismiss()
    }
}
