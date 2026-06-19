import Foundation
import SwiftData

@Model
final class ImportedTransaction {
    var id: UUID = UUID()
    var date: Date = Date()
    var transactionDescription: String = ""
    var rawAmount: Double = 0.0
    var valueDate: Date = Date()
    var categoryRaw: String = TransactionCategory.sonstiges.rawValue
    var merchantName: String = ""
    var bankFormatRaw: String = ""
    var importedAt: Date = Date()
    var profileID: String = ""
    var importBatchID: String = ""
    var currencyCode: String = "CHF"

    /// When set, this transaction is assigned to a user-created custom category
    /// instead of one of the built-in TransactionCategory cases.
    var customCategoryID: String? = nil

    /// Free-text note the user can attach; also matched against categorization rules.
    var userNote: String = ""

    var account: Account?

    var category: TransactionCategory {
        get {
            if let cat = TransactionCategory(rawValue: categoryRaw) { return cat }
            // Legacy rawValue migrations
            switch categoryRaw {
            case "Restaurant & Café": return .restaurant
            default: return .sonstiges
            }
        }
        set {
            categoryRaw = newValue.rawValue
            customCategoryID = nil   // clear custom assignment when a built-in is chosen
        }
    }

    var isExpense: Bool { rawAmount < 0 }
    var isIncome:  Bool { rawAmount > 0 }
    var amount:    Double { Swift.abs(rawAmount) }

    init(from tx: BankTransaction, bank: BankFormat, profileID: String, batchID: String = "") {
        self.date = tx.date
        self.transactionDescription = tx.description
        self.rawAmount = tx.rawAmount
        self.valueDate = tx.valueDate
        self.categoryRaw = tx.category.rawValue
        self.merchantName = tx.merchantName
        self.bankFormatRaw = bank.rawValue
        self.importedAt = Date()
        self.profileID = profileID
        self.importBatchID = batchID
        self.currencyCode = tx.currencyCode
    }

    func toBankTransaction() -> BankTransaction {
        BankTransaction(
            date: date,
            description: transactionDescription,
            rawAmount: rawAmount,
            valueDate: valueDate,
            category: category,
            merchantName: merchantName
        )
    }
}
