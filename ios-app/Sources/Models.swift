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

struct ExportTTFRequest: Codable {
    let fontName: String
    let weight: String

    enum CodingKeys: String, CodingKey {
        case fontName = "font_name"
        case weight
    }
}

struct TagItem: Codable, Identifiable, Hashable {
    let tag: String
    let completed: Int

    var id: String { tag }
}

struct TagsResponse: Codable {
    let tags: [TagItem]
}

struct CharDetailResponse: Codable {
    let unicodeHex: String?
    let char: String?
    let status: String?
    let strokesJson: [[StrokePointData]]?
    let mergedSvgPath: String?

    enum CodingKeys: String, CodingKey {
        case unicodeHex = "unicode_hex"
        case char
        case status
        case strokesJson = "strokes_json"
        case mergedSvgPath = "merged_svg_path"
    }
}

enum ReferenceFontOption: String, CaseIterable, Identifiable {
    case system = "system"
    case kaiti = "Kaiti SC"
    case songti = "Songti SC"
    case heiti = "Heiti SC"
    case pingfang = "PingFang SC"
    case maShanZheng = "MaShanZheng-Regular"
    case longCang = "LongCang-Regular"
    case yuanti = "Yuanti SC"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "系统默认"
        case .kaiti: return "楷体 (Kaiti SC)"
        case .songti: return "宋体 (Songti SC)"
        case .heiti: return "黑体 (Heiti SC)"
        case .pingfang: return "苹方 (PingFang SC)"
        case .maShanZheng: return "毛笔楷书"
        case .longCang: return "行草手写"
        case .yuanti: return "圆体"
        }
    }
}
