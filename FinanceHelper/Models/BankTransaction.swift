import SwiftUI

// MARK: - Bank Transaction

struct BankTransaction: Identifiable {
    let id = UUID()
    let date: Date
    let description: String
    let rawAmount: Double        // negative = expense, positive = income
    let valueDate: Date
    var category: TransactionCategory
    var merchantName: String     // cleaned from description
    var currencyCode: String = "CHF"

    var isExpense: Bool { rawAmount < 0 }
    var isIncome:  Bool { rawAmount > 0 }
    var amount:    Double { Swift.abs(rawAmount) }
}

// MARK: - Category

enum TransactionCategory: String, CaseIterable, Identifiable {
    case einkommen    = "Einkommen"
    case lebensmittel = "Lebensmittel"
    case restaurant   = "Restaurant, Café & Bar"
    case transport    = "Transport"
    case tanken       = "Tanken"
    case auto         = "Auto & Fahrzeug"
    case abonnement   = "Abonnements"
    case shopping     = "Shopping"
    case freizeit     = "Freizeit & Sport"
    case gesundheit   = "Gesundheit"
    case haustier     = "Haustier"
    case versicherung = "Versicherung"
    case wohnen       = "Wohnen"
    case bildung      = "Bildung"
    case reisen       = "Reisen"
    case schulden     = "Schulden"
    case bank         = "Bank & Finanzen"
    case transfer     = "Transfer"
    case dauerauftrag = "Dauerauftrag"
    case miete        = "Miete"
    case steuern      = "Steuern & staatliche Abgaben"
    case investieren  = "Investieren"
    case sparen       = "Sparen"
    case sonstiges    = "Unkategorisiert"

    var id: String { rawValue }
    var localizedName: String { NSLocalizedString(rawValue, comment: "") }

    var group: CategoryGroup {
        switch self {
        case .einkommen:                        return .einkommen
        case .schulden:                         return .schulden
        case .lebensmittel, .transport, .tanken, .auto,
             .abonnement, .gesundheit, .haustier,
             .versicherung, .wohnen, .bildung, .miete,
             .steuern:                                  return .fixkosten
        case .restaurant, .shopping, .freizeit,
             .reisen:                           return .lifestyle
        case .sparen:                           return .sparen
        case .investieren:                      return .investieren
        case .bank, .transfer, .dauerauftrag,
             .sonstiges:                        return .intern
        }
    }

    /// Internal categories are excluded from expense analysis (transfers, bank fees, uncategorised).
    var isInternal: Bool { group == .intern }

    var systemImage: String {
        switch self {
        case .einkommen:    return "banknote.fill"
        case .lebensmittel: return "cart.fill"
        case .restaurant:   return "fork.knife"
        case .transport:    return "tram.fill"
        case .tanken:       return "fuelpump.fill"
        case .auto:         return "car.fill"
        case .abonnement:   return "play.rectangle.fill"
        case .shopping:     return "bag.fill"
        case .freizeit:     return "figure.run"
        case .gesundheit:   return "pills.fill"
        case .haustier:     return "pawprint.fill"
        case .versicherung: return "shield.fill"
        case .wohnen:       return "drop.fill"
        case .bildung:      return "graduationcap.fill"
        case .reisen:       return "airplane"
        case .schulden:     return "arrow.counterclockwise.circle.fill"
        case .bank, .transfer, .dauerauftrag, .sonstiges:
            return "wrench.fill"
        case .miete:        return "house.fill"
        case .steuern:      return "doc.text.fill"
        case .investieren:  return "chart.line.uptrend.xyaxis"
        case .sparen:       return "dollarsign.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .einkommen:    return .green
        case .lebensmittel: return .orange
        case .restaurant:   return .red
        case .transport:    return .blue
        case .tanken:       return .brown
        case .auto:         return Color(red: 0.45, green: 0.45, blue: 0.55)
        case .abonnement:   return .purple
        case .shopping:     return .pink
        case .freizeit:     return .teal
        case .gesundheit:   return .mint
        case .haustier:     return .indigo
        case .versicherung: return .yellow
        case .wohnen:       return Color(red: 0.55, green: 0.35, blue: 0.15)
        case .bildung:      return Color(red: 0.25, green: 0.50, blue: 0.90)
        case .reisen:       return Color(red: 0.80, green: 0.30, blue: 0.60)
        case .schulden:     return Color(red: 0.80, green: 0.20, blue: 0.20)
        case .bank:         return Color(red: 0.10, green: 0.60, blue: 0.40)
        case .transfer:     return .gray
        case .dauerauftrag: return .cyan
        case .miete:        return .orange
        case .steuern:      return Color(red: 0.35, green: 0.42, blue: 0.55)
        case .investieren:  return Color(red: 0.10, green: 0.65, blue: 0.40)
        case .sparen:       return Color(red: 0.10, green: 0.50, blue: 0.85)
        case .sonstiges:    return Color.secondary
        }
    }

    var isExpenseCategory: Bool { !isInternal && self != .einkommen }

    /// Maps a transaction category to a sensible default budget category for
    /// auto-creating budget entries from the analyse view's suggestion.
    var suggestedBudgetCategory: BudgetCategory {
        switch self {
        case .einkommen:    return .haupteinkommen
        case .lebensmittel: return .lebensmittel
        case .restaurant:   return .restaurantEssen
        case .transport:    return .ovAbo
        case .tanken:       return .treibstoff
        case .auto:         return .autoversicherung
        case .abonnement:   return .streamingDienste
        case .shopping:     return .kleidungMode
        case .freizeit:     return .fitnessAbo
        case .gesundheit:   return .medizin
        case .haustier:     return .haustier
        case .versicherung: return .hausratversicherung
        case .wohnen:       return .nebenkosten
        case .bildung:      return .ausbildung
        case .reisen:       return .urlaubRuecklage
        case .schulden:     return .privatkreditZahlung
        case .miete:        return .miete
        case .steuern:      return .steuernKosten
        case .investieren:  return .etfSparplan
        case .sparen:       return .notgroschen
        case .bank, .transfer, .dauerauftrag, .sonstiges:
            return .servicePuffer
        }
    }
}

// MARK: - Supported Bank Formats

enum BankFormat: String, CaseIterable, Identifiable {
    case zugerKantonalbank    = "Zuger Kantonalbank"
    case zuercherKantonalbank = "Zürcher Kantonalbank"
    case yuh                  = "Yuh"
    case swisscard            = "SwissCard"
    case ubs                  = "UBS"

    var id: String { rawValue }

    var logoSymbol: String {
        switch self {
        case .zugerKantonalbank:    return "building.columns.fill"
        case .zuercherKantonalbank: return "building.columns.fill"
        case .yuh:                  return "creditcard.fill"
        case .swisscard:            return "creditcard.fill"
        case .ubs:                  return "building.columns.fill"
        }
    }

    var hint: String {
        switch self {
        case .zugerKantonalbank:
            return "Kontoauszug exportieren → CSV (Semikolon-getrennt) oder PDF (Einzeltransaktionen)"
        case .zuercherKantonalbank:
            return "E-Banking → Kontoauszug → Export als CSV"
        case .yuh:
            return "Aktivitäten exportieren → CSV"
        case .swisscard:
            return "Aktivitäten exportieren → CSV oder Excel (XLSX)"
        case .ubs:
            return "E-Banking → Kontoauszug → Export als CSV (Semikolon-getrennt)"
        }
    }
}
