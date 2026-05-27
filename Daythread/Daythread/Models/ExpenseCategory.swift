//
//  ExpenseCategory.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

enum ExpenseCategory: String, Codable, CaseIterable {
    case food, transport, lodging, activity, shopping, other

    nonisolated var displayName: String {
        switch self {
        case .food:      return "Food & Drink"
        case .transport: return "Transport"
        case .lodging:   return "Lodging"
        case .activity:  return "Activity"
        case .shopping:  return "Shopping"
        case .other:     return "Other"
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .food:      return "fork.knife"
        case .transport: return "car.fill"
        case .lodging:   return "bed.double.fill"
        case .activity:  return "figure.walk"
        case .shopping:  return "bag.fill"
        case .other:     return "ellipsis.circle.fill"
        }
    }
}
