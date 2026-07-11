import Foundation

struct SupabaseRESTClient: Sendable {
    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    enum ClientError: LocalizedError {
        case invalidResponse
        case requestFailed(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Supabase returned an invalid response."
            case .requestFailed(let statusCode, let message):
                return "Supabase request failed (\(statusCode)): \(message)"
            }
        }
    }

    let config: SupabaseConfig
    var accessToken: String?

    func authRequest<Response: Decodable>(
        path: String,
        method: Method = .get,
        body: Encodable? = nil,
        responseType: Response.Type = Response.self
    ) async throws -> Response {
        try await request(basePath: "auth/v1", path: path, method: method, body: body, responseType: responseType)
    }

    func restRequest<Response: Decodable>(
        path: String,
        method: Method = .get,
        body: Encodable? = nil,
        preferRepresentation: Bool = false,
        responseType: Response.Type = Response.self
    ) async throws -> Response {
        try await request(
            basePath: "rest/v1",
            path: path,
            method: method,
            body: body,
            preferRepresentation: preferRepresentation,
            responseType: responseType
        )
    }

    private func request<Response: Decodable>(
        basePath: String,
        path: String,
        method: Method,
        body: Encodable?,
        preferRepresentation: Bool = false,
        responseType: Response.Type
    ) async throws -> Response {
        guard let url = URL(string: "\(basePath)/\(path)", relativeTo: config.projectURL)?.absoluteURL else {
            throw ClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var preferValues = [preferRepresentation ? "return=representation" : "return=minimal"]
        if method == .post, path.contains("on_conflict=") {
            preferValues.append("resolution=merge-duplicates")
        }
        request.setValue(preferValues.joined(separator: ","), forHTTPHeaderField: "Prefer")

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONEncoder.supabase.encode(AnyEncodable(body))
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw ClientError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8) ?? "Unknown error"
            )
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        return try JSONDecoder.supabase.decode(Response.self, from: data)
    }
}

struct EmptyResponse: Codable, Sendable {}

private struct AnyEncodable: Encodable {
    private let encodeBody: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        encodeBody = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeBody(encoder)
    }
}

extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
