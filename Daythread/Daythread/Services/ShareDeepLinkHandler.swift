//
//  ShareDeepLinkHandler.swift
//  Daythread
//
//  Pure logic for mapping an accepted CKShare record name back to the local
//  Trip model. Kept as a free enum (namespace) so it can be tested without
//  any CloudKit or SwiftData infrastructure.
//

import Foundation

enum ShareDeepLinkHandler {
    /// Returns the first trip whose cloudKitShareID matches `recordName`, or nil.
    static func trip(forShareRecordName recordName: String, in trips: [Trip]) -> Trip? {
        guard !recordName.isEmpty else { return nil }
        return trips.first { $0.cloudKitShareID == recordName }
    }
}
