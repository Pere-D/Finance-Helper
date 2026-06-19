import Foundation
import SwiftData
import SwiftUI

@Model
final class UserTransactionCategory {
    var id: UUID = UUID()
    var name: String = ""
    var systemImage: String = "tag.fill"
    var colorHex: String = "#5856D6"
    var groupRaw: String = CategoryGroup.lifestyle.rawValue
    var profileID: String = ""

    var color: Color {
        Color(hex: colorHex) ?? .purple
    }

    var group: CategoryGroup { CategoryGroup(rawValue: groupRaw) ?? .lifestyle }

    /// Alias matching the `CategoryDisplayable` protocol requirement.
    var symbolName: String { systemImage }

    init(name: String, systemImage: String = "tag.fill", colorHex: String = "#5856D6",
         group: CategoryGroup = .lifestyle, profileID: String) {
        self.name = name
        self.systemImage = systemImage
        self.colorHex = colorHex
        self.groupRaw = group.rawValue
        self.profileID = profileID
    }
}

extension UserTransactionCategory: CategoryDisplayable {
    var displayName: String { name }
}
