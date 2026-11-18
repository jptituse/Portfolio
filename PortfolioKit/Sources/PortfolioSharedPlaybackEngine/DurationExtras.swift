extension Duration {
    /// The duration in seconds, with its fraction, as engines measure time.
    public var inSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
