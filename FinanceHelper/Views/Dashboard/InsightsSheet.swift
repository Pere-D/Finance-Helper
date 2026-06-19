import SwiftUI

struct InsightsSheet: View {
    let viewModel: DashboardViewModel
    let currency: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HealthScoreSection()
                    providerSection
                }
                .padding()
            }
            .background(AnimatedPatternBackground())
            .navigationTitle("Weitere Einsichten")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                        .tint(.primary)
                }
            }
        }
        .tint(.primary)
    }

    @ViewBuilder
    private var providerSection: some View {
        let breakdown = viewModel.providerBreakdown()
        VStack(spacing: 0) {
            SectionHeader(title: NSLocalizedString("provider_distribution", comment: ""),
                          icon: "building.columns")
            Divider()
            if breakdown.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Trage bei deinen Konten den Anbieter (z. B. \"DKB\") ein, um hier die Aufteilung zu sehen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(breakdown) { provider in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                // Left: provider name + account chips
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(provider.provider)
                                        .font(.subheadline.weight(.semibold))
                                    HStack(spacing: 4) {
                                        ForEach(provider.accounts.prefix(4)) { acc in
                                            HStack(spacing: 3) {
                                                Image(systemName: acc.icon)
                                                    .font(.system(size: 8, weight: .medium))
                                                    .foregroundStyle(acc.color)
                                                Text(acc.name)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(acc.color.opacity(0.08))
                                            .clipShape(Capsule())
                                        }
                                        if provider.accounts.count > 4 {
                                            Text("+\(provider.accounts.count - 4)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                // Right: big percentage + small total
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(String(format: "%.0f%%", provider.percentage))
                                        .font(.title3.weight(.black))
                                        .monospacedDigit()
                                        .contentTransition(.numericText())
                                    Text(provider.total.formatted(.currency(code: currency)
                                        .notation(.compactName)
                                        .precision(.fractionLength(0))))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                        .contentTransition(.numericText())
                                }
                            }

                            // Thin progress bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.10)).frame(height: 4)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.primary.opacity(0.5))
                                        .frame(width: max(6, geo.size.width * CGFloat(provider.percentage / 100)), height: 4)
                                }
                            }
                            .frame(height: 4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        if provider.id != breakdown.last?.id {
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .cardStyle()
    }

}
