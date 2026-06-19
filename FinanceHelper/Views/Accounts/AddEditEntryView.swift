import SwiftUI
import SwiftData

struct AddEditEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    let account: Account
    var entry: MonthlyEntry?
    var onDelete: (() -> Void)? = nil

    @State private var label: String = ""
    @State private var amountText: String = ""
    @State private var isIncome: Bool = true
    @State private var selectedInterval: EntryInterval = .monthly
    @State private var dayOfMonth: Int = 25
    @State private var createTransfer: Bool = false
    @State private var transferTargetAccount: Account? = nil

    private var isNew: Bool { entry == nil }
    private var isTransferEntry: Bool { entry?.isTransfer ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("entry_label", comment: "")) {
                    TextField(NSLocalizedString("entry_label_placeholder", comment: ""), text: $label)
                        .disabled(isTransferEntry)
                }

                Section(NSLocalizedString("entry_amount", comment: "")) {
                    HStack {
                        TextField("0.00", text: $amountText)
                            .decimalPadKeyboard()
                            .disabled(isTransferEntry)
                        Spacer()
                        Text(account.currency)
                            .foregroundStyle(.secondary)
                    }
                }

                if !isTransferEntry {
                    Section(NSLocalizedString("entry_direction", comment: "")) {
                        Picker(NSLocalizedString("entry_direction", comment: ""), selection: $isIncome) {
                            Label(NSLocalizedString("entry_income", comment: ""),
                                  systemImage: "arrow.down.circle.fill").tag(true)
                            Label(NSLocalizedString("entry_expense", comment: ""),
                                  systemImage: "arrow.up.circle.fill").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }

                    Section {
                        Picker(NSLocalizedString("interval", comment: ""), selection: $selectedInterval) {
                            ForEach(EntryInterval.allCases, id: \.self) { iv in
                                Text(iv.localizedName).tag(iv)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if selectedInterval.usesDayOfMonth {
                        Section {
                            Stepper(value: $dayOfMonth, in: 1...28) {
                                HStack {
                                    Text(NSLocalizedString("day_of_month", comment: ""))
                                    Spacer()
                                    Text(String(format: NSLocalizedString("day_of_month_format", comment: ""), dayOfMonth))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } footer: {
                            Text(NSLocalizedString("day_of_month_footer", comment: ""))
                        }
                    }

                    // Transfer mirror option — only for new entries
                    if isNew && otherAccounts.count > 0 {
                        Section {
                            Toggle(isOn: $createTransfer) {
                                Label(NSLocalizedString("create_transfer", comment: ""),
                                      systemImage: "arrow.left.arrow.right.circle")
                            }
                            if createTransfer {
                                Picker(NSLocalizedString("transfer_to_account", comment: ""),
                                       selection: $transferTargetAccount) {
                                    Text(NSLocalizedString("select_account", comment: ""))
                                        .tag(nil as Account?)
                                    ForEach(otherAccounts) { acc in
                                        Label(acc.name, systemImage: acc.type.systemImage)
                                            .tag(acc as Account?)
                                    }
                                }
                            }
                        } footer: {
                            if createTransfer {
                                Text(NSLocalizedString("transfer_footer", comment: ""))
                                    .font(.caption)
                            }
                        }
                    }
                }

                // Delete button for existing entries
                if !isNew, let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Label(NSLocalizedString("delete_entry", comment: ""), systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isNew
                ? NSLocalizedString("add_entry", comment: "")
                : NSLocalizedString("edit_entry", comment: ""))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                        .foregroundStyle(.primary)
                }
                if !isTransferEntry {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(NSLocalizedString("save", comment: "")) {
                            save()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .onAppear { populateFromEntry() }
    }

    private var otherAccounts: [Account] {
        allAccounts.filter { $0.id != account.id }
    }

    private func populateFromEntry() {
        guard let entry else { return }
        label = entry.label
        amountText = String(entry.amount)
        isIncome = entry.isIncome
        selectedInterval = entry.interval
        dayOfMonth = entry.dayOfMonth
    }

    private func save() {
        let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let cleanLabel = label.trimmingCharacters(in: .whitespaces)

        if let entry {
            entry.label = cleanLabel
            entry.amount = max(0, amount)
            entry.isIncome = isIncome
            entry.interval = selectedInterval
            entry.dayOfMonth = selectedInterval.usesDayOfMonth ? dayOfMonth : 1
        } else {
            let groupId: UUID? = (createTransfer && transferTargetAccount != nil) ? UUID() : nil

            let newEntry = MonthlyEntry(label: cleanLabel, amount: max(0, amount), isIncome: isIncome)
            newEntry.transferGroupId = groupId
            newEntry.interval = selectedInterval
            newEntry.dayOfMonth = selectedInterval.usesDayOfMonth ? dayOfMonth : 1
            newEntry.account = account
            account.monthlyEntries.append(newEntry)
            modelContext.insert(newEntry)

            if let target = transferTargetAccount, let gid = groupId {
                let mirror = MonthlyEntry(label: cleanLabel, amount: max(0, amount), isIncome: !isIncome)
                mirror.transferGroupId = gid
                mirror.interval = selectedInterval
                mirror.dayOfMonth = newEntry.dayOfMonth
                mirror.account = target
                target.monthlyEntries.append(mirror)
                modelContext.insert(mirror)
            }
        }
    }
}

#Preview {
    AddEditEntryView(account: Account(name: "Girokonto", type: .girokonto, balance: 1000, currency: "EUR"))
        .modelContainer(for: [Account.self, MonthlyEntry.self], inMemory: true)
}
