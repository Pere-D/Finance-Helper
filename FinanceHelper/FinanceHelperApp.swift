import SwiftUI
import SwiftData
#if os(iOS)
import UIKit

private class AppDelegate: NSObject, UIApplicationDelegate {
    private var keyboardPrewarmed = false

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Prevents UIScrollView from delaying touch delivery to subviews (TextFields, Buttons).
        // Without this, taps inside Forms inside nested sheets trigger "System gesture gate timed out".
        UIScrollView.appearance().delaysContentTouches = false
        UITableView.appearance().delaysContentTouches = false
        UICollectionView.appearance().backgroundColor = .clear
        UIBarButtonItem.appearance().tintColor = UIColor.label
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        guard !keyboardPrewarmed else { return }
        keyboardPrewarmed = true
        // Fire the one-time ManagedConfiguration MDM policy check (≈2s main-thread block)
        // while the splash screen is still visible so users never notice the delay.
        // Delay slightly to ensure the SwiftUI window exists before we query it.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            self.prewarmKeyboard(application)
        }
    }

    private func prewarmKeyboard(_ application: UIApplication) {
        guard let scene = application.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.keyWindow else { return }
        let tf = UITextField()
        // No inputView override: the custom empty inputView suppresses keyboard subsystem
        // init entirely, so the ManagedConfiguration check never runs. We need the real path.
        // alpha = 0 + off-screen frame = invisible. (isHidden would block becomeFirstResponder.)
        tf.alpha = 0
        tf.frame = CGRect(x: -200, y: -200, width: 1, height: 1)
        window.addSubview(tf)
        // becomeFirstResponder triggers the ~2s MDM check synchronously on the main thread.
        // resignFirstResponder called immediately after: the keyboard animation has not yet been
        // committed to Core Animation, so the keyboard never appears on screen.
        _ = tf.becomeFirstResponder()
        _ = tf.resignFirstResponder()
        tf.removeFromSuperview()
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}
#endif

@main
struct FinanceHelperApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) fileprivate var appDelegate
    #endif

    init() {
        if UserDefaults.standard.object(forKey: "default_currency") == nil {
            let supported: Set<String> = ["EUR", "CHF", "USD", "GBP", "JPY", "CAD", "AUD",
                                          "SEK", "NOK", "DKK", "CZK", "PLN", "HUF", "RON",
                                          "HKD", "SGD", "CNY", "INR", "BRL", "MXN", "ZAR",
                                          "TRY", "AED", "SAR", "KRW", "IDR"]
            let detected = Locale.current.currency?.identifier ?? "EUR"
            UserDefaults.standard.set(supported.contains(detected) ? detected : "EUR",
                                      forKey: "default_currency")
        }
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Account.self,
            MonthlyEntry.self,
            HealthScoreSettings.self,
            BudgetEntry.self,
            UserBudgetCategory.self,
            CustomAccountType.self,
            UserProfile.self,
            FinancialGoal.self,
            ImportedTransaction.self,
            UserTransactionCategory.self,
        ])
        do {
            return try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            ])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var splashVisible = true
    @State private var purchaseManager = PurchaseManager()
    @AppStorage("appearance_mode") private var appearanceMode = "system"

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(purchaseManager)
                if splashVisible {
                    SplashView { splashVisible = false }
                }
            }
            .preferredColorScheme(preferredScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}
