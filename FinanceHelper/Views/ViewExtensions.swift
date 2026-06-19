import SwiftUI
import UIKit

// MARK: - Known Banks

struct KnownBank: Identifiable, Hashable {
    let id: String          // asset name, e.g. "bank_ubs"
    let name: String        // full display name
    let shortLabel: String  // abbreviated label shown when no logo is loaded
    let brandColor: Color
    let importFormat: BankFormat?   // nil = not yet importable
    let isApproved: Bool            // logo usage confirmed — set false to hide until permission received

    init(id: String, name: String, shortLabel: String, brandColor: Color, importFormat: BankFormat?, isApproved: Bool = false) {
        self.id = id
        self.name = name
        self.shortLabel = shortLabel
        self.brandColor = brandColor
        self.importFormat = importFormat
        self.isApproved = isApproved
    }

    var hasLogoAsset: Bool { isApproved && UIImage(named: id) != nil }

    func matches(_ query: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }

    static let all: [KnownBank] = [
        // — Import-capable (match BankFormat cases) —
        .init(id: "bank_ubs",         name: "UBS",                      shortLabel: "UBS",   brandColor: Color(red:0.85,green:0.02,blue:0.12), importFormat: .ubs),
        .init(id: "bank_zugerkb",     name: "Zuger Kantonalbank",        shortLabel: "ZugerKB", brandColor: Color(red:0.00,green:0.42,blue:0.80), importFormat: .zugerKantonalbank),
        .init(id: "bank_zkb",         name: "Zürcher Kantonalbank",      shortLabel: "ZKB",   brandColor: Color(red:0.00,green:0.30,blue:0.65), importFormat: .zuercherKantonalbank),
        .init(id: "bank_yuh",         name: "Yuh",                       shortLabel: "yuh",   brandColor: Color(red:0.43,green:0.12,blue:0.84), importFormat: .yuh),
        .init(id: "bank_swisscard",   name: "SwissCard",                 shortLabel: "SC",    brandColor: Color(red:0.00,green:0.42,blue:0.60), importFormat: .swisscard),
        // — Kantonalbanken Schweiz —
        .init(id: "bank_postfinance", name: "PostFinance",               shortLabel: "PF",    brandColor: Color(red:0.95,green:0.73,blue:0.00), importFormat: nil),
        .init(id: "bank_raiffeisen",  name: "Raiffeisen",                shortLabel: "RB",    brandColor: Color(red:0.82,green:0.00,blue:0.12), importFormat: nil),
        .init(id: "bank_migrosbank",  name: "Migros Bank",               shortLabel: "MB",    brandColor: Color(red:1.00,green:0.55,blue:0.00), importFormat: nil),
        .init(id: "bank_coopfinance", name: "Coop Finance+",             shortLabel: "CF+",   brandColor: Color(red:0.00,green:0.58,blue:0.28), importFormat: nil),
        .init(id: "bank_valiant",     name: "Valiant",                   shortLabel: "VAL",   brandColor: Color(red:0.00,green:0.48,blue:0.30), importFormat: nil),
        .init(id: "bank_bekb",        name: "BEKB",                      shortLabel: "BEKB",  brandColor: Color(red:0.00,green:0.50,blue:0.28), importFormat: nil),
        .init(id: "bank_luzernerkb",  name: "Luzerner KB",               shortLabel: "LKB",   brandColor: Color(red:0.00,green:0.45,blue:0.75), importFormat: nil),
        .init(id: "bank_sgkb",        name: "St. Galler KB",             shortLabel: "SGKB",  brandColor: Color(red:0.00,green:0.42,blue:0.72), importFormat: nil),
        .init(id: "bank_thkb",        name: "Thurgauer KB",              shortLabel: "TKB",   brandColor: Color(red:0.00,green:0.47,blue:0.78), importFormat: nil),
        .init(id: "bank_graubkb",     name: "Graubündner KB",            shortLabel: "GKB",   brandColor: Color(red:0.75,green:0.00,blue:0.00), importFormat: nil),
        .init(id: "bank_blkb",        name: "BLKB",                      shortLabel: "BLKB",  brandColor: Color(red:0.00,green:0.42,blue:0.72), importFormat: nil),
        .init(id: "bank_bkb",         name: "BKB",                       shortLabel: "BKB",   brandColor: Color(red:0.00,green:0.40,blue:0.68), importFormat: nil),
        .init(id: "bank_szkb",        name: "Schwyzer KB",               shortLabel: "SZKB",  brandColor: Color(red:0.68,green:0.00,blue:0.10), importFormat: nil),
        .init(id: "bank_akb",         name: "Aargauische KB",            shortLabel: "AKB",   brandColor: Color(red:0.85,green:0.15,blue:0.15), importFormat: nil),
        .init(id: "bank_appkb",       name: "Appenzeller KB",            shortLabel: "APPKB", brandColor: Color(red:0.80,green:0.00,blue:0.10), importFormat: nil),
        .init(id: "bank_bancastato",  name: "BancaStato",                shortLabel: "BST",   brandColor: Color(red:0.00,green:0.30,blue:0.60), importFormat: nil),
        .init(id: "bank_bcf",         name: "BCF – Freiburger KB",       shortLabel: "BCF",   brandColor: Color(red:0.00,green:0.35,blue:0.65), importFormat: nil),
        .init(id: "bank_bcj",         name: "BCJ – Jurassische KB",      shortLabel: "BCJ",   brandColor: Color(red:0.78,green:0.62,blue:0.00), importFormat: nil),
        .init(id: "bank_bcn",         name: "BCN – Neuenburger KB",      shortLabel: "BCN",   brandColor: Color(red:0.00,green:0.42,blue:0.55), importFormat: nil),
        .init(id: "bank_glkb",        name: "Glarner KB",                shortLabel: "GLKB",  brandColor: Color(red:0.00,green:0.35,blue:0.60), importFormat: nil),
        .init(id: "bank_nkb",         name: "Nidwaldner KB",             shortLabel: "NKB",   brandColor: Color(red:0.72,green:0.00,blue:0.08), importFormat: nil),
        .init(id: "bank_okb",         name: "Obwaldner KB",              shortLabel: "OKB",   brandColor: Color(red:0.68,green:0.00,blue:0.10), importFormat: nil),
        .init(id: "bank_shkb",        name: "Schaffhauser KB",           shortLabel: "SHKB",  brandColor: Color(red:0.00,green:0.48,blue:0.25), importFormat: nil),
        .init(id: "bank_urk",         name: "Urner KB",                  shortLabel: "URK",   brandColor: Color(red:0.85,green:0.60,blue:0.00), importFormat: nil),
        .init(id: "bank_wkb",         name: "Walliser KB",               shortLabel: "WKB",   brandColor: Color(red:0.78,green:0.00,blue:0.10), importFormat: nil),
        .init(id: "bank_neon",        name: "Neon",                      shortLabel: "neon",  brandColor: Color(red:0.08,green:0.75,blue:0.56), importFormat: nil),
        .init(id: "bank_cler",        name: "Bank Cler",                 shortLabel: "Cler",  brandColor: Color(red:0.00,green:0.46,blue:0.78), importFormat: nil),
        .init(id: "bank_juliusbaer",  name: "Julius Bär",                shortLabel: "JB",    brandColor: Color(red:0.78,green:0.60,blue:0.10), importFormat: nil),
        .init(id: "bank_acrevis",     name: "Acrevis",                   shortLabel: "ACR",   brandColor: Color(red:0.00,green:0.52,blue:0.78), importFormat: nil),
        .init(id: "bank_wir",         name: "WIR Bank",                  shortLabel: "WIR",   brandColor: Color(red:0.00,green:0.42,blue:0.70), importFormat: nil),
        .init(id: "bank_alternative", name: "Alternative Bank",          shortLabel: "ABS",   brandColor: Color(red:0.18,green:0.62,blue:0.30), importFormat: nil),
        .init(id: "bank_bcge",        name: "BCGE",                      shortLabel: "BCGE",  brandColor: Color(red:0.00,green:0.42,blue:0.72), importFormat: nil),
        .init(id: "bank_bcv",         name: "BCV",                       shortLabel: "BCV",   brandColor: Color(red:0.00,green:0.48,blue:0.82), importFormat: nil),
        .init(id: "bank_hypi",        name: "Hypi Lenzburg",             shortLabel: "Hypi",  brandColor: Color(red:0.00,green:0.55,blue:0.80), importFormat: nil),
        .init(id: "bank_swissquote",  name: "Swissquote",                shortLabel: "SQ",    brandColor: Color(red:0.00,green:0.40,blue:0.72), importFormat: nil),
        .init(id: "bank_cornerbank",  name: "Cornèr Bank",               shortLabel: "CB",    brandColor: Color(red:0.00,green:0.35,blue:0.65), importFormat: nil),
        // — Versicherungen & Säule 3a —
        .init(id: "bank_mobiliar",    name: "Die Mobiliar",              shortLabel: "MOB",   brandColor: Color(red:0.90,green:0.35,blue:0.00), importFormat: nil),
        .init(id: "bank_swisslife",   name: "Swiss Life",                shortLabel: "SL",    brandColor: Color(red:0.05,green:0.20,blue:0.45), importFormat: nil),
        .init(id: "bank_axa",         name: "AXA",                       shortLabel: "AXA",   brandColor: Color(red:0.00,green:0.00,blue:0.52), importFormat: nil),
        .init(id: "bank_helvetia",    name: "Helvetia",                  shortLabel: "HEL",   brandColor: Color(red:0.72,green:0.00,blue:0.12), importFormat: nil),
        .init(id: "bank_zurich",      name: "Zurich",                    shortLabel: "ZUR",   brandColor: Color(red:0.00,green:0.18,blue:0.55), importFormat: nil),
        .init(id: "bank_baloise",     name: "Baloise",                   shortLabel: "BAL",   brandColor: Color(red:0.00,green:0.22,blue:0.50), importFormat: nil),
        .init(id: "bank_pax",         name: "Pax",                       shortLabel: "PAX",   brandColor: Color(red:0.00,green:0.55,blue:0.35), importFormat: nil),
        .init(id: "bank_generali",    name: "Generali",                  shortLabel: "GEN",   brandColor: Color(red:0.75,green:0.00,blue:0.12), importFormat: nil),
        .init(id: "bank_allianz",     name: "Allianz",                   shortLabel: "ALZ",   brandColor: Color(red:0.00,green:0.28,blue:0.62), importFormat: nil),
        // — Digitale Säule 3a —
        .init(id: "bank_viac",        name: "VIAC",                      shortLabel: "VIAC",  brandColor: Color(red:0.00,green:0.60,blue:0.50), importFormat: nil),
        .init(id: "bank_frankly",     name: "Frankly",                   shortLabel: "FKL",   brandColor: Color(red:0.95,green:0.45,blue:0.05), importFormat: nil),
        .init(id: "bank_finpension",  name: "finpension",                shortLabel: "FP",    brandColor: Color(red:0.05,green:0.22,blue:0.48), importFormat: nil),
        .init(id: "bank_selma",       name: "Selma Finance",             shortLabel: "SEL",   brandColor: Color(red:0.40,green:0.20,blue:0.70), importFormat: nil),
        .init(id: "bank_truewealth",  name: "True Wealth",               shortLabel: "TW",    brandColor: Color(red:0.08,green:0.18,blue:0.38), importFormat: nil),
        .init(id: "bank_inyova",      name: "Inyova",                    shortLabel: "INY",   brandColor: Color(red:0.10,green:0.65,blue:0.35), importFormat: nil),
        // — International / Digital —
        .init(id: "bank_revolut",     name: "Revolut",                   shortLabel: "REV",   brandColor: Color(red:0.12,green:0.12,blue:0.12), importFormat: nil),
        .init(id: "bank_wise",        name: "Wise",                      shortLabel: "WISE",  brandColor: Color(red:0.40,green:0.82,blue:0.22), importFormat: nil),
        .init(id: "bank_n26",         name: "N26",                       shortLabel: "N26",   brandColor: Color(red:0.12,green:0.12,blue:0.12), importFormat: nil),
        .init(id: "bank_ing",         name: "ING",                       shortLabel: "ING",   brandColor: Color(red:1.00,green:0.55,blue:0.00), importFormat: nil),
        .init(id: "bank_dkb",         name: "DKB",                       shortLabel: "DKB",   brandColor: Color(red:0.00,green:0.35,blue:0.70), importFormat: nil),
        .init(id: "bank_sparkasse",   name: "Sparkasse",                 shortLabel: "SPAR",  brandColor: Color(red:1.00,green:0.00,blue:0.00), importFormat: nil),
        .init(id: "bank_volksbank",   name: "Volksbank",                 shortLabel: "VB",    brandColor: Color(red:0.00,green:0.52,blue:0.28), importFormat: nil),
        .init(id: "bank_comdirect",   name: "Comdirect",                 shortLabel: "COM",   brandColor: Color(red:1.00,green:0.78,blue:0.00), importFormat: nil),
    ]
}

// MARK: - KnownBank provider lookup

extension KnownBank {
    // Cached by trimmed provider string — eliminates repeated linear scans through 50+ entries per row render
    nonisolated(unsafe) private static var _providerCache: [String: KnownBank?] = [:]

    static func forProvider(_ provider: String) -> KnownBank? {
        let key = provider.trimmingCharacters(in: .whitespaces)
        if let cached = _providerCache[key] { return cached }
        let result = all.first { $0.name.localizedCaseInsensitiveCompare(key) == .orderedSame }
        _providerCache[key] = result
        return result
    }
}

// MARK: - BankFormat display (shared by BankImportView and BankPickerSheet)

extension BankFormat {
    var knownBank: KnownBank? { KnownBank.all.first { $0.importFormat == self } }
    var shortLabel: String    { knownBank?.shortLabel ?? rawValue }
    var brandColor: Color     { knownBank?.brandColor ?? .blue }
    var logoAssetName: String { knownBank?.id ?? "" }
    var hasLogoAsset: Bool    { (knownBank?.isApproved ?? false) && UIImage(named: logoAssetName) != nil }
    var fileTypeLabel: String {
        switch self {
        case .swisscard:         return "CSV / XLSX"
        case .zugerKantonalbank: return "CSV / PDF"
        default:                 return "CSV"
        }
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || rawValue.localizedCaseInsensitiveContains(query)
    }
}

// MARK: - Shared Profile Emojis

let profileEmojis: [String] = [
    "👤", "👫", "👨‍👩‍👧", "👨‍👩‍👦‍👦",
    "🏠", "💼", "🏦", "🎯",
    "🌟", "💰", "🚗", "✈️",
    "🎓", "❤️", "📊", "🏡",
    "🤓", "😎", "🤩", "🥳",
    "🌈", "🍀", "💪", "🔥"
]

// MARK: - Card Style Modifier

private struct CardStyleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat

    private var milkOpacity: Double { colorScheme == .dark ? 0.06 : 1.0 }
    private var borderColor: Color { colorScheme == .dark ? .white.opacity(0.14) : .white.opacity(0.95) }

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(milkOpacity))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            }
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(borderColor, lineWidth: 0.6))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.04), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Background Theme

enum BackgroundTheme: String, CaseIterable {
    case emerald  = "emerald"   // green / mint — default
    case sapphire = "sapphire"  // blue / cyan
    case amethyst = "amethyst"  // purple / indigo
    case gold     = "gold"      // amber / yellow
    case rose     = "rose"      // pink / coral
    case arctic   = "arctic"    // cyan / teal
    case crimson  = "crimson"   // red / orange
    case mono     = "mono"      // neutral gray
    case sunset   = "sunset"    // warm orange / amber
    case violet   = "violet"    // violet / lavender
    case coffee   = "coffee"    // caramel / brown
    case neon     = "neon"      // lime / chartreuse

    var primary: Color {
        switch self {
        case .emerald:  return .green
        case .sapphire: return .blue
        case .amethyst: return .purple
        case .gold:     return Color(red: 0.95, green: 0.70, blue: 0.10)
        case .rose:     return Color(red: 0.95, green: 0.30, blue: 0.55)
        case .arctic:   return .cyan
        case .crimson:  return Color(red: 0.85, green: 0.15, blue: 0.20)
        case .mono:     return Color(white: 0.55)
        case .sunset:   return Color(red: 0.95, green: 0.45, blue: 0.10)
        case .violet:   return Color(red: 0.60, green: 0.20, blue: 0.90)
        case .coffee:   return Color(red: 0.55, green: 0.32, blue: 0.12)
        case .neon:     return Color(red: 0.30, green: 0.90, blue: 0.15)
        }
    }

    var secondary: Color {
        switch self {
        case .emerald:  return .mint
        case .sapphire: return .cyan
        case .amethyst: return .indigo
        case .gold:     return Color(red: 0.95, green: 0.55, blue: 0.10)
        case .rose:     return Color(red: 0.95, green: 0.55, blue: 0.35)
        case .arctic:   return .teal
        case .crimson:  return Color(red: 0.90, green: 0.45, blue: 0.10)
        case .mono:     return Color(white: 0.40)
        case .sunset:   return Color(red: 0.95, green: 0.70, blue: 0.10)
        case .violet:   return Color(red: 0.80, green: 0.40, blue: 0.95)
        case .coffee:   return Color(red: 0.75, green: 0.50, blue: 0.25)
        case .neon:     return Color(red: 0.55, green: 0.95, blue: 0.30)
        }
    }

    var label: String {
        switch self {
        case .emerald:  return "Emerald"
        case .sapphire: return "Sapphire"
        case .amethyst: return "Amethyst"
        case .gold:     return "Gold"
        case .rose:     return "Rose"
        case .arctic:   return "Arctic"
        case .crimson:  return "Crimson"
        case .mono:     return "Mono"
        case .sunset:   return "Sunset"
        case .violet:   return "Violet"
        case .coffee:   return "Coffee"
        case .neon:     return "Neon"
        }
    }
}

// MARK: - Animated Background

struct AnimatedPatternBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("bg_theme")     private var rawTheme  = BackgroundTheme.emerald.rawValue
    @AppStorage("bg_intensity") private var intensity = 1.0

    private var dark: Bool { colorScheme == .dark }
    private var theme: BackgroundTheme { BackgroundTheme(rawValue: rawTheme) ?? .emerald }
    private func scaled(_ base: Double) -> Double { min(base * intensity, 0.95) }

    var body: some View {
        let p = theme.primary
        let s = theme.secondary
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Color(.systemGroupedBackground)
                Circle()
                    .fill(RadialGradient(colors: [p.opacity(scaled(dark ? 0.30 : 0.12)), .clear],
                                         center: .center, startRadius: 0, endRadius: w * 0.7))
                    .frame(width: w * 1.4, height: w * 1.4)
                    .position(x: w * 0.25, y: h * 0.18)
                Circle()
                    .fill(RadialGradient(colors: [s.opacity(scaled(dark ? 0.20 : 0.09)), .clear],
                                         center: .center, startRadius: 0, endRadius: w * 0.65))
                    .frame(width: w * 1.3, height: w * 1.3)
                    .position(x: w * 0.78, y: h * 0.82)
            }
            .blur(radius: 50)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - View Extensions

extension View {
    @ViewBuilder
    func decimalPadKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }

    func cardStyle(cornerRadius: CGFloat = 14) -> some View {
        modifier(CardStyleModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Color Hex Extensions

extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned = String(cleaned.dropFirst()) }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8)  & 0xFF) / 255
        let b = Double(value & 0xFF)         / 255
        self.init(red: r, green: g, blue: b)
    }

    func hexString() -> String {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #else
        return "#808080"
        #endif
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let categoryRulesDidImport = Notification.Name("categoryRulesDidImport")
}

// MARK: - Button Styles

struct ScalePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct PressHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.06) : Color.clear)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
