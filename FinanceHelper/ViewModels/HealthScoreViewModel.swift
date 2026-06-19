import Foundation
import Observation

@Observable
final class HealthScoreViewModel {
    var accounts: [Account] = []

    var settings: HealthScoreSettings?

    private var wEmergency: Double   { settings?.emergencyFundWeight    ?? 25 }
    private var wDebt: Double        { settings?.debtToAssetWeight      ?? 25 }
    private var wInvestment: Double  { settings?.investmentRatioWeight  ?? 25 }
    private var wCredit: Double      { settings?.creditBurdenWeight     ?? 25 }

    var score: Double { calculateScore() }
    var scoreInt: Int { Int(score.rounded()) }

    enum ScoreCategory {
        case excellent, good, fair, poor, critical
    }

    var scoreCategory: ScoreCategory {
        switch score {
        case 80...100: return .excellent
        case 60..<80:  return .good
        case 40..<60:  return .fair
        case 20..<40:  return .poor
        default:       return .critical
        }
    }

    var scoreLabelKey: String {
        switch scoreCategory {
        case .excellent: return "score_excellent"
        case .good:      return "score_good"
        case .fair:      return "score_fair"
        case .poor:      return "score_poor"
        case .critical:  return "score_critical"
        }
    }

    var improvementTips: [String] {
        var tips: [String] = []
        if emergencyFundMonths < 1 {
            tips.append(NSLocalizedString("tip_emergency_low", comment: ""))
        } else if emergencyFundMonths < 3 {
            tips.append(NSLocalizedString("tip_emergency_medium", comment: ""))
        }
        if debtToAssetRatio > 0.40 {
            tips.append(NSLocalizedString("tip_debt_high", comment: ""))
        }
        if investmentRatio < 0.10 {
            tips.append(NSLocalizedString("tip_investment_low", comment: ""))
        }
        if creditBurden > 0.20 {
            tips.append(NSLocalizedString("tip_credit_high", comment: ""))
        }
        if tips.isEmpty {
            tips.append(NSLocalizedString("tip_great", comment: ""))
        }
        return tips
    }

    // MARK: - Computed metrics

    var totalAssets: Double {
        accounts.filter { !$0.type.isLiability }.reduce(0) { $0 + max(0, $1.balance) }
    }

    var totalLiabilities: Double {
        let fromLiabilityAccounts = accounts.filter { $0.type.isLiability }.reduce(0.0) { $0 + max(0, $1.balance) }
        // hypothekBetrag on immobilie accounts counts as liability when no separate Hypothek account is used
        let fromImmobilien = accounts.filter { $0.type == .immobilie }.reduce(0.0) { $0 + max(0, $1.hypothekBetrag) }
        return fromLiabilityAccounts + fromImmobilien
    }

    var totalIncome: Double { accounts.reduce(0) { $0 + $1.monthlyIncome } }
    var totalExpenses: Double { accounts.reduce(0) { $0 + $1.monthlyExpenses } }

    var emergencyFundMonths: Double {
        // Exclude debt repayments — emergency fund should cover living costs, not fixed obligations.
        let debtRepayments = accounts.filter { $0.type.isLiability }.reduce(0) { $0 + $1.monthlyExpenses }
        let livingCosts = max(0, totalExpenses - debtRepayments)
        guard livingCosts > 0 else { return 6 }
        let liquid = accounts.filter { $0.type.isLiquid }.reduce(0) { $0 + max(0, $1.balance) }
        return liquid / livingCosts
    }

    var debtToAssetRatio: Double {
        let total = totalAssets + totalLiabilities
        guard total > 0 else { return 0 }
        return totalLiabilities / total
    }

    var totalMonthlySavings: Double {
        let directSavings = accounts.reduce(0) { $0 + $1.monthlySavings }
        let transferSavings = accounts
            .filter { $0.type.isInvestment || $0.type == .sparkonto || $0.type == .tagesgeld || $0.type == .festgeld }
            .flatMap { $0.incomingBudgetTransfers }
            .filter(\.isActive)
            .reduce(0) { $0 + $1.effectiveMonthlyAmount }
        return directSavings + transferSavings
    }

    var investmentRatio: Double {
        guard totalIncome > 0 else { return 0 }
        let savingRate = totalMonthlySavings / totalIncome
        // Wealth-based score: avoids penalising retirees/late-career who accumulate assets instead of active savings
        let investmentWealth = accounts
            .filter { $0.type.isInvestment || $0.type == .immobilie }
            .reduce(0.0) { $0 + max(0, $1.balance) }
        let wealthScore = investmentWealth / (totalIncome * 120)  // 10 years of income = 100 %
        return max(savingRate, wealthScore)
    }

    var creditBurden: Double {
        guard totalIncome > 0 else { return 0 }
        let creditExp = accounts.filter { $0.type.isLiability }.reduce(0) { $0 + $1.monthlyExpenses }
        return creditExp / totalIncome
    }

    // MARK: - Criterion scores (0–100)

    var emergencyFundScore: Double  { min(100, emergencyFundMonths / 3.0 * 100) }
    var debtToAssetScore: Double    { max(0, (1.0 - debtToAssetRatio) * 100) }
    var investmentRatioScore: Double { min(100, investmentRatio / 0.20 * 100) }
    var creditBurdenScore: Double   { max(0, (1.0 - creditBurden / 0.30) * 100) }

    // MARK: - Weighted score

    private func calculateScore() -> Double {
        var total = 0.0
        var totalWeight = 0.0
        if settings?.emergencyFundEnabled    ?? true { total += wEmergency  * emergencyFundScore;   totalWeight += wEmergency }
        if settings?.debtToAssetEnabled      ?? true { total += wDebt       * debtToAssetScore;     totalWeight += wDebt }
        if settings?.investmentRatioEnabled  ?? true { total += wInvestment * investmentRatioScore; totalWeight += wInvestment }
        if settings?.creditBurdenEnabled     ?? true { total += wCredit     * creditBurdenScore;    totalWeight += wCredit }
        guard totalWeight > 0 else { return 0 }
        return total / totalWeight
    }

    // MARK: - Criteria list for display

    struct CriterionInfo {
        let nameKey: String
        let descriptionKey: String
        let score: Double
        let weight: Int
    }

    var criteriaInfo: [CriterionInfo] {
        var result: [CriterionInfo] = []
        if settings?.emergencyFundEnabled    ?? true { result.append(CriterionInfo(nameKey: "criterion_emergency_fund",   descriptionKey: "criterion_emergency_desc",   score: emergencyFundScore,   weight: Int(wEmergency))) }
        if settings?.debtToAssetEnabled      ?? true { result.append(CriterionInfo(nameKey: "criterion_debt_ratio",      descriptionKey: "criterion_debt_desc",        score: debtToAssetScore,     weight: Int(wDebt))) }
        if settings?.investmentRatioEnabled  ?? true { result.append(CriterionInfo(nameKey: "criterion_investment_ratio",descriptionKey: "criterion_investment_desc",   score: investmentRatioScore, weight: Int(wInvestment))) }
        if settings?.creditBurdenEnabled     ?? true { result.append(CriterionInfo(nameKey: "criterion_credit_burden",   descriptionKey: "criterion_credit_desc",      score: creditBurdenScore,    weight: Int(wCredit))) }
        return result
    }
}
