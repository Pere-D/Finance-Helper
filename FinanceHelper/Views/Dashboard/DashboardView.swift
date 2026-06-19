import SwiftUI
import SwiftData

struct DashboardView: View {
    @AppStorage("active_profile_id") private var activeProfileID: String = ""

    var body: some View {
        NavigationStack {
            DashboardContentView(profileID: activeProfileID)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [Account.self, MonthlyEntry.self, HealthScoreSettings.self], inMemory: true)
}
