import Foundation

public enum SessionTitleValidationError: LocalizedError, Equatable {
    case empty
    case multipleLinesOrControls
    case tooLong

    public var errorDescription: String? {
        switch self {
        case .empty: return "请输入标题"
        case .multipleLinesOrControls: return "标题只能为单行，不能包含换行或控制字符"
        case .tooLong: return "标题最多 \(SessionTitleEditor.maximumLength) 个字符"
        }
    }
}

public enum SessionTitleEditor {
    public static let maximumLength = 100

    public static func normalizedTitle(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw SessionTitleValidationError.empty }
        // Do not reject format scalars such as the zero-width joiner in emoji.
        guard !value.unicodeScalars.contains(where: {
            $0.properties.generalCategory == .control || CharacterSet.newlines.contains($0)
        }) else { throw SessionTitleValidationError.multipleLinesOrControls }
        guard value.count <= maximumLength else { throw SessionTitleValidationError.tooLong }
        return value
    }
}
