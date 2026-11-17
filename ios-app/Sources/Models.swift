import Foundation

enum CharsetCategory: String, CaseIterable, Identifiable, Codable {
    case basic50 = "basic_50"
    case level1_3500 = "level1_3500"
    case gb2312Ext = "gb2312_ext"
    case punctAscii = "punct_ascii"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .basic50: return "基础 50 字"
        case .level1_3500: return "一级字库 3500"
        case .gb2312Ext: return "GB2312 扩展"
        case .punctAscii: return "标点与 ASCII"
        }
    }
}

struct CharsetItem: Codable, Identifiable, Hashable {
    let unicodeHex: String
    let char: String

    var id: String { unicodeHex }

    enum CodingKeys: String, CodingKey {
        case unicodeHex = "unicode_hex"
        case char
    }
}

struct CharsetInfo: Codable {
    let count: Int
}

struct CharsetsResponse: Codable {
    let info: [String: CharsetInfo]
    let charsets: [String: [CharsetItem]]
}

struct GroupProgress: Codable {
    let total: Int
    let completed: Int
    let percentage: Double
}

struct CharItem: Codable, Identifiable, Hashable {
    let unicodeHex: String
    let char: String
    let category: String
    var status: String
    let updatedAt: String?

    var id: String { unicodeHex }
    var isCompleted: Bool { status == "completed" }

    enum CodingKeys: String, CodingKey {
        case unicodeHex = "unicode_hex"
        case char
        case category
        case status
        case updatedAt = "updated_at"
    }
}

struct ProgressResponse: Codable {
    let groups: [String: GroupProgress]
    let characters: [CharItem]
}

struct SaveCharRequest: Codable {
    let strokesJson: [[StrokePointData]]
    let mergedSvgPath: String

    enum CodingKeys: String, CodingKey {
        case strokesJson = "strokes_json"
        case mergedSvgPath = "merged_svg_path"
    }
}

struct StrokePointData: Codable {
    let x: Double
    let y: Double
    let w: Double
}

struct SaveCharResponse: Codable {
    let status: String?
    let unicodeHex: String?

    enum CodingKeys: String, CodingKey {
        case status
        case unicodeHex = "unicode_hex"
    }
}
