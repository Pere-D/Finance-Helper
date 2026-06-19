import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var accounts: [Account]
    @Query private var allProfiles: [UserProfile]
    @AppStorage("last_balance_update") private var lastBalanceUpdate: Double = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("active_profile_id") private var activeProfileID: String = ""
    @AppStorage("bg_theme") private var rawTheme = BackgroundTheme.emerald.rawValue

    private var themeAccent: Color { BackgroundTheme(rawValue: rawTheme)?.primary ?? .green }

    @State private var navigationRouter = NavigationRouter.shared
    @State private var isBackground = false

    private var hasActiveProfile: Bool {
        guard !activeProfileID.isEmpty else { return false }
        return allProfiles.contains { $0.id.uuidString == activeProfileID }
    }

    var body: some View {
        ZStack {
            mainTabs

            if !hasCompletedOnboarding {
                OnboardingView { hasCompletedOnboarding = true }
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: .opacity.combined(with: .scale(scale: 1.04))
                    ))
                    .zIndex(1)
            }

            // Privacy overlay: hides financial content in the app switcher screenshot.
            if isBackground {
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.4), value: hasCompletedOnboarding)
    }

    private var mainTabs: some View {
        @Bindable var router = navigationRouter
        return TabView(selection: $router.selectedTab) {
            tabContent { DashboardView() }
                .tabItem { Label("Übersicht", systemImage: "house.fill") }
                .tag(0)

            tabContent { NavigationStack { BudgetPlannerView() } }
                .tabItem { Label(NSLocalizedString("tab_budget", comment: ""), systemImage: "list.bullet.rectangle.portrait.fill") }
                .tag(1)

            tabContent { AnalyseView() }
                .tabItem { Label("Analyse", systemImage: "chart.bar.xaxis.ascending") }
                .tag(2)
        }
        .tint(.primary)
        .onAppear { autoUpdateBalances() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                withAnimation(.easeOut(duration: 0.2)) { isBackground = false }
                autoUpdateBalances()
            } else if newPhase == .background {
                withAnimation(.easeIn(duration: 0.1)) { isBackground = true }
            }
        }
    }

    @ViewBuilder
    private func tabContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if hasActiveProfile {
            content()
        } else {
            NavigationStack { NoProfileView() }
        }
    }

    private func autoUpdateBalances() {
        let now = Date()

        // First launch: record today without touching balances
        guard lastBalanceUpdate > 0 else {
            lastBalanceUpdate = now.timeIntervalSince1970
            return
        }

        let lastDate = Date(timeIntervalSince1970: lastBalanceUpdate)
        let months = Calendar.current.dateComponents([.month], from: lastDate, to: now).month ?? 0
        guard months > 0 else { return }

        // Stamp the new date first — if the app crashes mid-loop the months won't be re-applied on the next launch.
        lastBalanceUpdate = now.timeIntervalSince1970

        for account in accounts {
            if account.type.isLiability {
                account.balance = max(0, account.balance - account.monthlyExpenses * Double(months))
            } else {
                account.balance += account.monthlyCashFlow * Double(months)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Account.self, MonthlyEntry.self, HealthScoreSettings.self], inMemory: true)
}
