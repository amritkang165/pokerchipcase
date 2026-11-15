/// 4-digit table code; the TLS key is derived from it.
public struct TableCode: Hashable, Codable, Sendable {
    /// The four digits, as a string.
    public let digits: String

    /// Returns nil unless `digits` is exactly four ASCII digits.
    public init?(_ digits: String) {
        guard digits.count == 4, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        self.digits = digits
    }

    /// A random code from 0000 to 9999.
    public static func random() -> TableCode {
        TableCode(String(format: "%04d", Int.random(in: 0...9999)))!
    }
}
