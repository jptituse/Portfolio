/// A profile: one user on one of the servers added to this device.
public struct ProfileID: Hashable, Sendable, Codable {
    public let serverID: MediaServer.ID
    public let userID: User.ID

    public init(serverID: MediaServer.ID, userID: User.ID) {
        self.serverID = serverID
        self.userID = userID
    }
}
