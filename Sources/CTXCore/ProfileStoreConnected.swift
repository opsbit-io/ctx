import Foundation

extension ProfileStore {
    /// Every profile with a live session, not one per provider.
    ///
    /// One sign-in covers every account behind a portal, so several AWS profiles are
    /// commonly connected at once. Listing one per provider hid the rest and made a
    /// second account look disconnected while its credentials were valid.
    public var connectedProfiles: [CloudProfile] {
        profiles
            // Disconnect is a user-owned boundary. Hide the row as soon as that
            // intent is recorded, even if an older verification/discovery snapshot
            // still carries `.connected` for one render pass.
            .filter { $0.status == .connected && !manuallyDisconnectedProfiles.contains($0.id) }
            .sorted { ($0.provider.rawValue, $0.name) < ($1.provider.rawValue, $1.name) }
    }
}
