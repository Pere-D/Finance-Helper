import Foundation
import SwiftData
import SwiftUI

enum AccountBucket: String, Codable, CaseIterable {
    case liquid
    case investment
    case debt

    var localizedName: String {
        switch self {
        case .liquid:     return NSLocalizedString("bucket_liquid_account", comment: "Konto")
        case .investment: return NSLocalizedString("bucket_investment_account", comment: "Investieren / Vorsorge")
        case .debt:       return NSLocalizedString("bucket_debt_account", comment: "Schulden")
        }
    }

    var systemImage: String {
        switch self {
        case .liquid:     return "building.columns"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .debt:       return "creditcard"
        }
    }

    var color: Color {
        switch self {
        case .liquid:     return .blue
        case .investment: return .green
        case .debt:       return .red
        }
    }

    var baseAccountType: AccountType {
        switch self {
        case .liquid:     return .girokonto
        case .investment: return .investment
        case .debt:       return .kredit
        }
    }
}

@Model
final class CustomAccountType {
    var id: UUID = UUID()
    var name: String = ""
    var symbolName: String = "tag.fill"
    var colorNameRaw: String = CategoryColor.blue.rawValue
    var bucketRaw: String = AccountBucket.liquid.rawValue
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Account.customAccountType)
    var accounts: [Account] = []

    init(name: String, symbolName: String = "tag.fill", color: CategoryColor = .blue, bucket: AccountBucket = .liquid) {
        self.name = name
        self.symbolName = symbolName
        self.colorNameRaw = color.rawValue
        self.bucketRaw = bucket.rawValue
    }

    var categoryColor: CategoryColor {
        CategoryColor(rawValue: colorNameRaw) ?? .blue
    }

    var color: Color { categoryColor.color }

    var bucket: AccountBucket {
        AccountBucket(rawValue: bucketRaw) ?? .liquid
    }
}
