import Foundation
import CoreData

/// A throwaway record in the PRIVATE store used purely to wake NSPersistentCloudKitContainer's
/// mirroring delegate. When a CloudKit silent push arrives, bumping this record's timestamp
/// creates a pending private-store export; the mirroring delegate spins up to handle it and,
/// in doing so, flushes the stalled SHARED-database imports it would otherwise defer until the
/// next cold launch. See PersistenceController.pokeSyncPing().
@objc(SyncPing)
public class SyncPing: NSManagedObject {}
