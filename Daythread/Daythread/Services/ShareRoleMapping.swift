//
//  ShareRoleMapping.swift
//  Daythread
//
//  Pure conversion between the app's MemberRole and CloudKit's
//  CKShare.ParticipantPermission. Used when creating a share (role → permission)
//  and when a participant joins a shared trip (permission → role).
//
//  Kept as a free enum so it can be unit-tested without any CloudKit container.
//

import CloudKit

enum ShareRoleMapping {
    /// Maps an app role to the CloudKit permission granted on the CKShare.
    /// Admins and editors can both write; viewers are read-only.
    nonisolated static func permission(for role: MemberRole) -> CKShare.ParticipantPermission {
        switch role {
        case .admin, .editor: return .readWrite
        case .viewer:         return .readOnly
        }
    }

    /// Maps a joining participant's CloudKit permission back to an app role.
    /// The share owner is always admin. Non-owners get editor (read-write) or
    /// viewer (read-only / unknown — defaulting to the least-privileged role).
    nonisolated static func role(
        forPermission permission: CKShare.ParticipantPermission,
        isOwner: Bool
    ) -> MemberRole {
        if isOwner { return .admin }
        switch permission {
        case .readWrite: return .editor
        case .readOnly:  return .viewer
        default:         return .viewer   // .none, .unknown → safest role
        }
    }
}
