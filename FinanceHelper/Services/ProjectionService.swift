import Foundation
import SwiftUI

final class ProjectionService {
    static let shared = ProjectionService()
    
    private init() {}
    
    struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let balance: Double
        let isPast: Bool
    }
    
    /// Cumulative balance from real imported transactions, anchored to today's net worth.
    func computeHistoricalData(
        transactions: [ImportedTransaction],
        activeProfileID: String,
        currentNetWorth: Double
    ) -> [ChartPoint] {
        let calendar = Calendar.current
        let today = Date()
        let todayMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today

        var monthlyNet: [Date: Double] = [:]
        for tx in transactions where tx.profileID == activeProfileID {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date)) ?? tx.date
            guard monthStart < todayMonthStart else { continue }
            monthlyNet[monthStart, default: 0] += tx.rawAmount
        }
        guard !monthlyNet.isEmpty else { return [] }

        let sortedMonths = monthlyNet.keys.sorted()

        // Walk backwards from today's balance to derive each past month's opening balance
        var balanceByMonth: [Date: Double] = [todayMonthStart: currentNetWorth]
        for month in sortedMonths.reversed() {
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: month) else { continue }
            let balanceAtNext = balanceByMonth[nextMonth] ?? currentNetWorth
            balanceByMonth[month] = balanceAtNext - (monthlyNet[month] ?? 0)
        }

        var result = sortedMonths.map { month in
            ChartPoint(date: month, balance: balanceByMonth[month] ?? 0, isPast: true)
        }
        result.append(ChartPoint(date: todayMonthStart, balance: currentNetWorth, isPast: false))
        return result
    }
}
