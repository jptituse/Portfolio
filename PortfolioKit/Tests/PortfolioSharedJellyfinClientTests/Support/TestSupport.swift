import Foundation
import Testing

/// Real server responses, for testing how SDK types map to `PortfolioShared` models.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        let decoder = JSONDecoder()
        // Dates as Jellyfin sends them, with or without fractions of a second, as the SDK reads them.
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            return try Date(string, strategy: .iso8601)
        }
        return try decoder.decode(type, from: data(name))
    }
}
