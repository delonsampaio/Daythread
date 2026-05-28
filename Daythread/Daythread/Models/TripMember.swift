//
//  TripMember.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//
//  CloudKit compliance: inline property defaults on all non-optional stored properties.
//

import Foundation
import SwiftData

@Model
final class TripMember {
    var id: UUID = UUID()
    /// CKRecord.ID.recordName for real co-editors; empty string for virtual/shadow members.
    /// Virtual members exist only for expense splitting — they have no iCloud account yet.
    /// When a real user joins via CloudKit, set their appleUserID to link the accounts.
    var appleUserID: String = ""
    var displayName: String = ""
    var role: MemberRole = MemberRole.editor

    /// True when this member was added manually for expense splitting
    /// and has not yet been linked to a real iCloud account.
    var isVirtual: Bool { appleUserID.isEmpty }
    @Attribute(.externalStorage) var avatarData: Data?
    var joinedAt: Date = Date.now

    var trip: Trip?

    init(
        id: UUID = UUID(),
        appleUserID: String,
        displayName: String,
        role: MemberRole = .editor,
        avatarData: Data? = nil,
        joinedAt: Date = Date()
    ) {
        self.id = id
        self.appleUserID = appleUserID
        self.displayName = displayName
        self.role = role
        self.avatarData = avatarData
        self.joinedAt = joinedAt
    }
}
