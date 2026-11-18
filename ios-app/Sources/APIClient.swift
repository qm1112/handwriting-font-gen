import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case badResponse(Int, String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务器地址无效"
        case .badResponse(let code, let message):
            return "服务器错误 (\(code)): \(message)"
        case .decodingError(let error):
            return "数据解析失败: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class APIClient: ObservableObject {
    private static let baseURLKey = "handwriting_font_gen_base_url"
    static let defaultBaseURL = "http://192.168.31.31/fontgen"

    @Published var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: Self.baseURLKey)
        }
    }

    private let session: URLSession

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.baseURLKey)
        self.baseURL = (saved?.isEmpty == false) ? saved! : Self.defaultBaseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: "\(trimmed)\(path)") else {
            throw APIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        return url
    }

    private func normalizedTag(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "default" : trimmed
    }

    func fetchCharsets() async throws -> CharsetsResponse {
        let url = try makeURL(path: "/api/charsets")
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)
        do {
            return try JSONDecoder().decode(CharsetsResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func fetchTags() async throws -> TagsResponse {
        let url = try makeURL(path: "/api/tags")
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)
        do {
            return try JSONDecoder().decode(TagsResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func fetchProgress(tag: String = "default") async throws -> ProgressResponse {
        let url = try makeURL(
            path: "/api/progress",
            queryItems: [URLQueryItem(name: "tag", value: normalizedTag(tag))]
        )
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)
        do {
            return try JSONDecoder().decode(ProgressResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func fetchChar(hex: String, tag: String = "default") async throws -> CharDetailResponse {
        let url = try makeURL(
            path: "/api/char/\(hex.uppercased())",
            queryItems: [URLQueryItem(name: "tag", value: normalizedTag(tag))]
        )
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)
        do {
            return try JSONDecoder().decode(CharDetailResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func saveChar(hex: String, strokesJson: [[StrokePointData]], mergedSvgPath: String, tag: String = "default") async throws {
        let url = try makeURL(
            path: "/api/char/\(hex.uppercased())",
            queryItems: [URLQueryItem(name: "tag", value: normalizedTag(tag))]
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = SaveCharRequest(strokesJson: strokesJson, mergedSvgPath: mergedSvgPath)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    func exportTTF(fontName: String, weight: String = "regular", tag: String = "default") async throws -> URL {
        let url = try makeURL(
            path: "/api/export/ttf",
            queryItems: [URLQueryItem(name: "tag", value: normalizedTag(tag))]
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let trimmedName = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "MyHandwriting" : trimmedName
        let payload = ExportTTFRequest(fontName: finalName, weight: weight)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let sanitized = finalName.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitized).ttf")
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.badResponse(http.statusCode, msg)
        }
    }
}
