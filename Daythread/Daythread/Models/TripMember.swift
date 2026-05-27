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
    var appleUserID: String = ""          // CKRecord.ID.recordName
    var displayName: String = ""
    var role: MemberRole = MemberRole.editor
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
