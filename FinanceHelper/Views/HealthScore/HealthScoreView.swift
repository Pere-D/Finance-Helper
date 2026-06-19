import SwiftUI
import SwiftData

// MARK: - Embeddable section (Dashboard "Weitere Einsichten")

struct HealthScoreSection: View {
    @Query(sort: \Account.createdAt) private var allAccountsRaw: [Account]
    @AppStorage("active_profile_id") private var activeProfileID: String = ""
    @State private var viewModel = HealthScoreViewModel()
    @State private var showingDetail = false

    private var accounts: [Account] { allAccountsRaw.filter { $0.profileID == activeProfileID } }

    var body: some View {
        VStack(spacing: 16) {
            sectionHeader
            gaugeCard
        }
        .onChange(of: accounts) { viewModel.accounts = accounts }
        .onChange(of: activeProfileID) { viewModel.accounts = accounts }
        .onAppear { viewModel.accounts = accounts }
        .sheet(isPresented: $showingDetail) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        criteriaCard
                        tipsCard
                        formulaCard
                    }
                    .padding()
                }
                .background(AnimatedPatternBackground())
                .navigationTitle("Score Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { showingDetail = false }
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Text("Finance Score")
                .font(.headline.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Cards

    private var gaugeCard: some View {
        Button { showingDetail = true } label: {
            VStack(spacing: 12) {
                ScoreGaugeView(score: viewModel.score)

                Text(NSLocalizedString(viewModel.scoreLabelKey, comment: ""))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(scoreColor)

                HStack(spacing: 4) {
                    Text("Details")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal)
            .cardStyle(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    private var criteriaCard: some View {
        VStack(spacing: 0) {
            SectionHeader(title: NSLocalizedString("criteria", comment: ""),
                          icon: "checklist")
            Divider()
            ForEach(viewModel.criteriaInfo, id: \.nameKey) { criterion in
                ReadOnlyCriterionRow(criterion: criterion)
                if criterion.nameKey != viewModel.criteriaInfo.last?.nameKey {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .cardStyle()
    }

    private var tipsCard: some View {
        VStack(spacing: 0) {
            SectionHeader(title: NSLocalizedString("tips_title", comment: ""),
                          icon: "lightbulb")
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.improvementTips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.blue.opacity(0.7))
                            .padding(.top, 1)
                        Text(tip)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .cardStyle()
    }

    private var formulaCard: some View {
        VStack(spacing: 0) {
            SectionHeader(title: NSLocalizedString("how_calculated_title", comment: ""),
                          icon: "info.circle")
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                ForEach(viewModel.criteriaInfo, id: \.nameKey) { c in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(c.weight)%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                            .frame(width: 34, alignment: .leading)
                            .contentTransition(.numericText())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString(c.nameKey, comment: ""))
                                .font(.subheadline.weight(.medium))
                            Text(NSLocalizedString(c.descriptionKey, comment: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .cardStyle()
    }

    private var scoreColor: Color {
        switch viewModel.scoreCategory {
        case .excellent: return .green
        case .good:      return .mint
        case .fair:      return .yellow
        case .poor:      return .orange
        case .critical:  return .red
        }
    }
}

// MARK: - Read-Only Criterion Row

struct ReadOnlyCriterionRow: View {
    let criterion: HealthScoreViewModel.CriterionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(NSLocalizedString(criterion.nameKey, comment: ""))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%.0f", criterion.score))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(scoreColor(criterion.score))
                    .frame(width: 28, alignment: .trailing)
                    .contentTransition(.numericText())
            }
            ProgressView(value: criterion.score, total: 100)
                .tint(scoreColor(criterion.score))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func scoreColor(_ s: Double) -> Color {
        switch s {
        case 80...100: return .green
        case 60..<80:  return .mint
        case 40..<60:  return .yellow
        case 20..<40:  return .orange
        default:       return .red
        }
    }
}

#Preview {
    ScrollView { HealthScoreSection().padding() }
        .modelContainer(for: [Account.self, MonthlyEntry.self, HealthScoreSettings.self], inMemory: true)
}
