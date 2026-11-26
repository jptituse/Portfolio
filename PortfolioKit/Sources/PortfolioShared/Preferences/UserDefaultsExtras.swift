import Foundation

extension UserDefaults {
    /// The value saved for `key`, or `fallback` if nothing is saved there, or what is can't be read, such
    /// as a choice a later version removed.
    func decoded<Value: Decodable>(_ type: Value.Type = Value.self, forKey key: String, or fallback: Value) -> Value {
        guard let data = data(forKey: key), let value = try? JSONDecoder().decode(Value.self, from: data) else {
            return fallback
        }
        return value
    }

    /// Saves `value` for `key`, as JSON, so any `Codable` value can be kept, optionals included.
    func setEncoded<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, forKey: key)
    }
}
