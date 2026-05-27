//
//  MemberRole.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

enum MemberRole: String, Codable, CaseIterable {
    case admin, editor, viewer

    nonisolated var canEdit: Bool { self != .viewer }
    nonisolated var isAdmin: Bool { self == .admin }

    nonisolated var displayName: String {
        switch self {
        case .admin:  return "Admin"
        case .editor: return "Editor"
        case .viewer: return "Viewer"
        }
    }
}
