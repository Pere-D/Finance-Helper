import SwiftUI
import StoreKit

// MARK: - Paywall

struct PaywallView: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlanID: String = PurchaseManager.productIDAnnual

    // ← Datum hier ändern um die Sale-Phase zu verlängern oder zu beenden
    private static let saleEndDate: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 30
        return Calendar.current.date(from: c)!
    }()
    private var isSaleActive: Bool { Date() < Self.saleEndDate }

    private struct Feature {
        let icon: String
        let color: Color
        let nameKey: String
        let descKey: String
        let free: String
        let pro: String
    }

    private let features: [Feature] = [
        Feature(icon: "person.2.fill",                       color: .blue,   nameKey: "paywall_feature_profiles", descKey: "paywall_desc_profiles", free: "1",   pro: "∞"),
        Feature(icon: "creditcard.fill",                     color: .green,  nameKey: "paywall_feature_accounts", descKey: "paywall_desc_accounts", free: "3",   pro: "∞"),
        Feature(icon: "list.bullet.rectangle.portrait.fill", color: .orange, nameKey: "paywall_feature_entries",  descKey: "paywall_desc_entries",  free: "10",  pro: "∞"),
        Feature(icon: "target",                              color: .teal,   nameKey: "paywall_feature_goals",    descKey: "paywall_desc_goals",    free: "1",   pro: "∞"),
        Feature(icon: "icloud.fill",                         color: .blue,   nameKey: "paywall_feature_icloud",   descKey: "paywall_desc_icloud",   free: "—",   pro: "✓"),
        Feature(icon: "square.and.arrow.down.fill",          color: .teal,   nameKey: "Bank-Import",              descKey: "paywall_desc_import",   free: "100", pro: "∞"),
        Feature(icon: "tablecells.fill",                     color: .purple, nameKey: "paywall_feature_csv",      descKey: "paywall_desc_csv",      free: "—",   pro: "✓"),
        Feature(icon: "heart.text.clipboard.fill",           color: .red,    nameKey: "paywall_feature_health",   descKey: "paywall_desc_health",   free: "—",   pro: "✓"),
    ]

    var body: some View {
        ZStack {
            // Dark premium background
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.07, blue: 0.13),
                    Color(red: 0.11, green: 0.09, blue: 0.19),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {

                // Top bar
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(8)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Crown + title
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 1, green: 0.82, blue: 0.15), .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                            .frame(width: 64, height: 64)
                            .shadow(color: .orange.opacity(0.55), radius: 18, x: 0, y: 6)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 8)

                    Text("Finance Helper Pro")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text(NSLocalizedString("paywall_subtitle", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer(minLength: 14)

                // Feature comparison table
                VStack(spacing: 0) {
                    // Column headers
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("paywall_col_free", comment: ""))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(width: 44, alignment: .center)
                        Text("Pro")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                            .frame(width: 44, alignment: .center)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    ForEach(Array(features.enumerated()), id: \.element.nameKey) { idx, f in
                        HStack(spacing: 10) {
                            Image(systemName: f.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(f.color)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(NSLocalizedString(f.nameKey, comment: ""))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text(NSLocalizedString(f.descKey, comment: ""))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer()
                            Text(f.free)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.35))
                                .frame(width: 44, alignment: .center)
                            Text(f.pro)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.orange)
                                .frame(width: 44, alignment: .center)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(idx % 2 == 1 ? Color.white.opacity(0.04) : Color.clear)
                    }
                    .padding(.bottom, 4)
                }
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)

                Spacer(minLength: 10)

                // Launch sale banner (automatisch ausgeblendet nach saleEndDate)
                if isSaleActive {
                    HStack(spacing: 7) {
                        Image(systemName: "tag.fill")
                            .font(.caption.weight(.bold))
                        Text("Einführungsangebot · –50 %")
                            .font(.caption.weight(.bold))
                            .kerning(0.3)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.88, green: 0.22, blue: 0.44), Color(red: 0.65, green: 0.10, blue: 0.72)],
                            startPoint: .leading,
                            endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(red: 0.75, green: 0.15, blue: 0.55).opacity(0.55), radius: 10, x: 0, y: 4)
                    .padding(.bottom, 8)
                }

                // Plan cards
                HStack(spacing: 8) {
                    planCard(
                        id: PurchaseManager.productIDMonthly,
                        title: NSLocalizedString("plan_monthly", comment: ""),
                        price: purchases.monthlyProduct?.displayPrice ?? "CHF 1.95",
                        originalPrice: isSaleActive ? "CHF 3.95" : nil,
                        subtitle: NSLocalizedString("plan_per_month", comment: ""),
                        badge: nil
                    )
                    planCard(
                        id: PurchaseManager.productIDAnnual,
                        title: NSLocalizedString("plan_annual", comment: ""),
                        price: purchases.annualProduct?.displayPrice ?? "CHF 14.95",
                        originalPrice: isSaleActive ? "CHF 29.95" : nil,
                        subtitle: NSLocalizedString("plan_per_year", comment: ""),
                        badge: NSLocalizedString("plan_save_badge", comment: "")
                    )
                    planCard(
                        id: PurchaseManager.productIDLifetime,
                        title: NSLocalizedString("plan_lifetime", comment: ""),
                        price: purchases.lifetimeProduct?.displayPrice ?? "CHF 34.95",
                        originalPrice: isSaleActive ? "CHF 69.95" : nil,
                        subtitle: NSLocalizedString("plan_once", comment: ""),
                        badge: nil
                    )
                }
                .padding(.horizontal)

                Spacer(minLength: 16)

                // Error
                if let error = purchases.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                }

                // CTA
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await purchases.purchase(selectedPlanID) }
                } label: {
                    Group {
                        if purchases.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "crown.fill")
                                if let product = purchases.products.first(where: { $0.id == selectedPlanID }) {
                                    Text("\(NSLocalizedString("upgrade_now", comment: "")) – \(product.displayPrice)")
                                } else {
                                    Text(NSLocalizedString("upgrade_to_premium", comment: ""))
                                }
                            }
                            .font(.body.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 1, green: 0.82, blue: 0.15), .orange],
                            startPoint: .leading,
                            endPoint: .trailing)
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .orange.opacity(0.45), radius: 14, x: 0, y: 6)
                }
                .disabled(purchases.isLoading)
                .padding(.horizontal)

                // Restore + footer
                HStack(spacing: 16) {
                    Button {
                        Task { await purchases.restore() }
                    } label: {
                        Text(NSLocalizedString("paywall_restore", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .disabled(purchases.isLoading)
                    Link("Datenschutz", destination: URL(string: "https://financehelper.ch/datenschutz/")!)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.35))
                    Link("Nutzungsbedingungen", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.top, 10)

                Text(selectedPlanID == PurchaseManager.productIDLifetime
                     ? NSLocalizedString("paywall_footer_lifetime", comment: "")
                     : NSLocalizedString("paywall_footer", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: purchases.isPremium) { _, unlocked in
            if unlocked { dismiss() }
        }
    }

    // MARK: - Plan card

    private func planCard(id: String, title: String, price: String, originalPrice: String? = nil, subtitle: String, badge: String?) -> some View {
        let isSelected = selectedPlanID == id
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { selectedPlanID = id }
        } label: {
            ZStack(alignment: .top) {
                // Glass background
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isSelected
                                  ? Color.orange.opacity(0.22)
                                  : Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected
                                    ? LinearGradient(colors: [Color.orange, Color(red: 1, green: 0.6, blue: 0.1)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )

                VStack(spacing: 5) {
                    // Badge placeholder keeps layout stable
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    } else {
                        Color.clear.frame(height: 18)
                    }

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.orange : Color.white.opacity(0.5))
                        .padding(.top, 2)

                    // Price block
                    VStack(spacing: 2) {
                        if let originalPrice {
                            Text(originalPrice)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.3))
                                .strikethrough(true, color: .white.opacity(0.3))
                        }
                        Text(price)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.bottom, 4)

                    // Checkmark indicator
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? Color.orange : Color.white.opacity(0.2))
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: isSelected ? Color.orange.opacity(0.3) : Color.black.opacity(0.2), radius: isSelected ? 10 : 4, x: 0, y: 4)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
    }
}

// MARK: - Locked placeholder for Premium-only screens

struct PremiumLockedView: View {
    let featureName: String
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "crown.fill")
                .font(.system(size: 52))
                .foregroundStyle(
                    LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.1), .orange],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            VStack(spacing: 6) {
                Text(featureName)
                    .font(.title3.weight(.bold))
                Text(NSLocalizedString("premium_locked_subtitle", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onUpgrade) {
                Label(NSLocalizedString("upgrade_to_premium", comment: ""), systemImage: "crown.fill")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.1), .orange],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: .orange.opacity(0.25), radius: 8, x: 0, y: 4)
            }
            Spacer()
        }
        .padding()
    }
}

#Preview {
    PaywallView()
        .environment(PurchaseManager())
}
