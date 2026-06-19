import Foundation
import SwiftData

enum EntryInterval: String, CaseIterable, Codable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case yearly

    var localizedName: String {
        switch self {
        case .weekly:    return NSLocalizedString("interval_weekly", comment: "")
        case .biweekly:  return NSLocalizedString("interval_biweekly", comment: "")
        case .monthly:   return NSLocalizedString("interval_monthly", comment: "")
        case .quarterly: return NSLocalizedString("interval_quarterly", comment: "")
        case .yearly:    return NSLocalizedString("interval_yearly", comment: "")
        }
    }

    /// Factor by which the entry's amount contributes to monthly cash flow.
    var monthlyMultiplier: Double {
        switch self {
        case .weekly:    return 52.0 / 12.0
        case .biweekly:  return 26.0 / 12.0
        case .monthly:   return 1.0
        case .quarterly: return 1.0 / 3.0
        case .yearly:    return 1.0 / 12.0
        }
    }

    var usesDayOfMonth: Bool {
        self == .monthly || self == .quarterly || self == .yearly
    }
}

@Model
final class MonthlyEntry {
    var id: UUID = UUID()
    var label: String = ""
    var amount: Double = 0.0
    var isIncome: Bool = true
    var intervalRaw: String = EntryInterval.monthly.rawValue
    var dayOfMonth: Int = 1
    /// Shared UUID linking two paired transfer entries (source ↔ destination).
    var transferGroupId: UUID? = nil
    var account: Account?

    init(label: String = "", amount: Double = 0, isIncome: Bool = true) {
        self.label = label
        self.amount = amount
        self.isIncome = isIncome
    }

    var interval: EntryInterval {
        get { EntryInterval(rawValue: intervalRaw) ?? .monthly }
        set { intervalRaw = newValue.rawValue }
    }

    var effectiveMonthlyAmount: Double {
        amount * interval.monthlyMultiplier
    }

    var isTransfer: Bool { transferGroupId != nil }
}
