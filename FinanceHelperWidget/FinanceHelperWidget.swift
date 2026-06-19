import WidgetKit
import SwiftUI

// MARK: - Snapshot (inline copy of WidgetDataBridge types for widget target)

struct WidgetSnapshot: Codable {
    var netWorth: Double = 0
    var totalAssets: Double = 0
    var totalLiabilities: Double = 0
    var monthlyNetFlow: Double = 0
    var currency: String = "CHF"
    var updatedAt: Date = Date()
    var topAccounts: [AccountSnap] = []

    struct AccountSnap: Codable {
        var name: String
        var balance: Double
        var currency: String
        var typeRaw: String
    }

    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            netWorth: 42_500,
            totalAssets: 50_000,
            totalLiabilities: 7_500,
            monthlyNetFlow: 850,
            currency: "CHF",
            updatedAt: Date(),
            topAccounts: [
                AccountSnap(name: "Konto", balance: 12_500, currency: "CHF", typeRaw: "bank"),
                AccountSnap(name: "Depot", balance: 30_000, currency: "CHF", typeRaw: "investment")
            ]
        )
    }
}

private func loadSnapshot() -> WidgetSnapshot {
    guard let defaults = UserDefaults(suiteName: "group.com.dxlic.FinanceHelper"),
          let data = defaults.data(forKey: "widget_snapshot_v1"),
          let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    else { return .placeholder }
    return snap
}

// MARK: - Timeline

struct FinanceEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct FinanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> FinanceEntry {
        FinanceEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FinanceEntry) -> Void) {
        completion(FinanceEntry(date: .now, snapshot: context.isPreview ? .placeholder : loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FinanceEntry>) -> Void) {
        let entry = FinanceEntry(date: .now, snapshot: loadSnapshot())
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Small Widget

private struct SmallWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text("Nettovermögen")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(snapshot.netWorth, format: .currency(code: snapshot.currency).notation(.compactName))
                .font(.title2.weight(.bold))
                .foregroundStyle(snapshot.netWorth >= 0 ? Color.primary : Color.red)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: snapshot.monthlyNetFlow >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2)
                    .foregroundStyle(snapshot.monthlyNetFlow >= 0 ? .green : .red)
                Text(snapshot.monthlyNetFlow, format: .currency(code: snapshot.currency).notation(.compactName))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(snapshot.monthlyNetFlow >= 0 ? .green : .red)
                Text("/ Mo.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}

// MARK: - Medium Widget

private struct MediumWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text("Nettovermögen")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(snapshot.netWorth, format: .currency(code: snapshot.currency).notation(.compactName))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(snapshot.netWorth >= 0 ? Color.primary : Color.red)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Spacer()

                flowRow("Aktiva", value: snapshot.totalAssets, color: .green)
                flowRow("Schulden", value: snapshot.totalLiabilities, color: .red)
                flowRow("Monatsfluss", value: snapshot.monthlyNetFlow,
                        color: snapshot.monthlyNetFlow >= 0 ? .green : .red)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("Top Konten")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                if snapshot.topAccounts.isEmpty {
                    Text("Keine Daten")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.topAccounts.prefix(3), id: \.name) { acct in
                        HStack {
                            Text(acct.name)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            Text(acct.balance, format: .currency(code: acct.currency).notation(.compactName))
                                .font(.caption2.weight(.semibold))
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private func flowRow(_ label: String, value: Double, color: Color) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(value, format: .currency(code: snapshot.currency).notation(.compactName))
                .font(.caption2.weight(.medium)).foregroundStyle(color)
        }
    }
}

// MARK: - Entry View

struct FinanceHelperWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FinanceEntry

    var body: some View {
        switch family {
        case .systemMedium: MediumWidgetView(snapshot: entry.snapshot)
        default:            SmallWidgetView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Widget

struct FinanceHelperWidget: Widget {
    let kind = "FinanceHelperWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinanceProvider()) { entry in
            FinanceHelperWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Finanzen")
        .description("Nettovermögen und monatlicher Cashflow.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
