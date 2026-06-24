import Foundation

/// JSON encoders/decoders configured for Azure DevOps payloads.
///
/// Azure DevOps emits ISO-8601 timestamps that *sometimes* carry fractional
/// seconds (e.g. `2026-06-20T09:15:00.123Z`) and sometimes do not
/// (`2026-06-20T09:15:00Z`). `JSONDecoder.dateDecodingStrategy = .iso8601`
/// rejects the fractional form, so we parse defensively.
enum JSONCoding {
    /// Parses an Azure DevOps timestamp, tolerating presence or absence of
    /// fractional seconds. Formatters are created locally to stay `Sendable`-safe.
    static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parseDate(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognized date format: \(raw)"
                )
            }
            return date
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
