import Foundation
import SwiftUI

// MARK: - CategoryGroup

enum CategoryGroup: String, CaseIterable, Codable {
    case einkommen, schulden, fixkosten, lifestyle, sparen, investieren, intern

    var localizedName: String {
        switch self {
        case .einkommen:   return NSLocalizedString("budget_group_einkommen", comment: "")
        case .schulden:    return NSLocalizedString("budget_group_schulden", comment: "")
        case .fixkosten:   return NSLocalizedString("budget_group_fixkosten", comment: "")
        case .lifestyle:   return NSLocalizedString("budget_group_lifestyle", comment: "")
        case .sparen:      return NSLocalizedString("budget_group_sparen", comment: "")
        case .investieren: return NSLocalizedString("budget_group_investieren", comment: "")
        case .intern:      return "Intern"
        }
    }

    var systemImage: String {
        switch self {
        case .einkommen:   return "banknote.fill"
        case .schulden:    return "arrow.counterclockwise.circle.fill"
        case .fixkosten:   return "house.fill"
        case .lifestyle:   return "heart.fill"
        case .sparen:      return "tray.and.arrow.down.fill"
        case .investieren: return "chart.line.uptrend.xyaxis"
        case .intern:      return "arrow.left.arrow.right.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .einkommen:   return .green
        case .schulden:    return .red
        case .fixkosten:   return .blue
        case .lifestyle:   return Color(red: 0.85, green: 0.3, blue: 0.6)
        case .sparen:      return .teal
        case .investieren: return .purple
        case .intern:      return .gray
        }
    }
}

typealias BudgetCategoryGroup = CategoryGroup

// MARK: - BudgetCategory

enum BudgetCategory: String, Codable, CaseIterable {

    // ── Legacy cases ──
    case salary, bonus
    case healthInsurance, taxes, pillar3a, otherDebt
    case groceries, hairdresser, school, rent, vacation
    case phonePlan, internet, electricity
    case household, homeInsurance, emergencyFund
    case motorcycle, fitness, creditCardShopping, savings

    // ── Gruppe 1: Einkommen ──
    case haupteinkommen, nebeneinkommen, regelmaessigeZufluesse, variableEinnahmen

    // ── Gruppe 2: Schulden & Verpflichtungen ──
    case hypothekZahlung, privatkreditZahlung, leasingZahlung
    case kreditkartenSchuld, rahmenkreditZahlung, ausbildungskreditZahlung
    case amortisation

    // ── Gruppe 3: Fixkosten & Grundbedürfnisse ──
    case miete, nebenkosten, strom, serafe, internetAbo
    case krankenkasse, hausratversicherung, steuernKosten
    case ovAbo, treibstoff, autoversicherung, servicePuffer
    case medizin, lebensmittel, handyAbo, kinderbetreuung
    case ausbildung, haustier
    case hypothekZins

    // ── Gruppe 4: Persönliche Bedürfnisse & Lifestyle ──
    case ausgehen, ausfluege, restaurantEssen, takeaway
    case fitnessAbo, streamingDienste, gamingHobby, cloudDienste
    case buecherMedien, kleidungMode, friseurPflege, dekoWohnen, geschenkeSpenden

    // ── Gruppe 5: Sparen & Rücklagen ──
    case notgroschen, unregelmaessigeKosten, urlaubRuecklage, grosseAnschaffungen

    // ── Gruppe 6: Investieren & Vermögensaufbau ──
    case etfSparplan, kryptoAnlage, saeule3a, saeule2Einkauf

    var group: BudgetCategoryGroup {
        switch self {
        case .salary, .bonus,
             .haupteinkommen, .nebeneinkommen, .regelmaessigeZufluesse, .variableEinnahmen:
            return .einkommen

        case .otherDebt,
             .hypothekZahlung, .privatkreditZahlung, .leasingZahlung,
             .kreditkartenSchuld, .rahmenkreditZahlung, .ausbildungskreditZahlung,
             .amortisation:
            return .schulden

        case .healthInsurance, .taxes, .rent, .phonePlan, .internet, .electricity,
             .household, .homeInsurance, .groceries, .motorcycle, .school,
             .miete, .nebenkosten, .strom, .serafe, .internetAbo,
             .krankenkasse, .hausratversicherung, .steuernKosten,
             .ovAbo, .treibstoff, .autoversicherung, .servicePuffer,
             .medizin, .lebensmittel, .handyAbo, .kinderbetreuung,
             .ausbildung, .haustier, .hypothekZins:
            return .fixkosten

        case .hairdresser, .vacation, .fitness, .creditCardShopping,
             .ausgehen, .ausfluege, .restaurantEssen, .takeaway,
             .fitnessAbo, .streamingDienste, .gamingHobby, .cloudDienste,
             .buecherMedien, .kleidungMode, .friseurPflege, .dekoWohnen, .geschenkeSpenden,
             .urlaubRuecklage, .grosseAnschaffungen:
            return .lifestyle

        case .savings, .emergencyFund,
             .notgroschen, .unregelmaessigeKosten:
            return .sparen

        case .pillar3a, .etfSparplan, .kryptoAnlage, .saeule3a, .saeule2Einkauf:
            return .investieren
        }
    }

    var isIncomeCategory: Bool    { group == .einkommen }
    var isDebtCategory: Bool      { group == .schulden }
    var isSavingsCategory: Bool   { group == .sparen || group == .investieren }
    var isInvestmentCategory: Bool { group == .investieren }

    var isLegacyCategory: Bool {
        switch self {
        case .salary, .bonus, .healthInsurance, .taxes, .pillar3a, .otherDebt,
             .groceries, .hairdresser, .school, .rent, .vacation,
             .phonePlan, .internet, .electricity, .household, .homeInsurance,
             .emergencyFund, .motorcycle, .fitness, .creditCardShopping, .savings:
            return true
        default:
            return false
        }
    }

    var migratedTo: BudgetCategory {
        switch self {
        case .salary:             return .haupteinkommen
        case .bonus:              return .nebeneinkommen
        case .healthInsurance:    return .krankenkasse
        case .taxes:              return .steuernKosten
        case .pillar3a:           return .saeule3a
        case .otherDebt:          return .privatkreditZahlung
        case .groceries:          return .lebensmittel
        case .hairdresser:        return .friseurPflege
        case .school:             return .ausbildung
        case .rent:               return .miete
        case .vacation:           return .urlaubRuecklage
        case .phonePlan:          return .handyAbo
        case .internet:           return .internetAbo
        case .electricity:        return .strom
        case .household:          return .nebenkosten
        case .homeInsurance:      return .hausratversicherung
        case .emergencyFund:      return .notgroschen
        case .motorcycle:         return .servicePuffer
        case .fitness:            return .fitnessAbo
        case .creditCardShopping: return .kreditkartenSchuld
        case .savings:            return .notgroschen
        default:                  return self
        }
    }

    var rollsUpTo: TransactionCategory {
        switch self {
        case .haupteinkommen, .nebeneinkommen, .regelmaessigeZufluesse, .variableEinnahmen,
             .salary, .bonus:
            return .einkommen
        case .hypothekZahlung, .privatkreditZahlung, .leasingZahlung,
             .kreditkartenSchuld, .rahmenkreditZahlung, .ausbildungskreditZahlung,
             .amortisation, .otherDebt:
            return .schulden
        case .miete, .nebenkosten, .rent, .household:
            return .miete
        case .strom, .dekoWohnen, .electricity:
            return .wohnen
        case .hausratversicherung, .homeInsurance:
            return .wohnen
        case .krankenkasse, .autoversicherung, .healthInsurance:
            return .versicherung
        case .medizin:
            return .gesundheit
        case .lebensmittel, .groceries:
            return .lebensmittel
        case .ovAbo:
            return .transport
        case .treibstoff, .servicePuffer, .motorcycle:
            return .tanken
        case .serafe, .internetAbo, .handyAbo, .fitnessAbo, .streamingDienste, .cloudDienste,
             .internet, .phonePlan:
            return .abonnement
        case .steuernKosten, .taxes:
            return .sonstiges
        case .ausbildung, .kinderbetreuung, .school:
            return .bildung
        case .hypothekZins:
            return .wohnen
        case .haustier:
            return .haustier
        case .restaurantEssen, .takeaway, .ausgehen:
            return .restaurant
        case .ausfluege, .gamingHobby, .fitness:
            return .freizeit
        case .kleidungMode, .buecherMedien, .geschenkeSpenden, .friseurPflege,
             .hairdresser, .creditCardShopping:
            return .shopping
        case .vacation:
            return .reisen
        case .notgroschen, .unregelmaessigeKosten, .emergencyFund, .savings:
            return .sparen
        case .urlaubRuecklage:
            return .reisen
        case .grosseAnschaffungen:
            return .shopping
        case .etfSparplan, .kryptoAnlage, .saeule3a, .saeule2Einkauf, .pillar3a:
            return .investieren
        }
    }

    static var incomeCategories:      [BudgetCategory] { allCases.filter(\.isIncomeCategory) }
    static var savingsCategories:     [BudgetCategory] { allCases.filter(\.isSavingsCategory) }
    static var pureSavingsCategories: [BudgetCategory] { allCases.filter { $0.isSavingsCategory && !$0.isInvestmentCategory } }
    static var investmentCategories:  [BudgetCategory] { allCases.filter(\.isInvestmentCategory) }
    static var debtCategories:        [BudgetCategory] { allCases.filter(\.isDebtCategory) }
    static var expenseCategories:     [BudgetCategory] { allCases.filter { !$0.isIncomeCategory && !$0.isSavingsCategory && !$0.isDebtCategory } }

    private static let pickerCategoriesByGroup: [BudgetCategoryGroup: [BudgetCategory]] = {
        var dict: [BudgetCategoryGroup: [BudgetCategory]] = [:]
        for group in BudgetCategoryGroup.allCases {
            dict[group] = allCases.filter { $0.group == group && !$0.isLegacyCategory }
        }
        return dict
    }()

    static func pickerCategories(for group: BudgetCategoryGroup) -> [BudgetCategory] {
        pickerCategoriesByGroup[group] ?? []
    }

    var localizedName: String {
        switch self {
        case .salary:             return NSLocalizedString("budget_category_salary", comment: "")
        case .bonus:              return NSLocalizedString("budget_category_bonus", comment: "")
        case .healthInsurance:    return NSLocalizedString("budget_category_health_insurance", comment: "")
        case .taxes:              return NSLocalizedString("budget_category_taxes", comment: "")
        case .pillar3a:           return NSLocalizedString("budget_category_pillar3a", comment: "")
        case .otherDebt:          return NSLocalizedString("budget_category_other_debt", comment: "")
        case .groceries:          return NSLocalizedString("budget_category_groceries", comment: "")
        case .hairdresser:        return NSLocalizedString("budget_category_hairdresser", comment: "")
        case .school:             return NSLocalizedString("budget_category_school", comment: "")
        case .rent:               return NSLocalizedString("budget_category_rent", comment: "")
        case .vacation:           return NSLocalizedString("budget_category_vacation", comment: "")
        case .phonePlan:          return NSLocalizedString("budget_category_phone", comment: "")
        case .internet:           return NSLocalizedString("budget_category_internet", comment: "")
        case .electricity:        return NSLocalizedString("budget_category_electricity", comment: "")
        case .household:          return NSLocalizedString("budget_category_household", comment: "")
        case .homeInsurance:      return NSLocalizedString("budget_category_home_insurance", comment: "")
        case .emergencyFund:      return NSLocalizedString("budget_category_emergency_fund", comment: "")
        case .motorcycle:         return NSLocalizedString("budget_category_vehicle", comment: "")
        case .fitness:            return NSLocalizedString("budget_category_fitness", comment: "")
        case .creditCardShopping: return NSLocalizedString("budget_category_credit_card", comment: "")
        case .savings:            return NSLocalizedString("budget_category_savings", comment: "")
        case .haupteinkommen:          return NSLocalizedString("budget_cat_haupteinkommen", comment: "")
        case .nebeneinkommen:          return NSLocalizedString("budget_cat_nebeneinkommen", comment: "")
        case .regelmaessigeZufluesse:  return NSLocalizedString("budget_cat_regelmaessige_zufluesse", comment: "")
        case .variableEinnahmen:       return NSLocalizedString("budget_cat_variable_einnahmen", comment: "")
        case .hypothekZahlung:          return NSLocalizedString("budget_cat_hypothek", comment: "")
        case .privatkreditZahlung:      return NSLocalizedString("budget_cat_privatkredit", comment: "")
        case .leasingZahlung:           return NSLocalizedString("budget_cat_leasing", comment: "")
        case .kreditkartenSchuld:       return NSLocalizedString("budget_cat_kreditkarten_schuld", comment: "")
        case .rahmenkreditZahlung:      return NSLocalizedString("budget_cat_rahmenkredit", comment: "")
        case .ausbildungskreditZahlung: return NSLocalizedString("budget_cat_ausbildungskredit", comment: "")
        case .miete:               return NSLocalizedString("budget_cat_miete", comment: "")
        case .nebenkosten:         return NSLocalizedString("budget_cat_nebenkosten", comment: "")
        case .strom:               return NSLocalizedString("budget_cat_strom", comment: "")
        case .serafe:              return NSLocalizedString("budget_cat_serafe", comment: "")
        case .internetAbo:         return NSLocalizedString("budget_cat_internet_abo", comment: "")
        case .krankenkasse:        return NSLocalizedString("budget_cat_krankenkasse", comment: "")
        case .hausratversicherung: return NSLocalizedString("budget_cat_hausratversicherung", comment: "")
        case .steuernKosten:       return NSLocalizedString("budget_cat_steuern", comment: "")
        case .ovAbo:               return NSLocalizedString("budget_cat_ov_abo", comment: "")
        case .treibstoff:          return NSLocalizedString("budget_cat_treibstoff", comment: "")
        case .autoversicherung:    return NSLocalizedString("budget_cat_autoversicherung", comment: "")
        case .servicePuffer:       return NSLocalizedString("budget_cat_service_puffer", comment: "")
        case .medizin:             return NSLocalizedString("budget_cat_medizin", comment: "")
        case .lebensmittel:        return NSLocalizedString("budget_cat_lebensmittel", comment: "")
        case .handyAbo:            return NSLocalizedString("budget_cat_handy", comment: "")
        case .kinderbetreuung:     return NSLocalizedString("budget_cat_kinderbetreuung", comment: "")
        case .ausbildung:          return "Ausbildung"
        case .haustier:            return "Haustier"
        case .hypothekZins:        return "Hypothekarzins"
        case .amortisation:        return "Amortisation"
        case .ausgehen:          return NSLocalizedString("budget_cat_ausgehen", comment: "")
        case .ausfluege:         return NSLocalizedString("budget_cat_ausfluege", comment: "")
        case .restaurantEssen:   return NSLocalizedString("budget_cat_restaurant", comment: "")
        case .takeaway:          return NSLocalizedString("budget_cat_takeaway", comment: "")
        case .fitnessAbo:        return NSLocalizedString("budget_cat_fitness_abo", comment: "")
        case .streamingDienste:  return NSLocalizedString("budget_cat_streaming", comment: "")
        case .gamingHobby:       return NSLocalizedString("budget_cat_gaming", comment: "")
        case .cloudDienste:      return NSLocalizedString("budget_cat_cloud", comment: "")
        case .buecherMedien:     return NSLocalizedString("budget_cat_buecher", comment: "")
        case .kleidungMode:      return NSLocalizedString("budget_cat_kleidung", comment: "")
        case .friseurPflege:     return NSLocalizedString("budget_cat_friseur", comment: "")
        case .dekoWohnen:        return NSLocalizedString("budget_cat_deko", comment: "")
        case .geschenkeSpenden:  return NSLocalizedString("budget_cat_geschenke", comment: "")
        case .notgroschen:           return NSLocalizedString("budget_cat_notgroschen", comment: "")
        case .unregelmaessigeKosten: return NSLocalizedString("budget_cat_unregelmaessige_kosten", comment: "")
        case .urlaubRuecklage:       return NSLocalizedString("budget_cat_urlaub_ruecklage", comment: "")
        case .grosseAnschaffungen:   return NSLocalizedString("budget_cat_grosse_anschaffungen", comment: "")
        case .etfSparplan:   return NSLocalizedString("budget_cat_etf_sparplan", comment: "")
        case .kryptoAnlage:  return NSLocalizedString("budget_cat_krypto_anlage", comment: "")
        case .saeule3a:      return "Säule 3a"
        case .saeule2Einkauf: return "Säule 2 – Einkauf"
        }
    }

    var systemImage: String {
        switch self {
        case .salary:             return "banknote.fill"
        case .bonus:              return "star.fill"
        case .healthInsurance:    return "cross.circle.fill"
        case .taxes:              return "doc.text.fill"
        case .pillar3a:           return "umbrella.fill"
        case .otherDebt:          return "arrow.counterclockwise.circle.fill"
        case .groceries:          return "cart.fill"
        case .hairdresser:        return "scissors"
        case .school:             return "book.fill"
        case .rent:               return "house.fill"
        case .vacation:           return "airplane"
        case .phonePlan:          return "iphone"
        case .internet:           return "wifi"
        case .electricity:        return "bolt.fill"
        case .household:          return "bag.fill"
        case .homeInsurance:      return "shield.fill"
        case .emergencyFund:      return "dollarsign.circle.fill"
        case .motorcycle:         return "car.fill"
        case .fitness:            return "figure.run"
        case .creditCardShopping: return "creditcard.fill"
        case .savings:            return "arrow.up.circle.fill"
        case .haupteinkommen:         return "banknote.fill"
        case .nebeneinkommen:         return "briefcase.fill"
        case .regelmaessigeZufluesse: return "arrow.down.circle.fill"
        case .variableEinnahmen:      return "arrow.down.circle"
        case .hypothekZahlung:          return "house.fill"
        case .privatkreditZahlung:      return "arrow.counterclockwise.circle.fill"
        case .leasingZahlung:           return "car.fill"
        case .kreditkartenSchuld:       return "creditcard.fill"
        case .rahmenkreditZahlung:      return "minus.circle.fill"
        case .ausbildungskreditZahlung: return "graduationcap.fill"
        case .miete:               return "house.fill"
        case .nebenkosten:         return "drop.fill"
        case .strom:               return "bolt.fill"
        case .serafe:              return "tv.fill"
        case .internetAbo:         return "wifi"
        case .krankenkasse:        return "cross.circle.fill"
        case .hausratversicherung: return "shield.fill"
        case .steuernKosten:       return "doc.text.fill"
        case .ovAbo:               return "tram.fill"
        case .treibstoff:          return "fuelpump.fill"
        case .autoversicherung:    return "car.fill"
        case .servicePuffer:       return "wrench.fill"
        case .medizin:             return "pills.fill"
        case .lebensmittel:        return "cart.fill"
        case .handyAbo:            return "iphone"
        case .kinderbetreuung:     return "figure.and.child.holdinghands"
        case .ausbildung:          return "graduationcap.fill"
        case .haustier:            return "pawprint.fill"
        case .hypothekZins:        return "percent"
        case .amortisation:        return "arrow.down.circle.fill"
        case .ausgehen:          return "music.note"
        case .ausfluege:         return "location.fill"
        case .restaurantEssen:   return "fork.knife"
        case .takeaway:          return "bag.fill"
        case .fitnessAbo:        return "figure.run"
        case .streamingDienste:  return "play.rectangle.fill"
        case .gamingHobby:       return "gamecontroller.fill"
        case .cloudDienste:      return "cloud.fill"
        case .buecherMedien:     return "book.fill"
        case .kleidungMode:      return "bag.fill"
        case .friseurPflege:     return "scissors"
        case .dekoWohnen:        return "paintbrush.fill"
        case .geschenkeSpenden:  return "gift.fill"
        case .notgroschen:           return "dollarsign.circle.fill"
        case .unregelmaessigeKosten: return "exclamationmark.circle.fill"
        case .urlaubRuecklage:       return "airplane"
        case .grosseAnschaffungen:   return "tag.fill"
        case .etfSparplan:   return "chart.line.uptrend.xyaxis"
        case .kryptoAnlage:  return "bitcoinsign.circle"
        case .saeule3a:      return "umbrella.fill"
        case .saeule2Einkauf: return "building.columns.fill"
        }
    }

    var color: Color {
        switch self {
        case .salary, .bonus:     return .green
        case .healthInsurance:    return .red
        case .taxes:              return Color(red: 0.65, green: 0.1, blue: 0.1)
        case .pillar3a:           return .purple
        case .otherDebt:          return .orange
        case .groceries:          return Color(red: 0.9, green: 0.5, blue: 0.1)
        case .hairdresser:        return .pink
        case .school:             return .blue
        case .rent:               return .brown
        case .vacation:           return .cyan
        case .phonePlan:          return .indigo
        case .internet:           return Color(red: 0.3, green: 0.5, blue: 0.9)
        case .electricity:        return Color(red: 0.9, green: 0.75, blue: 0.1)
        case .household:          return .teal
        case .homeInsurance:      return Color(red: 0.2, green: 0.6, blue: 0.45)
        case .emergencyFund:      return .mint
        case .motorcycle:         return Color(red: 0.45, green: 0.45, blue: 0.5)
        case .fitness:            return Color(red: 0.9, green: 0.3, blue: 0.55)
        case .creditCardShopping: return Color(red: 0.75, green: 0.2, blue: 0.3)
        case .savings:            return Color(red: 0.1, green: 0.65, blue: 0.55)
        case .haupteinkommen:         return .green
        case .nebeneinkommen:         return Color(red: 0.2, green: 0.7, blue: 0.4)
        case .regelmaessigeZufluesse: return Color(red: 0.15, green: 0.6, blue: 0.3)
        case .variableEinnahmen:      return Color(red: 0.3, green: 0.65, blue: 0.2)
        case .hypothekZahlung:          return .brown
        case .privatkreditZahlung:      return .red
        case .leasingZahlung:           return Color(red: 0.8, green: 0.25, blue: 0.2)
        case .kreditkartenSchuld:       return Color(red: 0.75, green: 0.15, blue: 0.25)
        case .rahmenkreditZahlung:      return Color(red: 0.85, green: 0.35, blue: 0.15)
        case .ausbildungskreditZahlung: return Color(red: 0.65, green: 0.15, blue: 0.35)
        case .miete:               return .brown
        case .nebenkosten:         return .teal
        case .strom:               return Color(red: 0.9, green: 0.75, blue: 0.1)
        case .serafe:              return .indigo
        case .internetAbo:         return Color(red: 0.3, green: 0.5, blue: 0.9)
        case .krankenkasse:        return .red
        case .hausratversicherung: return Color(red: 0.2, green: 0.6, blue: 0.45)
        case .steuernKosten:       return Color(red: 0.65, green: 0.1, blue: 0.1)
        case .ovAbo:               return Color(red: 0.1, green: 0.6, blue: 0.55)
        case .treibstoff:          return Color(red: 0.55, green: 0.45, blue: 0.3)
        case .autoversicherung:    return Color(red: 0.45, green: 0.45, blue: 0.5)
        case .servicePuffer:       return Color(red: 0.6, green: 0.5, blue: 0.4)
        case .medizin:             return Color(red: 0.2, green: 0.7, blue: 0.3)
        case .lebensmittel:        return Color(red: 0.9, green: 0.5, blue: 0.1)
        case .handyAbo:            return .indigo
        case .kinderbetreuung:     return .pink
        case .ausbildung:          return Color(red: 0.25, green: 0.50, blue: 0.90)
        case .haustier:            return .indigo
        case .hypothekZins:        return .brown
        case .amortisation:        return Color(red: 0.55, green: 0.27, blue: 0.07)
        case .ausgehen:          return Color(red: 0.85, green: 0.3, blue: 0.6)
        case .ausfluege:         return .cyan
        case .restaurantEssen:   return Color(red: 0.9, green: 0.45, blue: 0.15)
        case .takeaway:          return Color(red: 0.85, green: 0.35, blue: 0.1)
        case .fitnessAbo:        return Color(red: 0.9, green: 0.3, blue: 0.55)
        case .streamingDienste:  return .purple
        case .gamingHobby:       return Color(red: 0.4, green: 0.3, blue: 0.85)
        case .cloudDienste:      return Color(red: 0.5, green: 0.6, blue: 0.9)
        case .buecherMedien:     return .blue
        case .kleidungMode:      return Color(red: 0.75, green: 0.35, blue: 0.7)
        case .friseurPflege:     return .pink
        case .dekoWohnen:        return Color(red: 0.8, green: 0.6, blue: 0.3)
        case .geschenkeSpenden:  return Color(red: 0.9, green: 0.3, blue: 0.4)
        case .notgroschen:           return .mint
        case .unregelmaessigeKosten: return .orange
        case .urlaubRuecklage:       return .cyan
        case .grosseAnschaffungen:   return .teal
        case .etfSparplan:   return Color(red: 0.2, green: 0.6, blue: 0.4)
        case .kryptoAnlage:  return .orange
        case .saeule3a:      return .purple
        case .saeule2Einkauf: return Color(red: 0.3, green: 0.45, blue: 0.85)
        }
    }
}
