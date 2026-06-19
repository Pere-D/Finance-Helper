import Foundation
import SwiftData

@Model
final class HealthScoreSettings {
    var emergencyFundWeight: Double = 25.0
    var debtToAssetWeight: Double = 25.0
    var investmentRatioWeight: Double = 25.0
    var creditBurdenWeight: Double = 25.0

    var emergencyFundEnabled: Bool = true
    var debtToAssetEnabled: Bool = true
    var investmentRatioEnabled: Bool = true
    var creditBurdenEnabled: Bool = true

    init() {}

    func resetToDefaults() {
        emergencyFundWeight = 25
        debtToAssetWeight = 25
        investmentRatioWeight = 25
        creditBurdenWeight = 25
        emergencyFundEnabled = true
        debtToAssetEnabled = true
        investmentRatioEnabled = true
        creditBurdenEnabled = true
    }
}
