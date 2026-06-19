import Foundation

enum BudgetRecurrence: String, Codable, CaseIterable {
    case once, monthly, quarterly, semiannual, yearly

    var localizedName: String {
        switch self {
        case .once:       return NSLocalizedString("budget_recurrence_once", comment: "")
        case .monthly:    return NSLocalizedString("budget_recurrence_monthly", comment: "")
        case .quarterly:  return NSLocalizedString("budget_recurrence_quarterly", comment: "")
        case .semiannual: return NSLocalizedString("budget_recurrence_semiannual", comment: "")
        case .yearly:     return NSLocalizedString("budget_recurrence_yearly", comment: "")
        }
    }

    /// Factor to convert this entry's amount to a monthly equivalent (0 for one-time)
    var monthlyMultiplier: Double {
        switch self {
        case .once:       return 0
        case .monthly:    return 1.0
        case .quarterly:  return 1.0 / 3.0
        case .semiannual: return 1.0 / 6.0
        case .yearly:     return 1.0 / 12.0
        }
    }
}
