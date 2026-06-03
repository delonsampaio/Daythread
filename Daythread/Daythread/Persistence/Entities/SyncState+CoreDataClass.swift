import Foundation
import CoreData

/// Local-only bookkeeping (NOT CloudKit-synced) for the custom shared-database
/// sync engine. One row per shared CKRecordZone, storing that zone's archived
/// CKServerChangeToken. Living inside shared.sqlite means wiping the store wipes
/// the tokens too — so the engine never thinks it's up to date against an empty DB.
@objc(SyncState)
public class SyncState: NSManagedObject {}
