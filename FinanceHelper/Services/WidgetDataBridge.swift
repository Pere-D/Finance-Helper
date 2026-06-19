import Foundation

// MARK: - Shared widget snapshot
// Add this file to BOTH the main app target AND the FinanceHelperWidget target in Xcode.

struct WidgetSnapshot: Codable {
    var netWorth: Double = 0
    var totalAssets: Double = 0
    var totalLiabilities: Double = 0
    var monthlyNetFlow: Double = 0
    var currency: String = "EUR"
    var updatedAt: Date = Date()
    var topAccounts: [AccountSnap] = []

    struct AccountSnap: Codable {
        var name: String
        var balance: Double
        var currency: String
        var typeRaw: String
    }

    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            netWorth: 24_500,
            totalAssets: 28_000,
            totalLiabilities: 3_500,
            monthlyNetFlow: 650,
            currency: "EUR",
            updatedAt: Date(),
            topAccounts: [
                AccountSnap(name: "Girokonto",  balance: 3_200, currency: "EUR", typeRaw: "girokonto"),
                AccountSnap(name: "Depot",      balance: 18_000, currency: "EUR", typeRaw: "depot"),
                AccountSnap(name: "Tagesgeld",  balance: 6_800, currency: "EUR", typeRaw: "tagesgeld"),
            ]
        )
    }
}

// MARK: - Bridge (reads/writes via App Group UserDefaults)

enum WidgetDataBridge {
    private static let appGroupID  = "group.com.dxlic.FinanceHelper"
    private static let snapshotKey = "widget_snapshot_v1"

    static func write(snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func read() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
