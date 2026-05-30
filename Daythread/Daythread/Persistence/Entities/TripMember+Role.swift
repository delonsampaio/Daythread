import Foundation

extension TripMember {
    var role: MemberRole {
        get { MemberRole(rawValue: roleRaw) ?? .editor }
        set { roleRaw = newValue.rawValue }
    }

    /// True when added manually for expense splitting (no linked iCloud account).
    var isVirtual: Bool { appleUserID.isEmpty }
}
