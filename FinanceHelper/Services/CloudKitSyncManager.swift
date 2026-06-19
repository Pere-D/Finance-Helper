import Foundation
import CloudKit
import SwiftData
import Observation

// Requires iCloud capability with CloudKit enabled in Xcode project settings.

@MainActor
@Observable
final class CloudKitSyncManager {

    var isSyncing = false
    var lastSyncDate: Date?
    var syncError: String?

    private var privateDB: CKDatabase { CKContainer.default().privateCloudDatabase }

    // MARK: - Lifecycle

    func enable(context: ModelContext) async {
        syncError = nil
        do {
            let status = try await CKContainer.default().accountStatus()
            guard status == .available else {
                syncError = NSLocalizedString("icloud_account_unavailable", comment: "")
                return
            }
        } catch {
            syncError = error.localizedDescription
            return
        }
        await setupSubscription()
        await uploadAll(context: context)
    }

    func disable() {
        isSyncing = false
        syncError = nil
    }

    // MARK: - Upload

    func uploadAll(context: ModelContext) async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let accounts = try context.fetch(FetchDescriptor<Account>())
            let entries  = try context.fetch(FetchDescriptor<BudgetEntry>())
            // Deduplicate by recordID — SwiftData can surface duplicate model instances
            // for the same UUID, which causes "can't save the same record twice" in CloudKit.
            var seen = Set<CKRecord.ID>()
            let records = (accounts.map(makeAccountRecord) + entries.map(makeBudgetEntryRecord))
                .filter { seen.insert($0.recordID).inserted }
            for batch in records.chunked(into: 400) {
                _ = try await privateDB.modifyRecords(saving: batch, deleting: [], savePolicy: .allKeys)
            }
            lastSyncDate = Date()
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: - Fetch & Merge

    func fetchRemoteChanges(context: ModelContext) async {
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }
        do {
            let localAccounts = try context.fetch(FetchDescriptor<Account>())
            let localEntries  = try context.fetch(FetchDescriptor<BudgetEntry>())
            let accountMap    = Dictionary(localAccounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let entryMap      = Dictionary(localEntries.map  { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            // Queries require record types to have a Queryable index on "recordName"
            // configured in the CloudKit Dashboard (Schema → Record Types → Indexes).
            let accountMatches = await fetchAll(recordType: "FinanceHelper_Account")
            let entryMatches   = await fetchAll(recordType: "FinanceHelper_BudgetEntry")

            for record in accountMatches {
                guard let idStr = record["id"] as? String,
                      let id    = UUID(uuidString: idStr) else { continue }
                if let local = accountMap[id] {
                    if (record.modificationDate ?? .distantPast) > local.createdAt {
                        applyAccountRecord(record, to: local)
                    }
                } else if let acc = makeAccount(from: record) {
                    context.insert(acc)
                }
            }

            for record in entryMatches {
                guard let idStr = record["id"] as? String,
                      let id    = UUID(uuidString: idStr) else { continue }
                if let local = entryMap[id] {
                    if (record.modificationDate ?? .distantPast) > local.createdAt {
                        applyBudgetEntryRecord(record, to: local)
                    }
                } else if let entry = makeBudgetEntry(from: record) {
                    context.insert(entry)
                }
            }

            try context.save()
            lastSyncDate = Date()
        } catch {
            syncError = error.localizedDescription
        }
    }

    // Fetches all records of the given type; returns [] and sets syncError if the query fails
    // (e.g. record type not yet indexed in CloudKit Dashboard).
    private func fetchAll(recordType: String) async -> [CKRecord] {
        do {
            let (matches, _) = try await privateDB.records(
                matching: CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            )
            return matches.compactMap { try? $1.get() }
        } catch let ckError as CKError {
            switch ckError.code {
            case .unknownItem:
                // Record type doesn't exist yet — no data uploaded for this type, silently skip.
                return []
            default:
                syncError = "[\(recordType)] \(ckError.localizedDescription)"
                return []
            }
        } catch {
            syncError = "[\(recordType)] \(error.localizedDescription)"
            return []
        }
    }

    // MARK: - CKRecord Factories

    private func makeAccountRecord(_ account: Account) -> CKRecord {
        let record = CKRecord(
            recordType: "FinanceHelper_Account",
            recordID: CKRecord.ID(recordName: "Account-\(account.id.uuidString)")
        )
        record["id"]        = account.id.uuidString
        record["typeRaw"]   = account.typeRaw
        record["currency"]  = account.currency
        record["isVisible"] = account.isVisible as NSNumber
        record["createdAt"] = account.createdAt
        record["profileID"] = account.profileID

        record.encryptedValues["name"]             = account.name
        record.encryptedValues["balance"]          = account.balance as NSNumber
        record.encryptedValues["provider"]         = account.provider
        record.encryptedValues["annualGrowthRate"] = account.annualGrowthRate as NSNumber
        record.encryptedValues["kaufpreis"]        = account.kaufpreis as NSNumber
        record.encryptedValues["hypothekBetrag"]   = account.hypothekBetrag as NSNumber
        record.encryptedValues["hypothekZinssatz"] = account.hypothekZinssatz as NSNumber
        record.encryptedValues["linked3aAccountID"] = account.linked3aAccountID
        if let d = account.kaufdatum { record["kaufdatum"] = d }
        return record
    }

    private func makeBudgetEntryRecord(_ entry: BudgetEntry) -> CKRecord {
        let record = CKRecord(
            recordType: "FinanceHelper_BudgetEntry",
            recordID: CKRecord.ID(recordName: "BudgetEntry-\(entry.id.uuidString)")
        )
        record["id"]            = entry.id.uuidString
        record["dueDay"]        = entry.dueDay as NSNumber
        record["dueDate"]       = entry.dueDate
        record["isActive"]      = entry.isActive as NSNumber
        record["createdAt"]     = entry.createdAt
        record["profileID"]     = entry.profileID
        record["recurrenceRaw"] = entry.recurrenceRaw

        record.encryptedValues["amount"]      = entry.amount as NSNumber
        record.encryptedValues["notes"]       = entry.notes
        record.encryptedValues["categoryRaw"] = entry.categoryRaw
        return record
    }

    private func makeAccount(from record: CKRecord) -> Account? {
        guard let idStr    = record["id"] as? String,
              let id       = UUID(uuidString: idStr),
              let name     = record.encryptedValues["name"] as? String,
              let typeRaw  = record["typeRaw"] as? String,
              let balanceN = record.encryptedValues["balance"] as? NSNumber,
              let currency = record["currency"] as? String else { return nil }

        let account              = Account(name: name,
                                           type: AccountType(rawValue: typeRaw) ?? .girokonto,
                                           balance: balanceN.doubleValue,
                                           currency: currency)
        account.id                = id
        account.createdAt         = record["createdAt"] as? Date ?? Date()
        account.profileID         = record["profileID"] as? String ?? ""
        account.isVisible         = (record["isVisible"] as? NSNumber)?.boolValue ?? true
        account.provider          = record.encryptedValues["provider"] as? String ?? ""
        account.annualGrowthRate  = (record.encryptedValues["annualGrowthRate"] as? NSNumber)?.doubleValue ?? 0
        account.kaufpreis         = (record.encryptedValues["kaufpreis"] as? NSNumber)?.doubleValue ?? 0
        account.kaufdatum         = record["kaufdatum"] as? Date
        account.hypothekBetrag    = (record.encryptedValues["hypothekBetrag"] as? NSNumber)?.doubleValue ?? 0
        account.hypothekZinssatz  = (record.encryptedValues["hypothekZinssatz"] as? NSNumber)?.doubleValue ?? 0
        account.linked3aAccountID = record.encryptedValues["linked3aAccountID"] as? String ?? ""
        return account
    }

    private func makeBudgetEntry(from record: CKRecord) -> BudgetEntry? {
        guard let idStr         = record["id"] as? String,
              let id            = UUID(uuidString: idStr),
              let amountN       = record.encryptedValues["amount"] as? NSNumber,
              let categoryRaw   = record.encryptedValues["categoryRaw"] as? String,
              let recurrenceRaw = record["recurrenceRaw"] as? String else { return nil }

        let entry        = BudgetEntry(category:   BudgetCategory(rawValue: categoryRaw) ?? .lebensmittel,
                                       amount:     amountN.doubleValue,
                                       recurrence: BudgetRecurrence(rawValue: recurrenceRaw) ?? .monthly)
        entry.id         = id
        entry.notes      = record.encryptedValues["notes"] as? String ?? ""
        entry.dueDay     = (record["dueDay"] as? NSNumber)?.intValue ?? 25
        entry.dueDate    = record["dueDate"] as? Date ?? Date()
        entry.isActive   = (record["isActive"] as? NSNumber)?.boolValue ?? true
        entry.createdAt  = record["createdAt"] as? Date ?? Date()
        entry.profileID  = record["profileID"] as? String ?? ""
        return entry
    }

    private func applyAccountRecord(_ record: CKRecord, to account: Account) {
        if let v = record.encryptedValues["name"] as? String { account.name = v }
        if let n = record.encryptedValues["balance"] as? NSNumber { account.balance = n.doubleValue }
        if let v = record.encryptedValues["provider"] as? String { account.provider = v }
        if let n = record.encryptedValues["annualGrowthRate"] as? NSNumber { account.annualGrowthRate = n.doubleValue }
        if let n = record["isVisible"] as? NSNumber { account.isVisible = n.boolValue }
        // Preserve local profileID if the remote record has none (e.g. records uploaded before multi-profile support).
        if let v = record["profileID"] as? String, !v.isEmpty { account.profileID = v }
        if let n = record.encryptedValues["kaufpreis"] as? NSNumber { account.kaufpreis = n.doubleValue }
        if let d = record["kaufdatum"] as? Date { account.kaufdatum = d }
        if let n = record.encryptedValues["hypothekBetrag"] as? NSNumber { account.hypothekBetrag = n.doubleValue }
        if let n = record.encryptedValues["hypothekZinssatz"] as? NSNumber { account.hypothekZinssatz = n.doubleValue }
        if let v = record.encryptedValues["linked3aAccountID"] as? String { account.linked3aAccountID = v }
    }

    private func applyBudgetEntryRecord(_ record: CKRecord, to entry: BudgetEntry) {
        if let n = record.encryptedValues["amount"] as? NSNumber { entry.amount = n.doubleValue }
        if let v = record.encryptedValues["notes"] as? String { entry.notes = v }
        if let v = record.encryptedValues["categoryRaw"] as? String { entry.categoryRaw = v }
        if let v = record["recurrenceRaw"] as? String { entry.recurrenceRaw = v }
        if let n = record["isActive"] as? NSNumber { entry.isActive = n.boolValue }
        if let n = record["dueDay"] as? NSNumber { entry.dueDay = n.intValue }
        if let v = record["dueDate"] as? Date { entry.dueDate = v }
    }

    // MARK: - Push Subscription

    private func setupSubscription() async {
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        let sub = CKDatabaseSubscription(subscriptionID: "financehelper-changes")
        sub.notificationInfo = info
        do {
            try await CKContainer.default().privateCloudDatabase.save(sub)
        } catch let ckError as CKError where ckError.code == .serverRejectedRequest {
            // Subscription already exists — safe to ignore
        } catch {
            print("[CloudKit] setupSubscription: \(error.localizedDescription)")
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
