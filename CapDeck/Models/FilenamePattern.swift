import Foundation

enum FilenamePatternError: LocalizedError, Equatable {
    case empty
    case invalidCharacter(Character)
    case unsupportedToken(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            "Filename pattern cannot be empty."
        case let .invalidCharacter(character):
            "Filename pattern cannot contain ‘\(character)’ characters."
        case let .unsupportedToken(token):
            "Unsupported filename token: {\(token)}."
        }
    }
}

enum FilenamePattern {
    static let defaultValue = "CapDeck-{date}-{time}"
    static let supportedTokens = ["date", "time", "timestamp"]

    static func validate(_ pattern: String) -> FilenamePatternError? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        for character in ["/", ":"] where trimmed.contains(character) {
            return .invalidCharacter(Character(character))
        }

        let tokenExpression = try? NSRegularExpression(pattern: #"\{([^{}]+)\}"#)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for match in tokenExpression?.matches(in: trimmed, range: range) ?? [] {
            guard
                let tokenRange = Range(match.range(at: 1), in: trimmed)
            else { continue }
            let token = String(trimmed[tokenRange])
            if !supportedTokens.contains(token) {
                return .unsupportedToken(token)
            }
        }

        let removingSupportedTokens = supportedTokens.reduce(trimmed) {
            $0.replacingOccurrences(of: "{\($1)}", with: "")
        }
        if removingSupportedTokens.contains("{") || removingSupportedTokens.contains("}") {
            return .unsupportedToken("invalid")
        }
        return nil
    }

    static func render(_ pattern: String, date: Date) throws -> String {
        if let error = validate(pattern) { throw error }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)

        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateValue = dateFormatter.string(from: date)
        dateFormatter.dateFormat = "HH-mm-ss"
        let timeValue = dateFormatter.string(from: date)
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestampValue = dateFormatter.string(from: date)

        return
            pattern
            .replacingOccurrences(of: "{date}", with: dateValue)
            .replacingOccurrences(of: "{time}", with: timeValue)
            .replacingOccurrences(of: "{timestamp}", with: timestampValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
