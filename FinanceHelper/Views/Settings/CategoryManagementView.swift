import SwiftUI
import SwiftData

struct CategoryManagementView: View {
    @AppStorage("active_profile_id") private var activeProfileID: String = ""
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allCustomCategories: [UserTransactionCategory]

    private var customCategories: [UserTransactionCategory] {
        allCustomCategories.filter { $0.profileID == activeProfileID }
    }

    @State private var showingAdd = false
    @State private var newName: String = ""
    @State private var newColorHex: String = "#5856D6"
    @State private var newSystemImage: String = "tag.fill"

    private let presetColors: [String] = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#00C7BE",
        "#007AFF", "#5856D6", "#AF52DE", "#FF2D55", "#A2845E", "#636366"
    ]

    private let presetIcons: [String] = [
        "tag.fill", "star.fill", "heart.fill", "bolt.fill", "gift.fill",
        "cart.fill", "house.fill", "car.fill", "airplane", "beach.umbrella.fill",
        "music.note", "book.fill", "dumbbell.fill", "gamecontroller.fill", "camera.fill",
        "phone.fill", "envelope.fill", "hammer.fill", "leaf.fill", "flame.fill",
        "drop.fill", "snowflake", "sun.max.fill", "moon.fill"
    ]

    private let iconColumns = [
        GridItem(.adaptive(minimum: 44), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            List {
                if !customCategories.isEmpty {
                    Section("Eigene Kategorien") {
                        ForEach(customCategories) { cat in
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(cat.color.opacity(0.15))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: cat.systemImage)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(cat.color)
                                }
                                Text(cat.name)
                                    .font(.subheadline)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                modelContext.delete(customCategories[index])
                            }
                        }
                    }
                }

                if showingAdd {
                    Section("Neue Kategorie") {
                        TextField("Name der Kategorie", text: $newName)
                            .autocorrectionDisabled()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Farbe")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(presetColors, id: \.self) { hex in
                                        let color = Color(hex: hex) ?? .purple
                                        let isSelected = newColorHex == hex
                                        Button {
                                            newColorHex = hex
                                        } label: {
                                            Circle()
                                                .fill(color)
                                                .frame(width: 30, height: 30)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.primary, lineWidth: isSelected ? 2.5 : 0)
                                                        .padding(2)
                                                )
                                                .overlay(
                                                    isSelected
                                                        ? Image(systemName: "checkmark")
                                                            .font(.system(size: 11, weight: .bold))
                                                            .foregroundStyle(.white)
                                                        : nil
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Symbol")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: iconColumns, spacing: 8) {
                                ForEach(presetIcons, id: \.self) { icon in
                                    let selectedColor = Color(hex: newColorHex) ?? .purple
                                    let isSelected = newSystemImage == icon
                                    Button {
                                        newSystemImage = icon
                                    } label: {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(isSelected ? selectedColor.opacity(0.18) : Color.secondary.opacity(0.08))
                                            Image(systemName: icon)
                                                .font(.system(size: 18))
                                                .foregroundStyle(isSelected ? selectedColor : Color.secondary)
                                        }
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? selectedColor : Color.clear, lineWidth: 1.5)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)

                        Button("Hinzufügen") {
                            addCategory()
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                    }
                }

                if customCategories.isEmpty && !showingAdd {
                    ContentUnavailableView {
                        Label("Keine eigenen Kategorien", systemImage: "tag.slash.fill")
                    } description: {
                        Text("Tippe auf + um eine eigene Kategorie\nzu erstellen.")
                    }
                }
            }
            .navigationTitle("Eigene Kategorien")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { showingAdd.toggle() }
                        if !showingAdd {
                            newName = ""
                            newColorHex = "#5856D6"
                            newSystemImage = "tag.fill"
                        }
                    } label: {
                        Image(systemName: showingAdd ? "xmark" : "plus")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private func addCategory() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let cat = UserTransactionCategory(
            name: name,
            systemImage: newSystemImage,
            colorHex: newColorHex,
            profileID: activeProfileID
        )
        modelContext.insert(cat)
        newName = ""
        newColorHex = "#5856D6"
        newSystemImage = "tag.fill"
        withAnimation { showingAdd = false }
    }
}
