import Foundation

public enum VerticalTitleSegment: Equatable, Sendable {
    case latin(String)
    case han(Character)
    case gap
}

public struct VerticalTitleLayout: Equatable, Sendable {
    public let visibleSegments: [VerticalTitleSegment]
    public let showsEllipsis: Bool

    public init(visibleSegments: [VerticalTitleSegment], showsEllipsis: Bool) {
        self.visibleSegments = visibleSegments
        self.showsEllipsis = showsEllipsis
    }
}

public enum VerticalTitleParser {
    public static func segments(for title: String) -> [VerticalTitleSegment] {
        let characters = Array(title)
        var result: [VerticalTitleSegment] = []
        var latin = ""
        var previousKind: Kind?
        var pendingSeparator = false

        func flushLatin() {
            guard !latin.isEmpty else { return }
            result.append(.latin(latin))
            latin = ""
            previousKind = .latin
        }
        func appendGapIfNeeded(before kind: Kind) {
            if pendingSeparator {
                if !(previousKind == .han && kind == .han) { appendGap(&result) }
                pendingSeparator = false
            } else if previousKind != nil, previousKind != kind {
                appendGap(&result)
            }
        }

        for index in characters.indices {
            let character = characters[index]
            if isHan(character) {
                flushLatin()
                appendGapIfNeeded(before: .han)
                result.append(.han(character))
                previousKind = .han
                continue
            }
            if isLatinBody(character) || isAllowedConnector(character, in: characters, at: index) {
                if latin.isEmpty { appendGapIfNeeded(before: .latin) }
                latin.append(character)
                continue
            }
            if character.isWhitespace,
               hasLatinBodyBefore(characters, index: index),
               hasLatinBodyAfter(characters, index: index) {
                if !latin.hasSuffix(" ") { latin.append(" ") }
                continue
            }

            flushLatin()
            pendingSeparator = true
        }
        flushLatin()
        while result.last == .gap { result.removeLast() }
        return result
    }

    private enum Kind { case latin, han }

    private static func appendGap(_ result: inout [VerticalTitleSegment]) {
        if result.last != .gap, !result.isEmpty { result.append(.gap) }
    }

    private static func isAllowedConnector(_ character: Character, in characters: [Character], at index: Int) -> Bool {
        guard character == "_" || character == "-" || character == "." else { return false }
        guard index > characters.startIndex, index < characters.index(before: characters.endIndex) else { return false }
        return isLatinBody(characters[characters.index(before: index)])
            && isLatinBody(characters[characters.index(after: index)])
    }

    private static func hasLatinBodyBefore(_ characters: [Character], index: Int) -> Bool {
        var cursor = index
        while cursor > characters.startIndex {
            cursor = characters.index(before: cursor)
            if !characters[cursor].isWhitespace { return isLatinBody(characters[cursor]) }
        }
        return false
    }

    private static func hasLatinBodyAfter(_ characters: [Character], index: Int) -> Bool {
        var cursor = characters.index(after: index)
        while cursor < characters.endIndex {
            if !characters[cursor].isWhitespace { return isLatinBody(characters[cursor]) }
            cursor = characters.index(after: cursor)
        }
        return false
    }

    private static func isLatinBody(_ character: Character) -> Bool {
        guard !isHan(character) else { return false }
        let scalars = character.unicodeScalars
        guard scalars.contains(where: { $0.properties.isAlphabetic || $0.properties.numericType != nil }) else { return false }
        return scalars.allSatisfy { scalar in
            scalar.properties.isAlphabetic
                || scalar.properties.numericType != nil
                || scalar.properties.generalCategory == .nonspacingMark
                || scalar.properties.generalCategory == .spacingMark
                || scalar.properties.generalCategory == .enclosingMark
        }
    }

    private static func isHan(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F, 0x30000...0x3134F:
                true
            default:
                false
            }
        }
    }
}

public enum VerticalTitleMeasurer {
    public static func layout(
        segments: [VerticalTitleSegment],
        maximumLength: Double,
        ellipsisAdvance: Double,
        advance: (VerticalTitleSegment) -> Double
    ) -> VerticalTitleLayout {
        let total = segments.reduce(0) { $0 + advance($1) }
        guard total > maximumLength else { return VerticalTitleLayout(visibleSegments: segments, showsEllipsis: false) }

        let budget = max(0, maximumLength - ellipsisAdvance)
        var visible: [VerticalTitleSegment] = []
        var used = 0.0
        for segment in segments {
            let length = advance(segment)
            if used + length <= budget {
                visible.append(segment)
                used += length
                continue
            }
            if case let .latin(text) = segment {
                let prefix = longestLatinPrefix(text, remaining: budget - used, advance: advance)
                if !prefix.isEmpty { visible.append(.latin(prefix)) }
            }
            break
        }
        while visible.last == .gap { visible.removeLast() }
        return VerticalTitleLayout(visibleSegments: visible, showsEllipsis: true)
    }

    private static func longestLatinPrefix(
        _ text: String,
        remaining: Double,
        advance: (VerticalTitleSegment) -> Double
    ) -> String {
        var prefix = ""
        for character in text {
            let candidate = prefix + String(character)
            if advance(.latin(candidate)) > remaining { break }
            prefix = candidate
        }
        while let last = prefix.last, last == " " || last == "_" || last == "-" || last == "." {
            prefix.removeLast()
        }
        return prefix
    }
}
