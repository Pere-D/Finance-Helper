import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main View

struct BankImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @Environment(PurchaseManager.self) private var purchases

    @State private var selectedBank: BankFormat? = nil
    @State private var searchText = ""
    @State private var showingFilePicker = false
    @State private var showingAnalysis   = false
    @State private var transactions: [BankTransaction] = []
    @State private var truncatedOriginalCount: Int? = nil
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isParsing = false

    private let gridColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var filteredBanks: [BankFormat] {
        BankFormat.allCases.filter { $0.matches(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Bank suchen…", text: $searchText)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        if filteredBanks.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "building.columns")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.secondary.opacity(0.5))
                                Text("Keine Bank gefunden")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(filteredBanks) { bank in
                                    BankCard(bank: bank, isSelected: selectedBank == bank) {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                            selectedBank = bank
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        // Request button
                        Button { sendBankRequest() } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.12))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "envelope.badge.plus")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.blue)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Wunschbank anfragen")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("Bitte einen echten Kontoauszug als Beispiel-CSV (anonymisiert) mitsenden – ohne Beispieldaten kann die Bank leider nicht implementiert werden.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    .padding(.top, 4)
                }

                Divider()

                VStack(spacing: 10) {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Group {
                            if isParsing {
                                HStack(spacing: 10) {
                                    ProgressView().tint(.white)
                                    Text("Wird geladen…")
                                }
                            } else {
                                let fileKey: LocalizedStringKey = selectedBank == .swisscard ? "Datei auswählen" : "CSV-Datei auswählen"
                                Label(fileKey, systemImage: "doc.badge.plus")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(selectedBank != nil && !isParsing
                                    ? (selectedBank?.brandColor ?? .blue)
                                    : Color.secondary.opacity(0.15))
                        .foregroundStyle(selectedBank != nil && !isParsing ? .white : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(selectedBank == nil || isParsing)
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ProfilePill()
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: allowedFileTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importFile(from: url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
        .alert("Fehler beim Import", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showingAnalysis) {
            TransactionAnalysisView(
                transactions: transactions,
                bank: selectedBank ?? .zugerKantonalbank,
                isNewImport: true,
                truncatedFrom: truncatedOriginalCount,
                onImportComplete: { dismiss() }
            )
        }
    }

    private func sendBankRequest() {
        let subject = "FinanceHelper – Bankwunsch: \(searchText.isEmpty ? "<Bankname>" : searchText)"
        let body = """
        Hallo,

        ich würde mir wünschen, dass folgende Bank in FinanceHelper als Import-Option unterstützt wird:

        Bank: \(searchText.isEmpty ? "<bitte hier eintragen>" : searchText)

        ──────────────────────────────────────────
        WICHTIG – ohne Beispieldaten ist eine Implementierung leider nicht möglich:

        Bitte sende einen echten Kontoauszug im CSV-Format (oder dem Format, das deine Bank anbietet) mit anonymisierten Beispieldaten als Anhang an diese E-Mail.

        Anleitung:
        1. Exportiere einen Kontoauszug direkt aus dem E-Banking deiner Bank (CSV, XLSX oder PDF).
        2. Ersetze alle persönlichen Angaben (Name, IBAN, Betrag) durch Platzhalterdaten – z.B. «Max Mustermann», «CH56 0483 5012 3456 7800 9», «100.00».
        3. Hänge die anonymisierte Datei direkt an diese E-Mail an.
        ──────────────────────────────────────────

        Danke!
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@financehelper.ch"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body",    value: body)
        ]
        if let url = components.url { openURL(url) }
    }

    private var allowedFileTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .plainText, UTType("public.csv") ?? .plainText]
        if selectedBank == .swisscard {
            types.append(.spreadsheet)
            if let xlsx = UTType("org.openxmlformats.spreadsheetml.sheet") { types.append(xlsx) }
            if let xlsx2 = UTType("com.microsoft.excel.xlsx") { types.append(xlsx2) }
        }
        if selectedBank == .zugerKantonalbank {
            types.append(.pdf)
        }
        return types
    }

    private func importFile(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = NSLocalizedString("Zugriff auf Datei verweigert.", comment: "")
            showingError = true
            return
        }
        guard let bank = selectedBank else {
            url.stopAccessingSecurityScopedResource()
            return
        }

        isParsing = true

        Task {
            await Task.yield()
            do {
                let parsed = try BankImportService.parse(url: url, format: bank)
                url.stopAccessingSecurityScopedResource()
                let freeLimit = 100
                if !purchases.isPremium && parsed.count > freeLimit {
                    transactions = Array(parsed.prefix(freeLimit))
                    truncatedOriginalCount = parsed.count
                } else {
                    transactions = parsed
                    truncatedOriginalCount = nil
                }
                showingAnalysis = true
            } catch {
                url.stopAccessingSecurityScopedResource()
                errorMessage = error.localizedDescription
                showingError = true
            }
            isParsing = false
        }
    }
}

// MARK: - Bank Card

private struct BankCard: View {
    let bank: BankFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    if bank.hasLogoAsset {
                        Color.white
                    } else {
                        bank.brandColor.opacity(isSelected ? 0.18 : 0.10)
                    }
                    if bank.hasLogoAsset {
                        Image(bank.logoAssetName)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                    } else {
                        Text(bank.shortLabel)
                            .font(.system(.title2, design: .rounded).weight(.black))
                            .foregroundStyle(bank.brandColor)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                            .lineLimit(2)
                            .padding(.horizontal, 8)
                    }
                }
                .frame(height: 88)

                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bank.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                        Text(bank.fileTypeLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? bank.brandColor : Color.secondary.opacity(0.35))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? bank.brandColor : Color.secondary.opacity(0.25),
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
    }
}
