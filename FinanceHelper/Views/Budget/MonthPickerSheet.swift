import SwiftUI

struct MonthPickerSheet: View {
    @Binding var selectedMonth: Date
    @Environment(\.dismiss) private var dismiss

    @State private var year: Int
    @State private var month: Int

    private static let shortMonths: [String] = {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        return fmt.shortMonthSymbols
    }()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    init(selectedMonth: Binding<Date>) {
        self._selectedMonth = selectedMonth
        let cal = Calendar.current
        self._year  = State(initialValue: cal.component(.year,  from: selectedMonth.wrappedValue))
        self._month = State(initialValue: cal.component(.month, from: selectedMonth.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 20) {
            // Drag indicator area / title
            Text("Zeitraum wählen")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            // Year navigation
            HStack(spacing: 0) {
                Button { withAnimation(.spring(response: 0.25)) { year -= 1 } } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text(String(year))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .frame(minWidth: 80, alignment: .center)
                    .contentTransition(.numericText())

                Button { withAnimation(.spring(response: 0.25)) { year += 1 } } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Month grid
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(1...12, id: \.self) { m in
                    let isSelected = m == month
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { month = m }
                    } label: {
                        Text(Self.shortMonths[m - 1])
                            .font(.subheadline.weight(isSelected ? .bold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(isSelected ? Color.primary.opacity(0.12) : Color.secondary.opacity(0.07))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(isSelected ? Color.primary.opacity(0.25) : Color.clear, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Confirm button
            Button {
                if let date = Calendar.current.date(from: DateComponents(year: year, month: month)) {
                    selectedMonth = date
                }
                dismiss()
            } label: {
                Text("Übernehmen")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.primary.opacity(0.09))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
    }
}
