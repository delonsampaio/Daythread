//
//  TripMember.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import SwiftData

@Model
final class TripMember {
    var id: UUID
    var appleUserID: String          // CKRecord.ID.recordName
    var displayName: String
    var role: MemberRole
    @Attribute(.externalStorage) var avatarData: Data?
    var joinedAt: Date

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
