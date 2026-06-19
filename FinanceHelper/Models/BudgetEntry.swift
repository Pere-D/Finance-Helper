import Foundation
import SwiftData
import SwiftUI

@Model
final class BudgetEntry {
    var id: UUID = UUID()
    var categoryRaw: String = BudgetCategory.lebensmittel.rawValue
    var amount: Double = 0.0
    var recurrenceRaw: String = BudgetRecurrence.monthly.rawValue
    /// Day of month (1–31) for recurring entries; clamped to the actual last day of the month at runtime.
    var dueDay: Int = 25
    /// Exact date for one-time entries; start reference for recurring
    var dueDate: Date = Date()
    var notes: String = ""
    var isActive: Bool = true
    var createdAt: Date = Date()

    var currencyOverride: String? = nil
    var profileID: String = ""
    var linkedGoalID: String? = nil
    var account: Account?
    var userCategory: UserBudgetCategory?
    var transferToAccount: Account?

    // Optional entry lifetime (recurring entries only)
    var startDate: Date? = nil
    var endDate: Date? = nil

    // Custom recurring months (when set, overrides quarterly/semiannual/yearly logic)
    var dueMonthsRaw: String = ""      // comma-separated months, e.g. "3,6,9,12"

    // Sonderzahlungen (only relevant for income entries)
    var bonus13Enabled: Bool = false
    var bonus13MonthsRaw: String = "12" // comma-separated month numbers, e.g. "6,12"
    var bonusFixedEnabled: Bool = false
    var bonusFixedAmount: Double = 0.0
    var bonusFixedMonth: Int = 6       // calendar month of fixed bonus payout (1–12)

    init(
        category: BudgetCategory = .lebensmittel,
        amount: Double = 0,
        recurrence: BudgetRecurrence = .monthly,
        dueDay: Int = 25,
        dueDate: Date = Date()
    ) {
        self.categoryRaw = category.rawValue
        self.amount = amount
        self.recurrenceRaw = recurrence.rawValue
        self.dueDay = dueDay
        self.dueDate = dueDate
    }

    var category: BudgetCategory {
        get { BudgetCategory(rawValue: categoryRaw) ?? .lebensmittel }
        set { categoryRaw = newValue.rawValue }
    }

    var recurrence: BudgetRecurrence {
        get { BudgetRecurrence(rawValue: recurrenceRaw) ?? .monthly }
        set { recurrenceRaw = newValue.rawValue }
    }

    var dueMonths: [Int] {
        get {
            dueMonthsRaw
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { (1...12).contains($0) }
                .sorted()
        }
        set {
            dueMonthsRaw = newValue.sorted().map(String.init).joined(separator: ",")
        }
    }

    var recurrenceDisplayLabel: String {
        let months = dueMonths
        guard !months.isEmpty else { return recurrence.localizedName }
        switch months.count {
        case 1:     return recurrence == .yearly ? recurrence.localizedName : NSLocalizedString("budget_recurrence_yearly", comment: "")
        case 2:     return NSLocalizedString("budget_recurrence_semiannual", comment: "")
        case 3, 4:  return NSLocalizedString("budget_recurrence_quarterly", comment: "")
        case 12:    return NSLocalizedString("budget_recurrence_monthly", comment: "")
        default:    return "\(months.count)× / Jahr"
        }
    }

    var bonusAnnualTotal: Double {
        (bonus13Enabled ? amount : 0) + (bonusFixedEnabled ? bonusFixedAmount : 0)
    }

    var bonus13Months: [Int] {
        get {
            bonus13MonthsRaw
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { (1...12).contains($0) }
                .sorted()
        }
        set {
            bonus13MonthsRaw = newValue.sorted().map(String.init).joined(separator: ",")
        }
    }

    var effectiveMonthlyAmount: Double {
        let months = dueMonths
        var base: Double
        if !months.isEmpty {
            base = Double(months.count) / 12.0 * amount
        } else {
            base = recurrence.monthlyMultiplier * amount
        }
        base += bonusAnnualTotal / 12.0
        return base
    }

    var isCurrentlyActive: Bool {
        guard isActive else { return false }
        let now = Date()
        if let start = startDate, start > now { return false }
        if let end = endDate, end < now { return false }
        return true
    }

    func isActive(at date: Date) -> Bool {
        guard isActive else { return false }
        if let start = startDate, start > date { return false }
        if let end = endDate, end < date { return false }
        return true
    }

    /// Next occurrence at or after `reference`, respecting optional startDate and endDate.
    func nextDueDate(after reference: Date = Date()) -> Date? {
        // Adjust reference forward to startDate if the entry hasn't started yet
        let reference = startDate.map { Swift.max(reference, $0) } ?? reference
        // Clamp result to endDate
        func bounded(_ date: Date) -> Date? {
            guard let end = endDate else { return date }
            return date <= end ? date : nil
        }

        let cal = Calendar.current

        // Custom month schedule overrides interval-based logic
        let months = dueMonths
        if !months.isEmpty {
            let sortedMonths = months.sorted()
            let refYear = cal.component(.year, from: reference)
            for yearOffset in 0...10 {
                let year = refYear + yearOffset
                for m in sortedMonths {
                    let monthStart = cal.date(from: DateComponents(year: year, month: m)) ?? reference
                    let maxDay = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 28
                    let day = min(dueDay > 0 ? dueDay : 15, maxDay)
                    guard let date = cal.date(from: DateComponents(year: year, month: m, day: day)),
                          date >= reference else { continue }
                    return bounded(date)
                }
            }
            return nil
        }

        switch recurrence {
        case .once:
            return (dueDate >= reference) ? bounded(dueDate) : nil
        case .monthly:
            var comps = cal.dateComponents([.year, .month], from: reference)
            let thisMonthStart = cal.date(from: comps) ?? reference
            let daysInThisMonth = cal.range(of: .day, in: .month, for: thisMonthStart)?.count ?? 28
            comps.day = min(dueDay, daysInThisMonth)
            guard let candidate = cal.date(from: comps) else { return nil }
            if candidate >= reference { return bounded(candidate) }
            guard let nextMonthRef = cal.date(byAdding: .month, value: 1, to: reference) else { return nil }
            var nextComps = cal.dateComponents([.year, .month], from: nextMonthRef)
            let nextMonthStart = cal.date(from: nextComps) ?? nextMonthRef
            let daysInNextMonth = cal.range(of: .day, in: .month, for: nextMonthStart)?.count ?? 28
            nextComps.day = min(dueDay, daysInNextMonth)
            return cal.date(from: nextComps).flatMap(bounded)
        case .quarterly:
            var candidate = dueDate
            for _ in 0..<100 {
                if candidate >= reference { return bounded(candidate) }
                guard let adv = cal.date(byAdding: .month, value: 3, to: candidate) else { break }
                candidate = adv
            }
            return nil
        case .semiannual:
            var candidate = dueDate
            for _ in 0..<50 {
                if candidate >= reference { return bounded(candidate) }
                guard let adv = cal.date(byAdding: .month, value: 6, to: candidate) else { break }
                candidate = adv
            }
            return nil
        case .yearly:
            var candidate = dueDate
            for _ in 0..<50 {
                if candidate >= reference { return bounded(candidate) }
                guard let adv = cal.date(byAdding: .year, value: 1, to: candidate) else { break }
                candidate = adv
            }
            return nil
        }
    }

    var isDueThisMonth: Bool {
        guard isActive else { return false }
        guard let next = nextDueDate() else { return false }
        return Calendar.current.isDate(next, equalTo: Date(), toGranularity: .month)
    }

    func isDue(inMonth monthStart: Date) -> Bool {
        guard isActive else { return false }
        let cal = Calendar.current
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        guard let next = nextDueDate(after: monthStart) else { return false }
        return next < monthEnd
    }

    var displayName: String {
        userCategory?.name ?? category.localizedName
    }

    var displaySymbolName: String {
        userCategory?.symbolName ?? category.systemImage
    }

    var displayColor: Color {
        userCategory?.color ?? category.color
    }

    var isIncomeEntry: Bool {
        guard transferToAccount == nil else { return false }
        return userCategory?.isIncome ?? category.isIncomeCategory
    }

    var isInvestmentEntry: Bool {
        guard transferToAccount == nil, !isIncomeEntry else { return false }
        if let uc = userCategory { return uc.isInvestment }
        if let acc = account { return acc.type.isInvestment }
        return category.isInvestmentCategory
    }

    var isSavingsEntry: Bool {
        guard transferToAccount == nil, !isIncomeEntry else { return false }
        if let uc = userCategory { return uc.isSavings || uc.isInvestment }
        return category.isSavingsCategory
    }
}
