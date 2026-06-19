import Foundation
import SwiftData
import UniformTypeIdentifiers
import SwiftUI

// MARK: - FileDocument wrapper for SwiftUI fileExporter / fileImporter

struct BackupDocument: FileDocument {
    static var readableContentTypes = [UTType.json]

    var data: Data

    init(_ data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Top-level backup envelope

struct AppBackup: Codable {
    var version: Int = 2
    var exportedAt: Date = Date()
    // Optional so old v1 files (missing these keys) decode without error
    var profiles: [UserProfileDTO]? = nil
    var accounts: [AccountDTO] = []
    var userBudgetCategories: [UserBudgetCategoryDTO] = []
    var budgetEntries: [BudgetEntryDTO] = []
    var financialGoals: [FinancialGoalDTO]? = nil
    var customAccountTypes: [CustomAccountTypeDTO]? = nil
    var healthScoreSettings: HealthScoreSettingsDTO? = nil
}

// MARK: - Data Transfer Objects

struct UserProfileDTO: Codable {
    var id: UUID
    var name: String
    var emoji: String
    var createdAt: Date
}

struct AccountDTO: Codable {
    var id: UUID
    var name: String
    var typeRaw: String
    var balance: Double
    var currency: String
    var provider: String?          // optional for v1 backward compat
    var isVisible: Bool
    var createdAt: Date
    var annualGrowthRate: Double
    var customAccountTypeId: UUID? // optional for v1 backward compat
    var monthlyEntries: [MonthlyEntryDTO]
}

struct MonthlyEntryDTO: Codable {
    var id: UUID
    var label: String
    var amount: Double
    var isIncome: Bool
    var intervalRaw: String
    var dayOfMonth: Int
    var transferGroupId: UUID?
}

struct BudgetEntryDTO: Codable {
    var id: UUID
    var categoryRaw: String
    var amount: Double
    var recurrenceRaw: String
    var dueDay: Int
    var dueDate: Date
    var notes: String
    var isActive: Bool
    var createdAt: Date
    var currencyOverride: String?  // optional for v1 backward compat
    var accountId: UUID?
    var userCategoryId: UUID?
    var transferToAccountId: UUID?
}

struct UserBudgetCategoryDTO: Codable {
    var id: UUID
    var name: String
    var symbolName: String
    var colorNameRaw: String
    var isIncome: Bool
    var isSavings: Bool?           // optional for v1 backward compat
    var isInvestment: Bool?        // optional for v1 backward compat
    var groupRaw: String?          // optional for v1 backward compat
    var createdAt: Date
}

struct FinancialGoalDTO: Codable {
    var id: UUID
    var profileID: String
    var name: String
    var categoryRaw: String
    var targetAmount: Double
    var currency: String
    var createdAt: Date
    var priority: Int
    var isActive: Bool
}

struct CustomAccountTypeDTO: Codable {
    var id: UUID
    var name: String
    var symbolName: String
    var colorNameRaw: String
    var bucketRaw: String
    var createdAt: Date
}

struct HealthScoreSettingsDTO: Codable {
    var emergencyFundWeight: Double
    var debtToAssetWeight: Double
    var investmentRatioWeight: Double
    var creditBurdenWeight: Double
    var emergencyFundEnabled: Bool
    var debtToAssetEnabled: Bool
    var investmentRatioEnabled: Bool
    var creditBurdenEnabled: Bool
}

// MARK: - Export

func createBackup(
    accounts: [Account],
    budgetEntries: [BudgetEntry],
    userCategories: [UserBudgetCategory],
    profiles: [UserProfile] = [],
    goals: [FinancialGoal] = [],
    customAccountTypes: [CustomAccountType] = [],
    healthSettings: HealthScoreSettings? = nil
) -> AppBackup {
    AppBackup(
        profiles: profiles.map { p in
            UserProfileDTO(id: p.id, name: p.name, emoji: p.emoji, createdAt: p.createdAt)
        },
        accounts: accounts.map { acc in
            AccountDTO(
                id: acc.id,
                name: acc.name,
                typeRaw: acc.typeRaw,
                balance: acc.balance,
                currency: acc.currency,
                provider: acc.provider,
                isVisible: acc.isVisible,
                createdAt: acc.createdAt,
                annualGrowthRate: acc.annualGrowthRate,
                customAccountTypeId: acc.customAccountType?.id,
                monthlyEntries: acc.monthlyEntries.map { e in
                    MonthlyEntryDTO(
                        id: e.id,
                        label: e.label,
                        amount: e.amount,
                        isIncome: e.isIncome,
                        intervalRaw: e.intervalRaw,
                        dayOfMonth: e.dayOfMonth,
                        transferGroupId: e.transferGroupId
                    )
                }
            )
        },
        userBudgetCategories: userCategories.map { cat in
            UserBudgetCategoryDTO(
                id: cat.id,
                name: cat.name,
                symbolName: cat.symbolName,
                colorNameRaw: cat.colorNameRaw,
                isIncome: cat.isIncome,
                isSavings: cat.isSavings,
                isInvestment: cat.isInvestment,
                groupRaw: cat.groupRaw,
                createdAt: cat.createdAt
            )
        },
        budgetEntries: budgetEntries.map { e in
            BudgetEntryDTO(
                id: e.id,
                categoryRaw: e.categoryRaw,
                amount: e.amount,
                recurrenceRaw: e.recurrenceRaw,
                dueDay: e.dueDay,
                dueDate: e.dueDate,
                notes: e.notes,
                isActive: e.isActive,
                createdAt: e.createdAt,
                currencyOverride: e.currencyOverride,
                accountId: e.account?.id,
                userCategoryId: e.userCategory?.id,
                transferToAccountId: e.transferToAccount?.id
            )
        },
        financialGoals: goals.map { g in
            FinancialGoalDTO(
                id: g.id,
                profileID: g.profileID,
                name: g.name,
                categoryRaw: g.categoryRaw,
                targetAmount: g.targetAmount,
                currency: g.currency,
                createdAt: g.createdAt,
                priority: g.priority,
                isActive: g.isActive
            )
        },
        customAccountTypes: customAccountTypes.map { cat in
            CustomAccountTypeDTO(
                id: cat.id,
                name: cat.name,
                symbolName: cat.symbolName,
                colorNameRaw: cat.colorNameRaw,
                bucketRaw: cat.bucketRaw,
                createdAt: cat.createdAt
            )
        },
        healthScoreSettings: healthSettings.map { s in
            HealthScoreSettingsDTO(
                emergencyFundWeight: s.emergencyFundWeight,
                debtToAssetWeight: s.debtToAssetWeight,
                investmentRatioWeight: s.investmentRatioWeight,
                creditBurdenWeight: s.creditBurdenWeight,
                emergencyFundEnabled: s.emergencyFundEnabled,
                debtToAssetEnabled: s.debtToAssetEnabled,
                investmentRatioEnabled: s.investmentRatioEnabled,
                creditBurdenEnabled: s.creditBurdenEnabled
            )
        }
    )
}

// MARK: - Import

/// Restores one profile's data. Global entities (categories, custom types) are merged.
/// Health score settings are not overwritten to preserve the user's current configuration.
func restoreBackup(_ backup: AppBackup, into context: ModelContext, profileID: String) throws {

    // 1. Merge custom account types (global — add new, keep existing)
    let existingCustomTypes = try context.fetch(FetchDescriptor<CustomAccountType>())
    var customTypeMap = Dictionary(uniqueKeysWithValues: existingCustomTypes.map { ($0.id, $0) })
    for dto in backup.customAccountTypes ?? [] where customTypeMap[dto.id] == nil {
        let cat = CustomAccountType(
            name: dto.name,
            symbolName: dto.symbolName,
            color: CategoryColor(rawValue: dto.colorNameRaw) ?? .blue,
            bucket: AccountBucket(rawValue: dto.bucketRaw) ?? .liquid
        )
        cat.id = dto.id
        cat.createdAt = dto.createdAt
        context.insert(cat)
        customTypeMap[dto.id] = cat
    }

    // 2. Delete this profile's goals (will be re-inserted)
    let profileGoals = try context.fetch(FetchDescriptor<FinancialGoal>(predicate: #Predicate { $0.profileID == profileID }))
    for goal in profileGoals { context.delete(goal) }

    // 3. Delete this profile's budget entries (removes inverse refs before accounts go)
    let profileEntries = try context.fetch(FetchDescriptor<BudgetEntry>(predicate: #Predicate { $0.profileID == profileID }))
    for entry in profileEntries { context.delete(entry) }

    // 4. Delete this profile's accounts (cascade-deletes their MonthlyEntries)
    let profileAccounts = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.profileID == profileID }))
    for account in profileAccounts { context.delete(account) }

    // 5. Merge user categories (global — add new, keep existing)
    let existingCategories = try context.fetch(FetchDescriptor<UserBudgetCategory>())
    var categoryMap = Dictionary(uniqueKeysWithValues: existingCategories.map { ($0.id, $0) })
    for dto in backup.userBudgetCategories where categoryMap[dto.id] == nil {
        let cat = UserBudgetCategory(
            name: dto.name,
            symbolName: dto.symbolName,
            color: CategoryColor(rawValue: dto.colorNameRaw) ?? .blue,
            isIncome: dto.isIncome,
            isSavings: dto.isSavings ?? false,
            isInvestment: dto.isInvestment ?? false
        )
        cat.id = dto.id
        cat.createdAt = dto.createdAt
        if let g = dto.groupRaw { cat.groupRaw = g }
        context.insert(cat)
        categoryMap[dto.id] = cat
    }

    // 6. Upsert profile record (so the profile exists on a fresh install)
    let existingProfiles = try context.fetch(FetchDescriptor<UserProfile>())
    var profileMap = Dictionary(uniqueKeysWithValues: existingProfiles.map { ($0.id, $0) })
    for dto in backup.profiles ?? [] {
        if let existing = profileMap[dto.id] {
            existing.name = dto.name
            existing.emoji = dto.emoji
        } else {
            let p = UserProfile(name: dto.name, emoji: dto.emoji)
            p.id = dto.id
            p.createdAt = dto.createdAt
            context.insert(p)
            profileMap[dto.id] = p
        }
    }

    // 7. Restore accounts + their monthly entries
    var accountMap: [UUID: Account] = [:]
    for dto in backup.accounts {
        let account = Account(
            name: dto.name,
            type: AccountType(rawValue: dto.typeRaw) ?? .girokonto,
            balance: dto.balance,
            currency: dto.currency
        )
        account.id               = dto.id
        account.profileID        = profileID
        account.isVisible        = dto.isVisible
        account.createdAt        = dto.createdAt
        account.annualGrowthRate = dto.annualGrowthRate
        account.provider         = dto.provider ?? ""
        if let catId = dto.customAccountTypeId { account.customAccountType = customTypeMap[catId] }
        context.insert(account)
        accountMap[dto.id] = account

        for edto in dto.monthlyEntries {
            let entry = MonthlyEntry(label: edto.label, amount: edto.amount, isIncome: edto.isIncome)
            entry.id             = edto.id
            entry.intervalRaw    = edto.intervalRaw
            entry.dayOfMonth     = edto.dayOfMonth
            entry.transferGroupId = edto.transferGroupId
            entry.account        = account
            context.insert(entry)
        }
    }

    // 8. Restore budget entries
    for dto in backup.budgetEntries {
        let entry = BudgetEntry(
            category:   BudgetCategory(rawValue: dto.categoryRaw) ?? .groceries,
            amount:     dto.amount,
            recurrence: BudgetRecurrence(rawValue: dto.recurrenceRaw) ?? .monthly,
            dueDay:     dto.dueDay,
            dueDate:    dto.dueDate
        )
        entry.id              = dto.id
        entry.notes           = dto.notes
        entry.isActive        = dto.isActive
        entry.createdAt       = dto.createdAt
        entry.profileID       = profileID
        entry.currencyOverride = dto.currencyOverride
        if let aid = dto.accountId           { entry.account = accountMap[aid] }
        if let cid = dto.userCategoryId      { entry.userCategory = categoryMap[cid] }
        if let tid = dto.transferToAccountId { entry.transferToAccount = accountMap[tid] }
        context.insert(entry)
    }

    // 9. Restore financial goals
    for dto in backup.financialGoals ?? [] {
        let goal = FinancialGoal(
            profileID:    profileID,
            name:         dto.name,
            category:     GoalCategory(rawValue: dto.categoryRaw) ?? .custom,
            targetAmount: dto.targetAmount,
            currency:     dto.currency
        )
        goal.id        = dto.id
        goal.createdAt = dto.createdAt
        goal.priority  = dto.priority
        goal.isActive  = dto.isActive
        context.insert(goal)
    }

    try context.save()
}
