import Foundation
import SwiftData

enum AccountType: String, CaseIterable, Codable {
    case girokonto
    case sparkonto
    case kreditkarte
    case kredit
    case hypothek
    case investment
    case krypto
    case bargeld
    case tagesgeld
    case festgeld
    case altersvorsorge
    case autokredit
    case depot            // brokerage / securities depot
    case geschaeftskonto  // business checking account
    case immobilie        // real estate asset

    var localizedName: String {
        switch self {
        case .girokonto:       return NSLocalizedString("account_type_girokonto", comment: "")
        case .sparkonto:       return NSLocalizedString("account_type_sparkonto", comment: "")
        case .kreditkarte:     return NSLocalizedString("account_type_kreditkarte", comment: "")
        case .kredit:          return NSLocalizedString("account_type_kredit", comment: "")
        case .hypothek:        return NSLocalizedString("account_type_hypothek", comment: "")
        case .investment:      return NSLocalizedString("account_type_investment", comment: "")
        case .krypto:          return NSLocalizedString("account_type_krypto", comment: "")
        case .bargeld:         return NSLocalizedString("account_type_bargeld", comment: "")
        case .tagesgeld:       return NSLocalizedString("account_type_tagesgeld", comment: "")
        case .festgeld:        return NSLocalizedString("account_type_festgeld", comment: "")
        case .altersvorsorge:  return NSLocalizedString("account_type_altersvorsorge", comment: "")
        case .autokredit:      return NSLocalizedString("account_type_autokredit", comment: "")
        case .depot:           return NSLocalizedString("account_type_depot", comment: "")
        case .geschaeftskonto: return NSLocalizedString("account_type_geschaeftskonto", comment: "")
        case .immobilie:       return NSLocalizedString("account_type_immobilie", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .girokonto:      return "building.columns"
        case .sparkonto:      return "dollarsign.circle"
        case .kreditkarte:    return "creditcard"
        case .kredit:         return "arrow.counterclockwise.circle"
        case .hypothek:       return "house"
        case .investment:     return "chart.line.uptrend.xyaxis"
        case .krypto:         return "bitcoinsign.circle"
        case .bargeld:        return "banknote"
        case .tagesgeld:      return "percent"
        case .festgeld:       return "lock.fill"
        case .altersvorsorge: return "umbrella.fill"
        case .autokredit:     return "car.fill"
        case .depot:          return "briefcase.fill"
        case .geschaeftskonto: return "building.2.fill"
        case .immobilie:       return "house.fill"
        }
    }

    var typeColor: Color {
        switch self {
        case .girokonto:      return .blue
        case .sparkonto:      return .teal
        case .kreditkarte:    return .red
        case .kredit:         return Color(red: 0.85, green: 0.2, blue: 0.3)
        case .hypothek:       return .brown
        case .investment:     return .green
        case .krypto:         return .orange
        case .bargeld:        return .indigo
        case .tagesgeld:      return .cyan
        case .festgeld:       return .mint
        case .altersvorsorge: return .purple
        case .autokredit:     return Color(red: 0.55, green: 0.27, blue: 0.07)
        case .depot:          return Color(red: 0.2, green: 0.6, blue: 0.4)
        case .geschaeftskonto: return Color(red: 0.3, green: 0.4, blue: 0.8)
        case .immobilie:       return Color(red: 0.76, green: 0.40, blue: 0.22)
        }
    }

    var isLiability: Bool  { self == .kreditkarte || self == .kredit || self == .hypothek || self == .autokredit }
    var isInvestment: Bool { self == .investment || self == .krypto || self == .altersvorsorge || self == .depot }
    var isLiquid: Bool     { self == .girokonto || self == .sparkonto || self == .bargeld || self == .tagesgeld || self == .geschaeftskonto }
}

// Allow AccountType to be used in SwiftUI without importing SwiftUI in the model layer
import SwiftUI

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = AccountType.girokonto.rawValue
    var balance: Double = 0.0
    var currency: String = "EUR"
    var provider: String = ""
    var isVisible: Bool = true
    var createdAt: Date = Date()
    /// Annual growth rate in percent (e.g. 7.0 = 7 %). Applied for investment and immobilie accounts.
    var annualGrowthRate: Double = 0.0
    /// Original purchase price (immobilie only). 0 = not set.
    var kaufpreis: Double = 0.0
    /// Purchase date (immobilie only).
    var kaufdatum: Date? = nil
    /// Outstanding mortgage on this property (immobilie only). 0 = not set or no mortgage.
    var hypothekBetrag: Double = 0.0
    /// Annual mortgage interest rate in percent (immobilie only, e.g. 2.5 = 2.5 %). 0 = not set.
    var hypothekZinssatz: Double = 0.0
    /// UUID string of a linked Altersvorsorge/3a account for indirect amortisation tracking (immobilie only).
    var linked3aAccountID: String = ""
    var customAccountType: CustomAccountType?
    var profileID: String = ""

    @Relationship(deleteRule: .cascade, inverse: \MonthlyEntry.account)
    var monthlyEntries: [MonthlyEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \BudgetEntry.account)
    var budgetEntries: [BudgetEntry] = []

    @Relationship(deleteRule: .nullify, inverse: \BudgetEntry.transferToAccount)
    var incomingBudgetTransfers: [BudgetEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \ImportedTransaction.account)
    var importedTransactions: [ImportedTransaction] = []

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .girokonto }
        set { typeRaw = newValue.rawValue }
    }

    var effectiveDisplayName: String { customAccountType?.name ?? type.localizedName }
    var effectiveSystemImage: String { customAccountType?.symbolName ?? type.systemImage }
    var effectiveColor: Color { customAccountType?.color ?? type.typeColor }

    /// Monthly interest cost based on hypothekBetrag × hypothekZinssatz (immobilie only).
    var monatlicheHypothekZinsen: Double {
        guard type == .immobilie, hypothekBetrag > 0, hypothekZinssatz > 0 else { return 0 }
        return hypothekBetrag * hypothekZinssatz / 100.0 / 12.0
    }

    init(name: String = "", type: AccountType = .girokonto, balance: Double = 0, currency: String = "EUR") {
        self.name = name
        self.typeRaw = type.rawValue
        self.balance = balance
        self.currency = currency
    }

    var monthlySavings: Double {
        budgetEntries.filter { $0.isCurrentlyActive && $0.isSavingsEntry }
            .reduce(0) { $0 + $1.effectiveMonthlyAmount }
    }

    /// Monthly recurring transfers arriving INTO this account from other accounts.
    var monthlyIncomingTransfers: Double {
        incomingBudgetTransfers
            .filter(\.isCurrentlyActive)
            .reduce(0) { $0 + $1.effectiveMonthlyAmount }
    }

    /// Monthly recurring transfers leaving FROM this account to other accounts.
    var monthlyOutgoingTransfers: Double {
        budgetEntries
            .filter { $0.isCurrentlyActive && $0.transferToAccount != nil }
            .reduce(0) { $0 + $1.effectiveMonthlyAmount }
    }

    var monthlyIncome: Double {
        let fromEntries = monthlyEntries.filter(\.isIncome).reduce(0) { $0 + $1.effectiveMonthlyAmount }
        let fromBudget  = budgetEntries.filter { $0.isCurrentlyActive && $0.isIncomeEntry && $0.transferToAccount == nil }
            .reduce(0) { $0 + $1.effectiveMonthlyAmount }
        return fromEntries + fromBudget
    }

    var monthlyExpenses: Double {
        let fromEntries = monthlyEntries.filter { !$0.isIncome }.reduce(0) { $0 + $1.effectiveMonthlyAmount }
        let fromBudget  = budgetEntries.filter { e in
            guard e.isCurrentlyActive, e.transferToAccount == nil else { return false }
            return !e.isIncomeEntry && !e.isSavingsEntry
        }.reduce(0) { $0 + $1.effectiveMonthlyAmount }
        return fromEntries + fromBudget
    }

    var monthlyCashFlow: Double {
        if type.isInvestment || type == .sparkonto || type == .tagesgeld || type == .festgeld {
            // For savings/investment accounts: budget entries represent DEPOSITS into this account
            return monthlyIncome + monthlySavings + monthlyIncomingTransfers - monthlyExpenses
        } else if type.isLiability {
            // For liabilities: incoming transfers are debt repayments and reduce the balance faster
            return monthlyIncome - monthlyExpenses - monthlyIncomingTransfers
        } else {
            // For liquid/other accounts: savings entries and transfers leave this account
            return monthlyIncome - monthlyExpenses - monthlySavings - monthlyOutgoingTransfers
        }
    }

    /// Cashflow computed at a specific future date, respecting startDate/endDate on budget entries.
    func monthlyCashFlow(at date: Date) -> Double {
        let savings = budgetEntries
            .filter { $0.isActive(at: date) && $0.isSavingsEntry }
            .reduce(0) { $0 + $1.effectiveMonthlyAmount }
        let incomingTransfers = incomingBudgetTransfers
            .filter { $0.isActive(at: date) }
            .reduce(0) { $0 + $1.effectiveMonthlyAmount }
        let outgoingTransfers = budgetEntries
            .filter { $0.isActive(at: date) && $0.transferToAccount != nil }
            .reduce(0) { $0 + $1.effectiveMonthlyAmount }
        let income = monthlyEntries.filter(\.isIncome).reduce(0) { $0 + $1.effectiveMonthlyAmount }
            + budgetEntries.filter { $0.isActive(at: date) && $0.isIncomeEntry && $0.transferToAccount == nil }
                .reduce(0) { $0 + $1.effectiveMonthlyAmount }
        let expenses = monthlyEntries.filter { !$0.isIncome }.reduce(0) { $0 + $1.effectiveMonthlyAmount }
            + budgetEntries.filter { e in
                guard e.isActive(at: date), e.transferToAccount == nil else { return false }
                return !e.isIncomeEntry && !e.isSavingsEntry
            }.reduce(0) { $0 + $1.effectiveMonthlyAmount }
        if type.isInvestment || type == .sparkonto || type == .tagesgeld || type == .festgeld {
            return income + savings + incomingTransfers - expenses
        } else if type.isLiability {
            return income - expenses - incomingTransfers
        } else {
            return income - expenses - savings - outgoingTransfers
        }
    }

    /// Estimated months until debt is paid off (liabilities only).
    var estimatedPayoffMonths: Int? {
        guard type.isLiability, balance > 0 else { return nil }
        let totalMonthlyRepayment = monthlyExpenses + monthlyIncomingTransfers
        guard totalMonthlyRepayment > 0 else { return nil }
        return Int(ceil(balance / totalMonthlyRepayment))
    }

    private var usesCompoundGrowth: Bool { (type.isInvestment || type == .immobilie) && annualGrowthRate > 0 }

    func projectedBalance(afterMonths months: Int) -> Double {
        guard usesCompoundGrowth && months > 0 else {
            return balance + monthlyCashFlow * Double(months)
        }
        let r = annualGrowthRate / 100.0 / 12.0
        let n = Double(months)
        let fvBalance = balance * pow(1 + r, n)
        let fvCashFlow = monthlyCashFlow * (pow(1 + r, n) - 1) / r
        return fvBalance + fvCashFlow
    }

    /// Daily-granular projection. Uses 365.2425/12 days-per-month for the cash-flow spread.
    func projectedBalance(afterDays days: Int) -> Double {
        let daysPerMonth = 365.2425 / 12.0
        let dailyFlow = monthlyCashFlow / daysPerMonth
        guard usesCompoundGrowth && days > 0 else {
            return balance + dailyFlow * Double(days)
        }
        let r = pow(1.0 + annualGrowthRate / 100.0, 1.0 / 365.2425) - 1.0
        let n = Double(days)
        let fvBalance = balance * pow(1 + r, n)
        let fvCashFlow = dailyFlow * (pow(1 + r, n) - 1) / r
        return fvBalance + fvCashFlow
    }
}
