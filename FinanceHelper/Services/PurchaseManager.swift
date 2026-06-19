import Foundation
import StoreKit
import Observation

@MainActor
@Observable
final class PurchaseManager {

    static let productIDMonthly  = "ch.financehelper.pro.monthly"
    static let productIDAnnual   = "ch.financehelper.pro.annual"
    static let productIDLifetime = "financehelper_pro_lifetime"
    static let allProductIDs: [String] = [productIDMonthly, productIDAnnual, productIDLifetime]

    #if DEBUG
    /// Flip to `false` to test the free-tier experience in debug builds.
    private static let simulatePremium = true
    #endif

    // TestFlight builds use a sandboxReceipt — unlock premium automatically for testers
    static var isTestFlight: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    private(set) var isPremium: Bool
    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var purchaseError: String?

    var monthlyProduct:  Product? { products.first { $0.id == Self.productIDMonthly } }
    var annualProduct:   Product? { products.first { $0.id == Self.productIDAnnual } }
    var lifetimeProduct: Product? { products.first { $0.id == Self.productIDLifetime } }

    // Legacy accessor — existing call sites that use .product continue to compile
    var product: Product? { annualProduct ?? monthlyProduct ?? lifetimeProduct }

    private nonisolated(unsafe) var listenerTask: Task<Void, Never>?

    init() {
        #if DEBUG
        isPremium = Self.simulatePremium
        #else
        isPremium = Self.isTestFlight || UserDefaults.standard.bool(forKey: "isPremiumUnlocked")
        #endif
        listenerTask = Task { await listenForTransactions() }
        Task {
            await loadProducts()
            await verifyEntitlements()
        }
    }

    deinit { listenerTask?.cancel() }

    // MARK: - Public

    func purchase(_ productID: String) async {
        guard let product = products.first(where: { $0.id == productID }) else {
            purchaseError = NSLocalizedString("paywall_product_unavailable", comment: "")
            return
        }
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    unlock()
                    await tx.finish()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // Legacy no-arg purchase — picks the annual plan as default
    func purchase() async {
        let id = annualProduct?.id ?? monthlyProduct?.id ?? lifetimeProduct?.id
            ?? Self.productIDAnnual
        await purchase(id)
    }

    func restore() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await verifyEntitlements()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Private

    private func loadProducts() async {
        guard let loaded = try? await Product.products(for: Self.allProductIDs) else { return }
        products = loaded
    }

    private func verifyEntitlements() async {
        guard !Self.isTestFlight else { return }

        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, Self.allProductIDs.contains(tx.productID) {
                unlock()
                await tx.finish()
                found = true
                return
            }
        }
        if !found && !products.isEmpty {
            isPremium = false
            UserDefaults.standard.set(false, forKey: "isPremiumUnlocked")
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let tx) = result, Self.allProductIDs.contains(tx.productID) {
                unlock()
                await tx.finish()
            }
        }
    }

    private func unlock() {
        isPremium = true
        UserDefaults.standard.set(true, forKey: "isPremiumUnlocked")
    }

    #if DEBUG
    func debugTogglePremium() {
        if isPremium {
            isPremium = false
            UserDefaults.standard.set(false, forKey: "isPremiumUnlocked")
        } else {
            unlock()
        }
    }
    #endif
}
