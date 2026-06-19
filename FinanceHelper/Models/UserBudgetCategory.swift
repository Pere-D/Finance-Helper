import Foundation
import SwiftData
import SwiftUI

// MARK: - Shared category protocol

/// A unified interface for both built-in and user-defined categories,
/// enabling consistent display across views.
protocol CategoryDisplayable {
    var displayName: String { get }
    var group: CategoryGroup { get }
    var symbolName: String { get }
    var colorHex: String { get }
}

enum CategoryColor: String, Codable, CaseIterable {
    case blue, green, red, orange, purple, pink, teal, indigo, mint, yellow, brown, gray

    var color: Color {
        switch self {
        case .blue:   return .blue
        case .green:  return .green
        case .red:    return .red
        case .orange: return .orange
        case .purple: return .purple
        case .pink:   return .pink
        case .teal:   return .teal
        case .indigo: return .indigo
        case .mint:   return .mint
        case .yellow: return .yellow
        case .brown:  return .brown
        case .gray:   return .gray
        }
    }

    var localizedName: String {
        switch self {
        case .blue:   return "Blau"
        case .green:  return "Grün"
        case .red:    return "Rot"
        case .orange: return "Orange"
        case .purple: return "Lila"
        case .pink:   return "Pink"
        case .teal:   return "Türkis"
        case .indigo: return "Indigo"
        case .mint:   return "Mint"
        case .yellow: return "Gelb"
        case .brown:  return "Braun"
        case .gray:   return "Grau"
        }
    }
}

@Model
final class UserBudgetCategory {
    var id: UUID = UUID()
    var name: String = ""
    var symbolName: String = "tag.fill"
    var colorNameRaw: String = CategoryColor.blue.rawValue
    var isIncome: Bool = false
    var isSavings: Bool = false
    var isInvestment: Bool = false
    /// Stores the CategoryGroup rawValue; used to place the category in the correct picker section.
    var groupRaw: String = ""
    var profileID: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \BudgetEntry.userCategory)
    var budgetEntries: [BudgetEntry] = []

    init(name: String, symbolName: String = "tag.fill", color: CategoryColor = .blue,
         isIncome: Bool = false, isSavings: Bool = false, isInvestment: Bool = false,
         group: CategoryGroup? = nil, profileID: String = "") {
        self.name = name
        self.symbolName = symbolName
        self.colorNameRaw = color.rawValue
        self.isIncome = isIncome
        self.isSavings = isSavings && !isIncome
        self.isInvestment = isInvestment && !isIncome && !isSavings
        if let g = group {
            self.groupRaw = g.rawValue
        } else {
            self.groupRaw = isIncome ? "einkommen" : isInvestment ? "investieren" : isSavings ? "sparen" : "lifestyle"
        }
        self.profileID = profileID
    }

    var categoryColor: CategoryColor {
        get { CategoryColor(rawValue: colorNameRaw) ?? .blue }
        set { colorNameRaw = newValue.rawValue }
    }

    var color: Color { categoryColor.color }

    var group: CategoryGroup { CategoryGroup(rawValue: groupRaw) ?? .lifestyle }

    var colorHex: String {
        switch categoryColor {
        case .blue:   return "#007AFF"
        case .green:  return "#34C759"
        case .red:    return "#FF3B30"
        case .orange: return "#FF9500"
        case .purple: return "#AF52DE"
        case .pink:   return "#FF2D55"
        case .teal:   return "#5AC8FA"
        case .indigo: return "#5856D6"
        case .mint:   return "#00C7BE"
        case .yellow: return "#FFCC00"
        case .brown:  return "#A2845E"
        case .gray:   return "#8E8E93"
        }
    }
}

extension UserBudgetCategory: CategoryDisplayable {
    var displayName: String { name }
}
