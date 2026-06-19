import SwiftUI
import SwiftData

// MARK: - Suggestion data

struct BudgetSuggestion: Identifiable {
    let id: String
    let category: TransactionCategory
    let actualMonthly: Double      // average monthly spend (last 3 months)
    let plannedMonthly: Double     // sum of matching budget entries' effective monthly amount
    let txCount: Int               // number of transactions counted

    var deviation: Double { actualMonthly - plannedMonthly }
    var hasPlan: Bool { plannedMonthly > 0 }
}

// MARK: - Sheet

struct BudgetSuggestionSheet: View {
    let transactions: [ImportedTransaction]
    let currency: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BudgetEntry.createdAt) private var allBudgetEntries: [BudgetEntry]
    @AppStorage("active_profile_id") private var activeProfileID: String = ""
    @AppStorage("bg_theme") private var rawTheme = BackgroundTheme.emerald.rawValue

    @State private var addedCategories: Set<String> = []
    @State private var showingApplyAllConfirm = false
    @State private var editedAmounts: [String: String] = [:]
    @FocusState private var focusedAmount: String?

    private var themeAccent: Color { BackgroundTheme(rawValue: rawTheme)?.primary ?? .blue }

    private var profileBudgetEntries: [BudgetEntry] {
        allBudgetEntries.filter { $0.profileID == activeProfileID && $0.isActive }
    }

    /// Window: last 3 calendar months ending today (inclusive of partial current month).
    private var dateRange: (from: Date, to: Date) {
        let cal = Calendar.current
        let today = Date()
        let from = cal.date(byAdding: .month, value: -3, to: today) ?? today
        return (from, today)
    }

    private var filteredTransactions: [ImportedTransaction] {
        let (from, to) = dateRange
        return transactions.filter { $0.date >= from && $0.date <= to && !$0.category.isInternal }
    }

    private var suggestions: [BudgetSuggestion] {
        // Group by category, average per month. For income categories use only
        // positive-amount transactions; for expense categories use only negative-amount
        // transactions. This prevents salary refunds from being suggested as income
        // and miscategorised positive transactions from polluting expense averages.
        var byCategory: [TransactionCategory: (total: Double, count: Int)] = [:]
        for tx in filteredTransactions {
            let key = tx.category
            if key == .einkommen {
                guard tx.isIncome else { continue }
            } else {
                guard tx.isExpense else { continue }
            }
            byCategory[key, default: (0, 0)].total += tx.amount
            byCategory[key, default: (0, 0)].count += 1
        }

        // Sum existing planned monthly amounts per *transaction* category via the suggested mapping.
        var plannedByTxCat: [TransactionCategory: Double] = [:]
        for entry in profileBudgetEntries {
            // Reverse map: find which TX category maps to this budget category. Take the first.
            for txCat in TransactionCategory.allCases where txCat.suggestedBudgetCategory == entry.category {
                plannedByTxCat[txCat, default: 0] += entry.effectiveMonthlyAmount
                break
            }
        }

        let result = byCategory.map { (cat, agg) -> BudgetSuggestion in
            BudgetSuggestion(
                id: cat.rawValue,
                category: cat,
                actualMonthly: agg.total / 3.0,
                plannedMonthly: plannedByTxCat[cat] ?? 0,
                txCount: agg.count
            )
        }
        // Sort: highest actual spend first
        return result.sorted { $0.actualMonthly > $1.actualMonthly }
    }

    private var totalActual: Double  { suggestions.reduce(0) { $0 + currentAmount(for: $1) } }
    private var totalPlanned: Double { suggestions.reduce(0) { $0 + $1.plannedMonthly } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    if suggestions.isEmpty {
                        emptyState
                    } else {
                        ForEach(suggestions) { sug in
                            suggestionCard(sug)
                        }
                    }
                    Color.clear.frame(height: 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .background(AnimatedPatternBackground())
            .navigationTitle("Budget-Vorschlag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Fertig") { focusedAmount = nil }
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                }
                if !suggestions.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingApplyAllConfirm = true
                        } label: {
                            Label("Alle übernehmen", systemImage: "tray.and.arrow.down.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .confirmationDialog(
                "Alle Vorschläge übernehmen?",
                isPresented: $showingApplyAllConfirm,
                titleVisibility: .visible
            ) {
                Button(String(format: NSLocalizedString("%lld Einträge anlegen", comment: ""), pendingCount)) {
                    applyAll()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Für jede Kategorie wird ein neuer Budget-Eintrag angelegt — auch wenn schon einer existiert. Du kannst die Beträge danach im Budget-Planer anpassen.")
            }
        }
    }

    private var pendingCount: Int {
        suggestions.filter { !addedCategories.contains($0.id) }.count
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Letzte 3 Monate", systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(filteredTransactions.count) Tx")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 10) {
                statBox(label: "Ø Ausgaben / Monat", value: totalActual, color: .red)
                statBox(label: "Geplant / Monat", value: totalPlanned, color: .primary)
            }
            if totalPlanned > 0 {
                let delta = totalActual - totalPlanned
                HStack(spacing: 6) {
                    Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.bold))
                    Text("Abweichung: \(delta.formatted(.currency(code: currency)))")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(delta > 0 ? .red : .green)
            } else {
                Text("Noch keine Budgetplanung vorhanden — übernimm einzelne Vorschläge oder alle.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .cardStyle(cornerRadius: 14)
    }

    private func statBox(label: LocalizedStringKey, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.formatted(.currency(code: currency).notation(.compactName)))
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Per-category card

    private func suggestionCard(_ sug: BudgetSuggestion) -> some View {
        let alreadyAdded = addedCategories.contains(sug.id)
        let current = currentAmount(for: sug)
        let liveDeviation = current - sug.plannedMonthly
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(sug.category.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: sug.category.systemImage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(sug.category.color)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(sug.category.localizedName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(String(format: NSLocalizedString("Ø aus %lld Tx", comment: ""), sug.txCount))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                HStack(spacing: 4) {
                    TextField("0", text: amountTextBinding(for: sug))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedAmount, equals: sug.id)
                        .font(.body.weight(.bold))
                        .foregroundStyle(sug.category.color)
                        .frame(width: 80)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(sug.category.color.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(alreadyAdded)
                    Text(currency)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if sug.hasPlan {
                HStack(spacing: 6) {
                    Text("Geplant:")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(sug.plannedMonthly.formatted(.currency(code: currency)))
                        .font(.caption.weight(.medium))
                        .contentTransition(.numericText())
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: liveDeviation > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2.weight(.bold))
                        Text(liveDeviation.formatted(.currency(code: currency)))
                            .font(.caption.weight(.semibold))
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(liveDeviation > 0 ? Color.red : Color.green)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((liveDeviation > 0 ? Color.red : Color.green).opacity(0.12))
                    .clipShape(Capsule())
                }
            } else {
                Text("Noch nicht im Budget geplant")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button { applySuggestion(sug) } label: {
                HStack(spacing: 6) {
                    Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    Group {
                        if alreadyAdded {
                            Text("Übernommen")
                        } else if sug.hasPlan {
                            Text("Eintrag anpassen")
                        } else {
                            Text("Als Eintrag übernehmen")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(alreadyAdded ? Color.green.opacity(0.18) : themeAccent.opacity(0.15))
                .foregroundStyle(alreadyAdded ? Color.green : themeAccent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(alreadyAdded)
        }
        .padding(14)
        .cardStyle(cornerRadius: 14)
    }

    // MARK: - Amount editing helpers

    private func amountTextBinding(for sug: BudgetSuggestion) -> Binding<String> {
        Binding(
            get: { editedAmounts[sug.id] ?? defaultAmountString(sug.actualMonthly) },
            set: { editedAmounts[sug.id] = $0 }
        )
    }

    private func currentAmount(for sug: BudgetSuggestion) -> Double {
        if let s = editedAmounts[sug.id], let v = parseAmount(s) { return v }
        return sug.actualMonthly
    }

    private func parseAmount(_ s: String) -> Double? {
        let normalized = s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func defaultAmountString(_ value: Double) -> String {
        String(format: "%.0f", value.rounded())
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Keine Ausgaben in den letzten 3 Monaten gefunden.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private func applySuggestion(_ sug: BudgetSuggestion) {
        focusedAmount = nil
        let amount = currentAmount(for: sug).rounded()
        let entry = BudgetEntry(
            category: sug.category.suggestedBudgetCategory,
            amount: amount,
            recurrence: .monthly
        )
        entry.profileID = activeProfileID
        entry.notes = String(format: NSLocalizedString("Aus Analyse generiert (%lld Tx, Ø 3 Monate)", comment: ""), sug.txCount)
        entry.isActive = true
        modelContext.insert(entry)
        addedCategories.insert(sug.id)
    }

    private func applyAll() {
        for sug in suggestions where !addedCategories.contains(sug.id) {
            applySuggestion(sug)
        }
    }
}
