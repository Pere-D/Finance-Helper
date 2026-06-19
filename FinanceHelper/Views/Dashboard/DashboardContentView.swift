import SwiftUI
import SwiftData
import WidgetKit

struct DashboardContentView: View {
    let profileID: String
    
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [Account]
    @Query private var budgetEntries: [BudgetEntry]
    @Query private var transactions: [ImportedTransaction]
    @Query private var goals: [FinancialGoal]
    
    @AppStorage("default_currency") private var defaultCurrency = "EUR"
    @AppStorage("goals_include_investments") private var includeInvestments: Bool = false
    @AppStorage("goals_notgroschen_months") private var notgroschenMonths: Double = 3
    @AppStorage("bg_theme") private var rawTheme = BackgroundTheme.emerald.rawValue
    
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var viewModel = DashboardViewModel()
    @State private var showingAccounts = false
    @State private var showingSettings = false
    @State private var showingInsights = false
    @State private var showingGoals = false
    @State private var showingAddBudgetEntry = false
    @State private var showingPaywall = false
    @State private var chartMonths: Int = 12
    @State private var selectedPageTab: Int = 0
    @State private var cachedTotalData: [DashboardViewModel.ChartPoint] = []
    @State private var cachedStackedData: [DashboardViewModel.AccountChartPoint] = []
    @State private var cachedSnapshots: [DashboardViewModel.BalanceSnapshot] = []
    @State private var cachedHistoricalData: [ProjectionService.ChartPoint] = []
    @State private var cachedGoalMarkers: [GoalMarker] = []
    @State private var cachedGoalEntryMarkers: [GoalMarker] = []

    init(profileID: String) {
        self.profileID = profileID
        
        let accountPredicate = #Predicate<Account> { $0.profileID == profileID }
        _accounts = Query(filter: accountPredicate, sort: \Account.createdAt)
        
        let budgetPredicate = #Predicate<BudgetEntry> { $0.profileID == profileID }
        _budgetEntries = Query(filter: budgetPredicate, sort: \BudgetEntry.createdAt)
        
        let transactionPredicate = #Predicate<ImportedTransaction> { $0.profileID == profileID }
        _transactions = Query(filter: transactionPredicate, sort: \ImportedTransaction.date)
        
        let goalPredicate = #Predicate<FinancialGoal> { $0.profileID == profileID && $0.isActive }
        _goals = Query(filter: goalPredicate, sort: [SortDescriptor(\FinancialGoal.priority), SortDescriptor(\FinancialGoal.createdAt)])
    }

    var body: some View {
        contentLayout
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AnimatedPatternBackground())
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .tint(.primary)
            }
            ToolbarItem(placement: .principal) { ProfilePill() }
            ToolbarItem(placement: .primaryAction) {
                Button { showingAccounts = true } label: {
                    Image(systemName: "creditcard")
                }
                .tint(.primary)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingInsights = true } label: {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.2))
                        .shadow(color: Color(red: 1.0, green: 0.75, blue: 0.1).opacity(0.7), radius: 5, x: 0, y: 0)
                }
            }
        }
        .fullScreenCover(isPresented: $showingSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showingAccounts) { AccountsView() }
        .fullScreenCover(isPresented: $showingInsights) { InsightsSheet(viewModel: viewModel, currency: defaultCurrency) }
        .fullScreenCover(isPresented: $showingGoals) {
            GoalsView(
                liquidCapital: viewModel.liquidTotal,
                investCapital: viewModel.investmentTotal,
                monthlyNetFlow: viewModel.monthlyNetCashFlow,
                growthRate: viewModel.averageInvestmentGrowthRate,
                monthlyFixedCosts: viewModel.totalMonthlyFixedCosts,
                monthlyInvestContrib: viewModel.totalMonthlyInvestContrib,
                oneTimeAdjustments: viewModel.goalProjectionAdjustments,
                currency: defaultCurrency
            )
        }
        .fullScreenCover(isPresented: $showingAddBudgetEntry) { AddEditBudgetEntryView() }
        .fullScreenCover(isPresented: $showingPaywall) { PaywallView().environment(purchases) }
        .onChange(of: accounts) { viewModel.accounts = accounts; viewModel.writeWidgetSnapshot(); refreshChartData() }
        .onChange(of: accounts.map(\.isVisible)) { viewModel.accounts = accounts }
        .onChange(of: showingAccounts) { if !showingAccounts { viewModel.accounts = accounts; refreshChartData() } }
        .onChange(of: budgetEntries) { viewModel.budgetEntries = budgetEntries; viewModel.writeWidgetSnapshot(); refreshChartData() }
        .onChange(of: defaultCurrency) { viewModel.displayCurrency = defaultCurrency; viewModel.writeWidgetSnapshot(); refreshChartData() }
        .onChange(of: transactions) { refreshChartData() }
        .onChange(of: goals) { refreshChartData() }
        .onChange(of: notgroschenMonths) { refreshChartData() }
        .onChange(of: chartMonths) { refreshChartData() }
        .onAppear {
            viewModel.accounts = accounts
            viewModel.budgetEntries = budgetEntries
            viewModel.displayCurrency = defaultCurrency
            Task {
                refreshChartData()
                await viewModel.fetchExchangeRates()
                viewModel.writeWidgetSnapshot()
                refreshChartData()
            }
        }
    }

    // MARK: - Adaptive Layout

    @ViewBuilder
    private var contentLayout: some View {
        if horizontalSizeClass == .regular {
            VStack(spacing: 12) {
                netWorthCard
                wealthChartPagedCard
                    .frame(height: 420)
                goalsCard
                Spacer()
            }
        } else {
            VStack(spacing: 12) {
                netWorthCard
                wealthChartPagedCard
                    .layoutPriority(1)
                goalsCard
            }
        }
    }

    // MARK: - Net Worth Hero

    private var netWorthCard: some View {
        VStack(spacing: 8) {
            Text("Gesamtvermögen")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            Text(viewModel.netWorth.formatted(.currency(code: defaultCurrency)))
                .font(.system(size: 72, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
                .shadow(color: netWorthGlowColor.opacity(0.28), radius: 16, x: 0, y: 0)
                .shadow(color: netWorthGlowColor.opacity(0.15), radius: 6, x: 0, y: 2)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .contentTransition(.numericText())

            HStack(spacing: 5) {
                Image(systemName: viewModel.monthlyNetCashFlow >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption.weight(.semibold))
                Text(abs(viewModel.monthlyNetCashFlow).formatted(.currency(code: defaultCurrency))
                     + " / " + NSLocalizedString("month_abbrev", comment: ""))
                    .font(.subheadline.weight(.medium))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(viewModel.monthlyNetCashFlow >= 0 ? Color.green : Color.red)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background((viewModel.monthlyNetCashFlow >= 0 ? Color.green : Color.red).opacity(0.1))
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal)
    }

    private var netWorthGlowColor: Color {
        viewModel.netWorth >= 0 ? .green : .red
    }

    // MARK: - Wealth + Chart paged card

    private var wealthChartPagedCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                pageTabButton(tab: 0, label: NSLocalizedString("wealth_allocation", comment: ""), icon: "chart.pie.fill")
                pageTabButton(tab: 1, label: NSLocalizedString("balance_projection", comment: ""), icon: "chart.line.uptrend.xyaxis")

                if selectedPageTab == 1 {
                    Picker("", selection: $chartMonths) {
                        ForEach([3, 6, 12, 24, 36, 60, 120, 240], id: \.self) { preset in
                            Text(formatMonthsLabel(preset)).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(.secondary)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.2), value: selectedPageTab)

            Divider()

            TabView(selection: $selectedPageTab) {
                WealthBucketsCard(
                    viewModel: viewModel,
                    currency: defaultCurrency,
                    themeAccent: themeAccent,
                    onAddAccount: { showingAccounts = true },
                    onAddBudgetEntry: { attemptAddBudgetEntry() }
                )
                .tag(0)

                chartCard
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cardStyle()
    }

    private func pageTabButton(tab: Int, label: String, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { selectedPageTab = tab }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption2.weight(.medium))
                Text(label).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(selectedPageTab == tab ? Color.primary.opacity(0.08) : Color.secondary.opacity(0.06))
            .foregroundStyle(selectedPageTab == tab ? Color.primary : Color.secondary)
            .clipShape(Capsule())
        }
    }

    // MARK: - Goals Card

    private var goalsCard: some View {
        Button { showingGoals = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(Color.blue.opacity(0.12)).frame(width: 30, height: 30)
                            Image(systemName: "target")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.blue)
                        }
                        Text(NSLocalizedString("goals_title", comment: ""))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }

                if goals.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
                        Text(NSLocalizedString("goals_first_goal", comment: ""))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } else if let goal = goals.sorted(by: {
                        $0.priority != $1.priority ? $0.priority < $1.priority : $0.createdAt < $1.createdAt
                    }).first {
                    let proj = computeGoalProjection(
                        targetAmount: goal.targetAmount,
                        liquidCapital: viewModel.liquidTotal,
                        investCapital: viewModel.investmentTotal,
                        monthlyNetFlow: viewModel.monthlyNetCashFlow,
                        growthRate: viewModel.averageInvestmentGrowthRate,
                        monthlyFixedCosts: viewModel.totalMonthlyFixedCosts,
                        includeInvestments: includeInvestments,
                        monthlyInvestContrib: viewModel.totalMonthlyInvestContrib,
                        oneTimeAdjustments: viewModel.goalProjectionAdjustments,
                        emergencyMonths: notgroschenMonths
                    )
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.name).font(.caption.weight(.bold)).lineLimit(1)
                            Text(goal.targetAmount.formatted(.currency(code: defaultCurrency).notation(.compactName)))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                        Spacer()
                        if let rec = proj.recommendedDate {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(rec.formatted(.dateTime.month(.abbreviated).year()))
                                    .font(.system(.subheadline, design: .rounded).weight(.black))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    
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
                                .frame(width: max(11, geo.size.width * CGFloat(proj.progressFraction)), height: 11)
                                .shadow(color: goal.category.color.opacity(0.3), radius: 6, x: 0, y: 0)
                        }
                    }
                    .frame(height: 11)
                }
            }
            .padding(18)
            .cardStyle(cornerRadius: 14)
        }
        .buttonStyle(ScalePressButtonStyle())
    }

    // MARK: - Balance Projection Card

    private var chartCard: some View {
        Group {
            if accounts.isEmpty {
                emptyChartState
            } else {
                BalanceChartView(
                    totalData: cachedTotalData,
                    stackedData: cachedStackedData,
                    snapshots: cachedSnapshots,
                    currency: defaultCurrency,
                    months: chartMonths,
                    goalMarkers: cachedGoalMarkers,
                    goalEntryMarkers: cachedGoalEntryMarkers,
                    historicalLine: cachedHistoricalData,
                    historicalLineColor: historicalLineColor,
                    isInteractive: selectedPageTab == 1
                )
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(colorScheme == .dark ? Color.clear : Color(.systemBackground))
    }

    private var emptyChartState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.largeTitle).foregroundStyle(.secondary.opacity(0.4))
            VStack(spacing: 4) {
                Text("Keine Prognose verfügbar")
                    .font(.subheadline.weight(.semibold))
                Text("Füge ein Konto oder einen Budgeteintrag hinzu, um deine Prognose zu sehen.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                Button { showingAccounts = true } label: {
                    Label("Konto hinzufügen", systemImage: "plus.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(themeAccent).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                Button { attemptAddBudgetEntry() } label: {
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
        .padding(.vertical, 28)
    }

    private var themeAccent: Color { BackgroundTheme(rawValue: rawTheme)?.primary ?? .blue }

    private func attemptAddBudgetEntry() {
        if !purchases.isPremium && budgetEntries.count >= 10 {
            showingPaywall = true
        } else {
            showingAddBudgetEntry = true
        }
    }

    private var historicalLineColor: Color {
        let dominant = accounts
            .filter { $0.isVisible && !$0.type.isLiability }
            .max(by: {
                viewModel.convert(max(0, $0.balance), from: $0.currency, to: defaultCurrency) <
                viewModel.convert(max(0, $1.balance), from: $1.currency, to: defaultCurrency)
            })
        return dominant?.customAccountType?.color ?? Color.primary
    }

    private func refreshChartData() {
        // Compute main-actor-isolated chart data synchronously
        let capturedChartMonths = chartMonths
        let total = capturedChartMonths <= 3
            ? viewModel.projectedBalanceDailyData(days: capturedChartMonths * 30)
            : viewModel.projectedBalanceData(months: capturedChartMonths)
        let stacked = viewModel.stackedFutureData(months: capturedChartMonths)
        let snaps = viewModel.balanceSnapshots(months: capturedChartMonths)
        let hist = viewModel.historicalChartData(transactions: transactions, profileID: profileID)
        cachedTotalData = total
        cachedStackedData = stacked
        cachedSnapshots = snaps
        cachedHistoricalData = hist

        // Compute goal projections in background (pure calculation, no actor-isolated access needed)
        let capturedEmergencyMonths = notgroschenMonths
        let capturedGoals = goals
        let capturedBudgetEntries = budgetEntries
        let goalAppearance: [UUID: (color: Color, icon: String)] = Dictionary(
            uniqueKeysWithValues: capturedGoals.map { ($0.id, (color: $0.category.color, icon: $0.category.systemImage)) }
        )
        let liquidCapital = viewModel.liquidTotal
        let investCapital = viewModel.investmentTotal
        let monthlyNetFlow = viewModel.monthlyNetCashFlow
        let growthRate = viewModel.averageInvestmentGrowthRate
        let monthlyFixedCosts = viewModel.totalMonthlyFixedCosts
        let monthlyInvestContrib = viewModel.totalMonthlyInvestContrib
        let goalAdjustments = viewModel.goalProjectionAdjustments
        let capturedIncludeInvestments = includeInvestments
        Task.detached(priority: .userInitiated) {
            let cutoff = Calendar.current.date(byAdding: .month, value: capturedChartMonths, to: Date()) ?? Date()
            let sortedGoals = capturedGoals.sorted {
                $0.priority != $1.priority ? $0.priority < $1.priority : $0.createdAt < $1.createdAt
            }
            let lockedDates: [UUID: Date] = Dictionary(uniqueKeysWithValues:
                capturedBudgetEntries.compactMap { entry -> (UUID, Date)? in
                    guard entry.isActive, let idStr = entry.linkedGoalID,
                          let goal = capturedGoals.first(where: { $0.id.uuidString == idStr }) else { return nil }
                    let due = entry.nextDueDate() ?? entry.dueDate
                    return (goal.id, due)
                }
            )
            let projs = computeSequentialGoalProjections(
                goals: Array(sortedGoals.prefix(5)),
                liquidCapital: liquidCapital,
                investCapital: investCapital,
                monthlyNetFlow: monthlyNetFlow,
                growthRate: growthRate,
                monthlyFixedCosts: monthlyFixedCosts,
                includeInvestments: capturedIncludeInvestments,
                monthlyInvestContrib: monthlyInvestContrib,
                oneTimeAdjustments: goalAdjustments,
                emergencyMonths: capturedEmergencyMonths,
                lockedDates: lockedDates
            )
            // Goals that already have a linked budget entry are represented by goalEntryMarkers —
            // skip them here to avoid showing the same goal twice in the chart.
            let goalIDsWithEntry = Set(
                capturedBudgetEntries
                    .filter { $0.isActive && $0.linkedGoalID != nil && $0.recurrence == .once }
                    .compactMap { $0.linkedGoalID }
            )
            let markers = projs.compactMap { goal, proj -> GoalMarker? in
                guard !goalIDsWithEntry.contains(goal.id.uuidString) else { return nil }
                guard let date = proj.recommendedDate, date <= cutoff else { return nil }
                return GoalMarker(name: goal.name, color: goalAppearance[goal.id]?.color ?? .orange, date: date, icon: goalAppearance[goal.id]?.icon ?? "target")
            }

            let today = Calendar.current.startOfDay(for: Date())
            let horizonDays = capturedChartMonths * 32
            let entryMarkers: [GoalMarker] = capturedBudgetEntries
                .filter { $0.isActive && $0.linkedGoalID != nil && $0.recurrence == .once }
                .compactMap { entry -> GoalMarker? in
                    guard let due = entry.nextDueDate(after: today) else { return nil }
                    let dayKey = Calendar.current.startOfDay(for: due)
                    let offset = Calendar.current.dateComponents([.day], from: today, to: dayKey).day ?? 0
                    guard offset > 0 && offset <= horizonDays else { return nil }
                    let linkedGoal = capturedGoals.first { $0.id.uuidString == entry.linkedGoalID }
                    return GoalMarker(
                        name: linkedGoal?.name ?? "",
                        color: linkedGoal.flatMap { goalAppearance[$0.id]?.color } ?? .orange,
                        date: due,
                        icon: linkedGoal.flatMap { goalAppearance[$0.id]?.icon } ?? "target"
                    )
                }

            await MainActor.run {
                self.cachedGoalMarkers = markers
                self.cachedGoalEntryMarkers = entryMarkers
            }
        }
    }

    private func formatMonthsLabel(_ months: Int) -> String {
        if months < 12 { return String(format: NSLocalizedString("months_label_months", comment: ""), months) }
        let years = months / 12
        let rem = months % 12
        return rem == 0 
            ? String(format: NSLocalizedString("months_label_years", comment: ""), years)
            : String(format: NSLocalizedString("months_label_years_months", comment: ""), years, rem)
    }
}
