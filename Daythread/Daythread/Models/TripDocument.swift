//
//  TripDocument.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import Foundation
import SwiftData

@Model
final class TripDocument {
    var id: UUID
    var title: String
    @Attribute(.externalStorage) var documentData: Data   // PDF or JPEG bytes — stored on filesystem, not SQLite
    var mimeType: String                                  // "application/pdf" or "image/jpeg"
    var expiryDate: Date?                                 // for passports, visas — drives expiry warning badge
    var addedAt: Date

    var trip: Trip?

    init(
        id: UUID = UUID(),
        title: String,
        documentData: Data,
        mimeType: String,
        expiryDate: Date? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.documentData = documentData
        self.mimeType = mimeType
        self.expiryDate = expiryDate
        self.addedAt = addedAt
    }
}
