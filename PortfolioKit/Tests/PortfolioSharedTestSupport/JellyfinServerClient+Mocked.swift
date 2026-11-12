import PortfolioSharedJellyfinClient

extension ClientIdentity {
    /// Who the client under test says it is.
    public static let test = ClientIdentity(clientName: "Portfolio", version: "1.0", deviceName: "Apple TV", deviceID: "device-123")
}

extension JellyfinServerClient {
    /// A client whose requests go to `MockJellyfinServer` instances.
    public static let mocked = JellyfinServerClient(identity: .test, sessionConfiguration: { MockJellyfinServer.sessionConfiguration })
}
