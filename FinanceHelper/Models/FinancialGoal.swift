import Foundation
import SwiftData
import SwiftUI

// MARK: - Goal Category

enum GoalCategory: String, CaseIterable, Identifiable {
    case traumreise, trips, tech, hobby, fahrzeug, wohnen, haustier, genuss, lebensereign, weiterbildung, startkapital, custom

    var id: String { rawValue }

    var localizedName: String { NSLocalizedString("goal_cat_\(rawValue)_name", comment: "") }

    var fullDescription: String { NSLocalizedString("goal_cat_\(rawValue)_desc", comment: "") }

    var systemImage: String {
        switch self {
        case .traumreise:    return "airplane"
        case .trips:         return "ticket.fill"
        case .tech:          return "laptopcomputer"
        case .hobby:         return "camera.fill"
        case .fahrzeug:      return "car.fill"
        case .wohnen:        return "house.fill"
        case .haustier:      return "pawprint.fill"
        case .genuss:        return "cup.and.saucer.fill"
        case .lebensereign:  return "heart.fill"
        case .weiterbildung: return "graduationcap.fill"
        case .startkapital:  return "flame.fill"
        case .custom:        return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .traumreise:    return .blue
        case .trips:         return .orange
        case .tech:          return .cyan
        case .hobby:         return .purple
        case .fahrzeug:      return Color(red: 0.80, green: 0.18, blue: 0.18)
        case .wohnen:        return Color(red: 0.60, green: 0.38, blue: 0.18)
        case .haustier:      return Color(red: 0.95, green: 0.40, blue: 0.55)
        case .genuss:        return Color(red: 0.55, green: 0.32, blue: 0.12)
        case .lebensereign:  return .pink
        case .weiterbildung: return .green
        case .startkapital:  return Color(red: 0.95, green: 0.50, blue: 0.10)
        case .custom:        return .teal
        }
    }

    var suggestedAmounts: [Double] {
        switch self {
        case .traumreise:    return [2_000, 5_000, 10_000, 20_000]
        case .trips:         return [500, 1_000, 2_500, 5_000]
        case .tech:          return [500, 1_500, 3_000, 5_000]
        case .hobby:         return [500, 1_500, 3_500, 8_000]
        case .fahrzeug:      return [5_000, 15_000, 30_000, 60_000]
        case .wohnen:        return [1_000, 3_000, 8_000, 20_000]
        case .haustier:      return [500, 1_500, 3_000, 5_000]
        case .genuss:        return [200, 500, 1_500, 3_000]
        case .lebensereign:  return [3_000, 10_000, 20_000, 50_000]
        case .weiterbildung: return [500, 2_000, 5_000, 15_000]
        case .startkapital:  return [5_000, 15_000, 30_000, 100_000]
        case .custom:        return [1_000, 5_000, 10_000, 25_000]
        }
    }
}

// MARK: - Model

@Model
final class FinancialGoal {
    var id: UUID = UUID()
    var profileID: String = ""
    var name: String = ""
    var categoryRaw: String = GoalCategory.custom.rawValue
    var targetAmount: Double = 0
    var currency: String = "EUR"
    var createdAt: Date = Date()
    var priority: Int = 0
    var isActive: Bool = true

    init(profileID: String = "", name: String = "", category: GoalCategory = .custom,
         targetAmount: Double = 0, currency: String = "EUR") {
        self.profileID = profileID
        self.name = name
        self.categoryRaw = category.rawValue
        self.targetAmount = targetAmount
        self.currency = currency
    }

    var category: GoalCategory { GoalCategory(rawValue: categoryRaw) ?? .custom }
}
