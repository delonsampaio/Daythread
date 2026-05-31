//
//  TripMemberRegistry.swift
//  Daythread
//
//  Registers the current iCloud user as a real (non-virtual) member of a trip,
//  so co-editors see real names + roles in Group Sync regardless of whether they
//  have each other saved in Contacts (Apple's UICloudSharingController only
//  resolves names via Contacts, otherwise showing the generic "Owner"/role).
//
//  The member record syncs through CloudKit's shared store, so once each person
//  has opened Group Sync once, everyone sees the full named roster.
//

import CoreData

enum TripMemberRegistry {

    /// Creates or updates the current user's membership on `trip`. Matched by
    /// `appleUserID` (the CloudKit user record name) so it never duplicates
    /// across launches or devices. Never matches virtual expense-only members,
    /// which carry an empty appleUserID.
    @discardableResult
    static func upsertCurrentUser(
        in trip: Trip,
        appleUserID: String,
        displayName: String,
        role: MemberRole,
        context: NSManagedObjectContext
    ) -> TripMember {
        let member = trip.membersArray.first {
            !$0.appleUserID.isEmpty && $0.appleUserID == appleUserID
        } ?? {
            let m = TripMember(context: context)
            m.id = UUID()
            m.appleUserID = appleUserID
            m.joinedAt = Date()
            m.trip = trip            // link before first save (zone-hopping rule)
            return m
        }()
        member.displayName = displayName
        member.role = role
        return member
    }
}
