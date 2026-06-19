import Foundation
import Observation
import SwiftUI

@Observable
final class CurrencyService {
    static let shared = CurrencyService()

    private(set) var exchangeRates: [String: Double]
    private(set) var lastSyncSuccessful: Bool = false
    private(set) var lastSyncDate: Date?

    private static let ratesCacheKey = "currency_rates_cache"
    private static let syncDateKey   = "currency_rates_sync_date"

    static let currencyFlags: [String: String] = [
        "CHF": "🇨🇭", "EUR": "🇪🇺", "USD": "🇺🇸", "GBP": "🇬🇧", "JPY": "🇯🇵",
        "CAD": "🇨🇦", "AUD": "🇦🇺", "SEK": "🇸🇪", "NOK": "🇳🇴", "DKK": "🇩🇰",
        "PLN": "🇵🇱", "CZK": "🇨🇿", "HUF": "🇭🇺", "RON": "🇷🇴", "HKD": "🇭🇰",
        "SGD": "🇸🇬", "CNY": "🇨🇳", "INR": "🇮🇳", "BRL": "🇧🇷", "MXN": "🇲🇽",
        "ZAR": "🇿🇦", "TRY": "🇹🇷", "AED": "🇦🇪", "SAR": "🇸🇦", "KRW": "🇰🇷",
        "IDR": "🇮🇩",
    ]

    static let supportedCurrencies: [String] = [
        "CHF", "EUR", "USD", "GBP", "JPY", "CAD", "AUD", "SEK", "NOK", "DKK",
        "PLN", "CZK", "HUF", "RON", "HKD", "SGD", "CNY", "INR", "BRL", "MXN",
        "ZAR", "TRY", "AED", "SAR", "KRW", "IDR",
    ]

    private static let builtInFallback: [String: Double] = [
        "EUR": 1.0, "USD": 1.08, "GBP": 0.86, "CHF": 0.96, "JPY": 162.0,
        "CAD": 1.47, "AUD": 1.64, "SEK": 11.50, "NOK": 11.70, "DKK": 7.46,
        "PLN": 4.25, "CZK": 25.30, "HUF": 395.0, "RON": 4.97, "HKD": 8.45,
        "SGD": 1.46, "CNY": 7.85, "INR": 90.0, "BRL": 5.85, "MXN": 19.5,
        "ZAR": 20.5, "TRY": 36.5, "AED": 3.97, "SAR": 4.05, "KRW": 1450.0,
        "IDR": 17200.0,
    ]

    enum RateAge { case fresh, recent, stale, offline }

    var isUsingFallback: Bool { !lastSyncSuccessful || lastSyncDate == nil }

    var rateAge: RateAge {
        guard let date = lastSyncDate else { return .offline }
        let hours = Date().timeIntervalSince(date) / 3600
        if hours < 6  { return .fresh }
        if hours < 24 { return .recent }
        return .stale
    }

    var statusLabel: String {
        switch rateAge {
        case .fresh:   return "Aktuell"
        case .recent:  return "Heute aktualisiert"
        case .stale:   return "Veraltet"
        case .offline: return "Offline (Fallback)"
        }
    }

    var statusColor: Color {
        switch rateAge {
        case .fresh, .recent: return .green
        case .stale:          return .orange
        case .offline:        return .red
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.ratesCacheKey),
           let cached = try? JSONDecoder().decode([String: Double].self, from: data) {
            exchangeRates = cached
            let ts = UserDefaults.standard.double(forKey: Self.syncDateKey)
            if ts > 0 {
                lastSyncDate = Date(timeIntervalSince1970: ts)
                lastSyncSuccessful = true
            }
        } else {
            exchangeRates = Self.builtInFallback
        }
    }

    func convert(_ amount: Double, from: String, to: String) -> Double {
        guard from != to else { return amount }
        let fromRate = exchangeRates[from] ?? 1.0
        let toRate   = exchangeRates[to]   ?? 1.0
        return amount / fromRate * toRate
    }

    func formattedRate(from: String, to: String) -> String {
        let rate = convert(1.0, from: from, to: to)
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = rate < 0.01 ? 6 : (rate < 1 ? 4 : 2)
        fmt.minimumFractionDigits = 2
        let rateStr = fmt.string(from: NSNumber(value: rate)) ?? String(format: "%.4f", rate)
        return "1 \(from) = \(rateStr) \(to)"
    }

    func fetchExchangeRates() async {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/EUR") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded   = try JSONDecoder().decode(ERResponse.self, from: data)
            var rates = decoded.rates
            rates["EUR"] = 1.0
            exchangeRates      = rates
            lastSyncSuccessful = true
            lastSyncDate       = Date()
            if let encoded = try? JSONEncoder().encode(rates) {
                UserDefaults.standard.set(encoded, forKey: Self.ratesCacheKey)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.syncDateKey)
            }
        } catch {
            lastSyncSuccessful = false
        }
    }

    private struct ERResponse: Decodable {
        let rates: [String: Double]
    }
}
