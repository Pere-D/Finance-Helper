import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "👤"
    var createdAt: Date = Date()

    init(name: String, emoji: String = "👤") {
        self.name = name
        self.emoji = emoji
    }
}
