import SwiftUI
import Observation

@Observable
final class NavigationRouter {
    static let shared = NavigationRouter()
    
    var selectedTab: Int = 0
    var analyseCategoryFilter: TransactionCategory? = nil
    var analyseDateFrom: Date? = nil

    private init() {}

    func jumpToAnalyse(with category: TransactionCategory?, dateFrom: Date? = nil) {
        self.analyseDateFrom = dateFrom
        self.selectedTab = 2
        // Delay the filter so AnalyseView is active and in the hierarchy when onChange fires
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            self.analyseCategoryFilter = category
        }
    }
}
