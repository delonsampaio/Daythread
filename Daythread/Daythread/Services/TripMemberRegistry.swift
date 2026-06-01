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
        // Fetch by appleUserID alone (not `trip == %@`) to avoid the CoreData
        // cross-store join error that arises when a TripMember synced from the
        // CloudKit shared store and the Trip is in the private store. Filter to
        // the right trip in memory afterwards.
        let request = TripMember.fetchRequest()
        request.predicate = NSPredicate(format: "appleUserID == %@", appleUserID)

        let member = (try? context.fetch(request))?.first(where: { $0.trip?.objectID == trip.objectID }) ?? {
            let m = TripMember(context: context)
            m.id = UUID()
            m.appleUserID = appleUserID
            m.joinedAt = Date()
            m.trip = trip            // link before first save (zone-hopping rule)
            return m
        }()
        member.displayName = displayName
        // Never downgrade a role. syncParticipants may correctly assign .admin
        // and then registerMyMembership may overwrite with .editor when
        // fetchShares temporarily returns nil (e.g. during initial sync).
        // Highest privilege always wins.
        if role.privilege > member.role.privilege {
            member.role = role
        }
        return member
    }
}
