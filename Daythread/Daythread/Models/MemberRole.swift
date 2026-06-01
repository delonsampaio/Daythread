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
    /// Higher = more privileged. Used to ensure roles are never downgraded
    /// by a stale ownership check (admin=2 > editor=1 > viewer=0).
    nonisolated var privilege: Int {
        switch self { case .admin: return 2; case .editor: return 1; case .viewer: return 0 }
    }

    nonisolated var displayName: String {
        switch self {
        case .admin:  return "Admin"
        case .editor: return "Editor"
        case .viewer: return "Viewer"
        }
    }
}
