import Foundation
import SwiftUI
import Observation
import WidgetKit

@Observable
final class DashboardViewModel {
    var accounts: [Account] = []
    var budgetEntries: [BudgetEntry] = []
    var displayCurrency: String = "EUR"
    
    private let currencyService = CurrencyService.shared
    
    var isSynced: Bool { currencyService.lastSyncSuccessful }

    func convert(_ amount: Double, from: String, to: String) -> Double {
        currencyService.convert(amount, from: from, to: to)
    }

    func fetchExchangeRates() async {
        await currencyService.fetchExchangeRates()
    }

    private var visibleAccounts: [Account] { accounts.filter(\.isVisible) }

    /// When true, goal-linked budget entries are excluded from the projection line.
    var excludeGoalEntries: Bool = false

    private var standaloneBudgetEntries: [BudgetEntry] {
        budgetEntries.filter { $0.account == nil && $0.isCurrentlyActive }
    }

    // MARK: - Helper for Redundant Sums

    private func sumVisibleAccounts(where filter: (Account) -> Bool = { _ in true },
                                    value: (Account) -> Double) -> Double {
        visibleAccounts.filter(filter)
            .reduce(0) { $0 + convert(value($1), from: $1.currency, to: displayCurrency) }
    }

    // MARK: - Totals

    var totalAssets: Double {
        sumVisibleAccounts(where: { !$0.type.isLiability }, value: { max(0, $0.balance) })
    }

    var totalLiabilities: Double {
        sumVisibleAccounts(where: { $0.type.isLiability }, value: { $0.balance })
    }

    var netWorth: Double { totalAssets - totalLiabilities }

    var totalMonthlyIncome: Double {
        let fromAccounts = sumVisibleAccounts(value: { $0.monthlyIncome })
        let fromStandalone = standaloneBudgetEntries
            .filter { $0.isIncomeEntry && $0.transferToAccount == nil }
            .reduce(0) { $0 + convert($1.effectiveMonthlyAmount, from: $1.currencyOverride ?? displayCurrency, to: displayCurrency) }
        return fromAccounts + fromStandalone
    }

    var totalMonthlyExpenses: Double {
        let fromAccounts = sumVisibleAccounts(value: { $0.monthlyExpenses })
        let fromStandalone = standaloneBudgetEntries
            .filter { !$0.isIncomeEntry && !$0.isSavingsEntry && $0.transferToAccount == nil }
            .reduce(0) { $0 + convert($1.effectiveMonthlyAmount, from: $1.currencyOverride ?? displayCurrency, to: displayCurrency) }
        return fromAccounts + fromStandalone
    }

    var totalMonthlySavings: Double {
        let fromAccounts = sumVisibleAccounts(value: { $0.monthlySavings })
        let fromStandalone = standaloneBudgetEntries
            .filter { $0.isSavingsEntry }
            .reduce(0) { $0 + convert($1.effectiveMonthlyAmount, from: $1.currencyOverride ?? displayCurrency, to: displayCurrency) }
        return fromAccounts + fromStandalone
    }

    var monthlySavingsForPlanner: Double { totalMonthlySavings }

    var monthlyNetCashFlow: Double {
        totalMonthlyIncome - totalMonthlyExpenses - totalMonthlySavings
    }

    // MARK: - Planner Projection

    struct PlannerPoint: Identifiable {
        let id = UUID()
        let date: Date
        let balance: Double
        let eventAmount: Double
    }

    func plannerProjection(months: Int) -> [PlannerPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let oneTime = oneTimeAdjustments(upToMonths: months)
        let monthly = monthlyNetCashFlow
        let r = averageInvestmentGrowthRate / 100.0 / 12.0
        var balance = netWorth

        return (0...months).map { i in
            let date = cal.date(byAdding: .month, value: i, to: today) ?? today
            if i == 0 { return PlannerPoint(date: date, balance: balance, eventAmount: 0) }
            balance = balance * (1 + r) + monthly
            let event = oneTime[i] ?? 0
            balance += event
            return PlannerPoint(date: date, balance: balance, eventAmount: event)
        }
    }

    // MARK: - Bucket totals

    var liquidTotal: Double {
        sumVisibleAccounts(where: { $0.type.isLiquid || $0.type == .festgeld }, value: { $0.balance })
    }

    var investmentTotal: Double {
        sumVisibleAccounts(where: { $0.type == .investment || $0.type == .krypto || $0.type == .depot || $0.type == .immobilie }, value: { max(0, $0.balance) })
    }

    var pensionTotal: Double {
        sumVisibleAccounts(where: { $0.type == .altersvorsorge }, value: { max(0, $0.balance) })
    }

    var averageInvestmentGrowthRate: Double {
        let inv = visibleAccounts.filter { $0.type.isInvestment && $0.annualGrowthRate > 0 }
        guard !inv.isEmpty else { return 7.0 }
        let totalBal = inv.reduce(0.0) { $0 + convert(max(0, $1.balance), from: $1.currency, to: displayCurrency) }
        guard totalBal > 0 else { return 7.0 }
        return inv.reduce(0.0) { $0 + ($1.annualGrowthRate * convert(max(0, $1.balance), from: $1.currency, to: displayCurrency)) } / totalBal
    }

    // MARK: - Chart data

    typealias ChartPoint = ProjectionService.ChartPoint

    func historicalChartData(transactions: [ImportedTransaction], profileID: String) -> [ChartPoint] {
        ProjectionService.shared.computeHistoricalData(
            transactions: transactions,
            activeProfileID: profileID,
            currentNetWorth: netWorth
        )
    }

    // MARK: - Daily adjustments (Refactored Logic)

    private func dailyAdjustmentsMap(upToDays days: Int, excludingGoals: Bool = false) -> [Date: Double] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [Date: Double] = [:]

        for entry in budgetEntries where entry.isCurrentlyActive {
            if excludingGoals && entry.linkedGoalID != nil { continue }
            let curr = entry.account?.currency ?? entry.currencyOverride ?? displayCurrency
            let isIncome = entry.userCategory?.isIncome ?? entry.category.isIncomeCategory
            let amt = convert(entry.amount, from: curr, to: displayCurrency)

            if entry.recurrence == .once {
                let isSavingsTransfer = entry.transferToAccount != nil &&
                    (entry.userCategory.map { $0.isSavings || $0.isInvestment } ?? entry.category.isSavingsCategory)
                if isSavingsTransfer { continue }
                guard let due = entry.nextDueDate(after: today) else { continue }
                let dayKey = cal.startOfDay(for: due)
                let offset = cal.dateComponents([.day], from: today, to: dayKey).day ?? 0
                if offset > 0 && offset <= days {
                    result[dayKey, default: 0] += isIncome ? amt : -amt
                }
            } else if isIncome {
                // Handle bonuses for recurring income entries
                let nowYear = cal.component(.year, from: today)
                if entry.bonus13Enabled {
                    let payoutMonths = entry.bonus13Months
                    if !payoutMonths.isEmpty {
                        let payoutAmount = amt / Double(payoutMonths.count)
                        for yearOffset in 0...(days / 365 + 1) {
                            for month in payoutMonths {
                                let comps = DateComponents(year: nowYear + yearOffset, month: month, day: 15)
                                if let d = cal.date(from: comps) {
                                    let dayKey = cal.startOfDay(for: d)
                                    let offset = cal.dateComponents([.day], from: today, to: dayKey).day ?? 0
                                    if offset > 0 && offset <= days { result[dayKey, default: 0] += payoutAmount }
                                }
                            }
                        }
                    }
                }
                if entry.bonusFixedEnabled && entry.bonusFixedAmount > 0 {
                    let payoutAmount = convert(entry.bonusFixedAmount, from: curr, to: displayCurrency)
                    for yearOffset in 0...(days / 365 + 1) {
                        let comps = DateComponents(year: nowYear + yearOffset, month: entry.bonusFixedMonth, day: 15)
                        if let d = cal.date(from: comps) {
                            let dayKey = cal.startOfDay(for: d)
                            let offset = cal.dateComponents([.day], from: today, to: dayKey).day ?? 0
                            if offset > 0 && offset <= days { result[dayKey, default: 0] += payoutAmount }
                        }
                    }
                }
            }
        }
        return result
    }

    private func oneTimeAdjustments(upToMonths months: Int, excludingGoals: Bool = false) -> [Int: Double] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [Int: Double] = [:]
        for (date, amount) in dailyAdjustmentsMap(upToDays: months * 32, excludingGoals: excludingGoals) {
            let comps = cal.dateComponents([.year, .month], from: today, to: date)
            let offset = max(1, (comps.year ?? 0) * 12 + (comps.month ?? 0))
            if offset <= months { result[offset, default: 0] += amount }
        }
        return result
    }

    // MARK: - Projections

    /// Iterates month-by-month so that entries with future startDate/endDate affect the slope correctly.
    private func computeMonthlyProjection(months: Int) -> [UUID: [Int: Double]] {
        guard months > 0 else {
            return Dictionary(uniqueKeysWithValues: visibleAccounts.map { ($0.id, [0: $0.balance]) })
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [UUID: [Int: Double]] = [:]
        for acc in visibleAccounts {
            var bal = acc.balance
            var snap: [Int: Double] = [0: bal]
            for i in 1...months {
                let date = cal.date(byAdding: .month, value: i, to: today) ?? today
                let cf = acc.monthlyCashFlow(at: date)
                if acc.type.isInvestment && acc.annualGrowthRate > 0 {
                    let r = acc.annualGrowthRate / 100.0 / 12.0
                    bal = bal * (1 + r) + cf
                } else {
                    bal += cf
                }
                snap[i] = bal
            }
            result[acc.id] = snap
        }
        return result
    }

    func projectedBalanceDailyData(days: Int) -> [ChartPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let events = dailyAdjustmentsMap(upToDays: days, excludingGoals: excludeGoalEntries)
        var cumEvents = 0.0
        return (0...days).map { i in
            let date = cal.date(byAdding: .day, value: i, to: today) ?? today
            if i > 0 { cumEvents += events[date] ?? 0 }
            let accountBalance = visibleAccounts.reduce(0.0) { sum, acc in
                let proj = convert(acc.projectedBalance(afterDays: i), from: acc.currency, to: displayCurrency)
                return sum + (acc.type.isLiability ? -abs(proj) : proj)
            }
            return ChartPoint(date: date, balance: accountBalance + (i > 0 ? cumEvents : 0), isPast: false)
        }
    }

    func projectedBalanceData(months: Int) -> [ChartPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let oneTime = oneTimeAdjustments(upToMonths: months, excludingGoals: excludeGoalEntries)
        var cumulativeOneTime = 0.0
        let projection = computeMonthlyProjection(months: months)
        return (0...months).map { i in
            let date = cal.date(byAdding: .month, value: i, to: today) ?? today
            if i > 0 { cumulativeOneTime += oneTime[i] ?? 0 }
            let accountBalance = visibleAccounts.reduce(0.0) { sum, acc in
                let bal = projection[acc.id]?[i] ?? acc.balance
                let converted = convert(bal, from: acc.currency, to: displayCurrency)
                return sum + (acc.type.isLiability ? -converted : converted)
            }
            return ChartPoint(date: date, balance: accountBalance + (i > 0 ? cumulativeOneTime : 0), isPast: false)
        }
    }

    struct AccountChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let balance: Double
        let accountName: String
        let accountType: AccountType
        let displayColor: Color
    }

    func stackedFutureData(months: Int) -> [AccountChartPoint] {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())

        let investmentSavingsMonthly: Double = visibleAccounts
            .filter { !$0.type.isLiability && ($0.type == .investment || $0.type == .krypto || $0.type == .depot || $0.type == .altersvorsorge) }
            .reduce(0.0) { sum, acc in
                let s = acc.budgetEntries
                    .filter { $0.isCurrentlyActive && $0.isSavingsEntry && $0.recurrence != .once && $0.transferToAccount == nil }
                    .reduce(0.0) { $0 + convert($1.effectiveMonthlyAmount, from: acc.currency, to: displayCurrency) }
                return sum + s
            }

        func oneTimeMap(for accts: [Account], isLiquidBucket: Bool) -> [Int: Double] {
            let ids = Set(accts.map { ObjectIdentifier($0) })
            var result: [Int: Double] = [:]
            for entry in budgetEntries where entry.isCurrentlyActive {
                let belongsHere = entry.account.map { ids.contains(ObjectIdentifier($0)) } ?? isLiquidBucket
                guard belongsHere else { continue }
                
                let curr = entry.account?.currency ?? entry.currencyOverride ?? displayCurrency
                let amt = convert(entry.amount, from: curr, to: displayCurrency)
                let isIncome = entry.userCategory?.isIncome ?? entry.category.isIncomeCategory

                if entry.recurrence == .once {
                    let isSavingsTransfer = entry.transferToAccount != nil &&
                        (entry.userCategory.map { $0.isSavings || $0.isInvestment } ?? entry.category.isSavingsCategory)
                    if isSavingsTransfer { continue }
                    guard let due = entry.nextDueDate(after: now) else { continue }
                    let mc = calendar.dateComponents([.year, .month], from: now, to: due)
                    let offset = max(1, (mc.year ?? 0) * 12 + (mc.month ?? 0))
                    if offset <= months { result[offset, default: 0] += isIncome ? amt : -amt }
                } else if isIncome && isLiquidBucket {
                    let nowYear = calendar.component(.year, from: now)
                    if entry.bonus13Enabled {
                        let payoutAmount = amt / Double(max(1, entry.bonus13Months.count))
                        for yearOffset in 0...(months / 12 + 1) {
                            for month in entry.bonus13Months {
                                if let d = calendar.date(from: DateComponents(year: nowYear + yearOffset, month: month, day: 15)) {
                                    let mc = calendar.dateComponents([.year, .month], from: now, to: d)
                                    let offset = max(1, (mc.year ?? 0) * 12 + (mc.month ?? 0))
                                    if offset <= months { result[offset, default: 0] += payoutAmount }
                                }
                            }
                        }
                    }
                    if entry.bonusFixedEnabled && entry.bonusFixedAmount > 0 {
                        let payoutAmount = convert(entry.bonusFixedAmount, from: curr, to: displayCurrency)
                        for yearOffset in 0...(months / 12 + 1) {
                            if let d = calendar.date(from: DateComponents(year: nowYear + yearOffset, month: entry.bonusFixedMonth, day: 15)) {
                                let mc = calendar.dateComponents([.year, .month], from: now, to: d)
                                let offset = max(1, (mc.year ?? 0) * 12 + (mc.month ?? 0))
                                if offset <= months { result[offset, default: 0] += payoutAmount }
                            }
                        }
                    }
                }
            }
            return result
        }

        struct Category {
            let name: String
            let color: Color
            let accounts: [Account]
            let monthlyAdjustment: Double
            let oneTimeMap: [Int: Double]
        }

        let liquidAccts  = visibleAccounts.filter { !$0.type.isLiability && ($0.type.isLiquid || $0.type == .festgeld) }
        let investAccts  = visibleAccounts.filter { !$0.type.isLiability && ($0.type == .investment || $0.type == .krypto || $0.type == .depot || $0.type == .immobilie) }
        let pensionAccts = visibleAccounts.filter { !$0.type.isLiability && $0.type == .altersvorsorge }

        let categories: [Category] = [
            Category(name: NSLocalizedString("bucket_liquid", comment: ""), color: AllocationDonutView.liquidColor,
                     accounts: liquidAccts, monthlyAdjustment: -investmentSavingsMonthly,
                     oneTimeMap: oneTimeMap(for: liquidAccts, isLiquidBucket: true)),
            Category(name: NSLocalizedString("bucket_investment", comment: ""), color: AllocationDonutView.investmentColor,
                     accounts: investAccts, monthlyAdjustment: 0,
                     oneTimeMap: oneTimeMap(for: investAccts, isLiquidBucket: false)),
            Category(name: NSLocalizedString("bucket_pension", comment: ""), color: AllocationDonutView.pensionColor,
                     accounts: pensionAccts, monthlyAdjustment: 0,
                     oneTimeMap: oneTimeMap(for: pensionAccts, isLiquidBucket: false)),
        ].filter { !$0.accounts.isEmpty }

        let projection = computeMonthlyProjection(months: months)
        return categories.flatMap { category in
            var cumulativeOneTime = 0.0
            return (0...months).map { i in
                if i > 0 { cumulativeOneTime += category.oneTimeMap[i] ?? 0 }
                let date = calendar.date(byAdding: .month, value: i, to: now) ?? now
                let balance = category.accounts.reduce(0.0) {
                    let bal = projection[$1.id]?[i] ?? $1.balance
                    return $0 + convert(bal, from: $1.currency, to: displayCurrency)
                } + (i > 0 ? category.monthlyAdjustment * Double(i) + cumulativeOneTime : 0)
                return AccountChartPoint(date: date, balance: balance, accountName: category.name,
                                         accountType: category.accounts.first?.type ?? .girokonto, displayColor: category.color)
            }
        }
    }

    struct BalanceSnapshot: Identifiable {
        let id = UUID()
        let date: Date
        let assetTotal: Double
        let netWorth: Double
    }

    func balanceSnapshots(months: Int) -> [BalanceSnapshot] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let oneTime = oneTimeAdjustments(upToMonths: months, excludingGoals: excludeGoalEntries)
        var cumulativeOneTime = 0.0
        let projection = computeMonthlyProjection(months: months)
        return (0...months).map { i in
            if i > 0 { cumulativeOneTime += oneTime[i] ?? 0 }
            let date = cal.date(byAdding: .month, value: i, to: today) ?? today
            let assets = visibleAccounts.filter { !$0.type.isLiability }.reduce(0.0) {
                let bal = projection[$1.id]?[i] ?? $1.balance
                return $0 + convert(bal, from: $1.currency, to: displayCurrency)
            }
            let net = visibleAccounts.reduce(0.0) {
                let bal = projection[$1.id]?[i] ?? $1.balance
                let p = convert(bal, from: $1.currency, to: displayCurrency)
                return $0 + ($1.type.isLiability ? -p : p)
            }
            return BalanceSnapshot(date: date, assetTotal: assets + cumulativeOneTime, netWorth: net + cumulativeOneTime)
        }
    }

    // MARK: - Cash Flow Pieces

    struct PieSlice: Identifiable {
        let id = UUID()
        let accountName: String
        let accountType: AccountType
        let amount: Double
        let displayColor: Color
    }

    func incomePieSlices() -> [PieSlice] {
        visibleAccounts.filter { $0.monthlyIncome > 0 }
            .map { PieSlice(accountName: $0.name, accountType: $0.type, amount: convert($0.monthlyIncome, from: $0.currency, to: displayCurrency), displayColor: $0.effectiveColor) }
            .sorted { $0.amount > $1.amount }
    }

    func expensePieSlices() -> [PieSlice] {
        visibleAccounts.filter { $0.monthlyExpenses > 0 }
            .map { PieSlice(accountName: $0.name, accountType: $0.type, amount: convert($0.monthlyExpenses, from: $0.currency, to: displayCurrency), displayColor: $0.effectiveColor) }
            .sorted { $0.amount > $1.amount }
    }

    func savingsPieSlices() -> [PieSlice] {
        visibleAccounts.filter { $0.monthlySavings > 0 }
            .map { PieSlice(accountName: $0.name, accountType: $0.type, amount: convert($0.monthlySavings, from: $0.currency, to: displayCurrency), displayColor: $0.effectiveColor) }
            .sorted { $0.amount > $1.amount }
    }

    var totalMonthlyInvestContrib: Double {
        sumVisibleAccounts(where: { $0.type.isInvestment }, value: { max(0, $0.monthlyCashFlow) })
    }

    var goalOneTimeAdjustments: [Int: Double] { oneTimeAdjustments(upToMonths: 360) }
    var goalProjectionAdjustments: [Int: Double] { oneTimeAdjustments(upToMonths: 360, excludingGoals: true) }

    var totalMonthlyFixedCosts: Double {
        let fromMonthlyEntries = visibleAccounts.reduce(0.0) { sum, acc in
            let exp = acc.monthlyEntries.filter { !$0.isIncome }.reduce(0.0) { $0 + $1.effectiveMonthlyAmount }
            return sum + convert(exp, from: acc.currency, to: displayCurrency)
        }
        let fromBudgetEntries = budgetEntries.filter { e in
            guard e.isCurrentlyActive, e.recurrence != .once else { return false }
            return !e.isIncomeEntry && !e.isSavingsEntry && e.transferToAccount == nil
        }.reduce(0.0) { sum, e in
            let curr = e.account?.currency ?? e.currencyOverride ?? displayCurrency
            return sum + convert(e.effectiveMonthlyAmount, from: curr, to: displayCurrency)
        }
        return fromMonthlyEntries + fromBudgetEntries
    }

    // MARK: - Provider Breakdown

    struct ProviderBreakdown: Identifiable {
        let id = UUID()
        let provider: String
        let total: Double
        let percentage: Double
        let accounts: [AccountDetail]
    }
    
    struct AccountDetail: Identifiable {
        let id = UUID()
        let name: String
        let convertedBalance: Double
        let currency: String
        let icon: String
        let color: Color
    }

    func providerBreakdown() -> [ProviderBreakdown] {
        let eligible = visibleAccounts.filter { !$0.type.isLiability && !$0.provider.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !eligible.isEmpty else { return [] }
        let total = sumVisibleAccounts(where: { !$0.type.isLiability && !$0.provider.trimmingCharacters(in: .whitespaces).isEmpty }, value: { max(0, $0.balance) })
        guard total > 0 else { return [] }
        
        let grouped = Dictionary(grouping: eligible) { $0.provider.trimmingCharacters(in: .whitespaces) }
        return grouped.compactMap { (provider, accs) -> ProviderBreakdown? in
            let providerTotal = accs.reduce(0.0) { $0 + convert(max(0, $1.balance), from: $1.currency, to: displayCurrency) }
            guard providerTotal > 0 else { return nil }
            let details = accs.map { acc in
                AccountDetail(name: acc.name, convertedBalance: convert(max(0, acc.balance), from: acc.currency, to: displayCurrency),
                              currency: displayCurrency, icon: acc.effectiveSystemImage, color: acc.effectiveColor)
            }.sorted { $0.convertedBalance > $1.convertedBalance }
            return ProviderBreakdown(provider: provider, total: providerTotal, percentage: providerTotal / total * 100, accounts: details)
        }.sorted { $0.total > $1.total }
    }

    func writeWidgetSnapshot() {
        let top = accounts
            .filter { $0.isVisible && !$0.type.isLiability }
            .sorted { $0.balance > $1.balance }
            .prefix(4)
            .map { WidgetSnapshot.AccountSnap(name: $0.name, balance: $0.balance,
                                              currency: $0.currency, typeRaw: $0.typeRaw) }
        let snapshot = WidgetSnapshot(
            netWorth:         netWorth,
            totalAssets:      totalAssets,
            totalLiabilities: totalLiabilities,
            monthlyNetFlow:   monthlyNetCashFlow,
            currency:         displayCurrency,
            updatedAt:        Date(),
            topAccounts:      Array(top)
        )
        WidgetDataBridge.write(snapshot: snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
