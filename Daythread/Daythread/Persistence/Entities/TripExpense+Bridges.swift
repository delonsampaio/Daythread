import Foundation

extension TripExpense {
    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// Newline-joined storage (CloudKit can't store arrays/transformables).
    var splitAmongStringIDs: [String] {
        get { splitAmongJoined.split(separator: "\n").map(String.init) }
        set { splitAmongJoined = newValue.joined(separator: "\n") }
    }

    var splitAmongIDs: [UUID] {
        get { splitAmongStringIDs.compactMap { UUID(uuidString: $0) } }
        set { splitAmongStringIDs = newValue.map(\.uuidString) }
    }
}
