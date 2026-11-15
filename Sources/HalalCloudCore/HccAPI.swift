//
//  HccAPI.swift
//  HalalCloudCore
//
//  Transport layer for the Halal Cloud Open API.
//

import Foundation

/// gRPC-style status codes used by the Halal Cloud Open API.
public enum HccStatus: Int, Sendable {
    case ok = 0
    case cancelled = 1
    case unknown = 2
    case invalidArgument = 3
    case deadlineExceeded = 4
    case notFound = 5
    case alreadyExists = 6
    case permissionDenied = 7
    case resourceExhausted = 8
    case failedPrecondition = 9
    case aborted = 10
    case outOfRange = 11
    case unimplemented = 12
    case internalError = 13
    case unavailable = 14
    case dataLoss = 15
    case unauthenticated = 16

    public init(httpStatusCode: Int) {
        switch httpStatusCode {
        case 200: self = .ok
        case 499: self = .cancelled
        case 500: self = .unknown
        case 400: self = .invalidArgument
        case 504: self = .deadlineExceeded
        case 404: self = .notFound
        case 409: self = .alreadyExists
        case 403: self = .permissionDenied
        case 429: self = .resourceExhausted
        case 401: self = .unauthenticated
        case 501: self = .unimplemented
        case 503: self = .unavailable
        default: self = .internalError
        }
    }

    public var localizedDescription: String {
        switch self {
        case .ok: return "OK"
        case .cancelled: return "The request was cancelled."
        case .unknown: return "The server returned an unknown error."
        case .invalidArgument: return "The request was rejected as invalid."
        case .deadlineExceeded: return "The request timed out."
        case .notFound: return "The item was not found."
        case .alreadyExists: return "The item already exists."
        case .permissionDenied: return "You do not have permission to do that."
        case .resourceExhausted: return "You have run out of quota or hit a rate limit."
        case .failedPrecondition: return "The server is not in a state that allows this operation."
        case .aborted: return "The operation was aborted."
        case .outOfRange: return "The request went past the valid range."
        case .unimplemented: return "This operation is not supported by the server."
        case .internalError: return "The server reported an internal error."
        case .unavailable: return "The service is currently unavailable."
        case .dataLoss: return "The server reported data loss."
        case .unauthenticated: return "Your session has expired. Please sign in again."
        }
    }
}

public struct HccError: LocalizedError, Sendable {
    public let status: HccStatus
    public let path: String
    public let detail: String

    public init(status: HccStatus, path: String, detail: String) {
        self.status = status
        self.path = path
        self.detail = detail
    }

    public var errorDescription: String? {
        if detail.isEmpty {
            return status.localizedDescription
        }
        return "\(status.localizedDescription)\n\n\(detail)"
    }
}

/// Posts JSON requests to `openapi.2dland.cn` with HL6 signatures applied.
public final class HccAPIClient {

    public let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 300
            configuration.httpMaximumConnectionsPerHost = 8
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    private func url(for path: String) -> URL? {
        URL(string: "https://\(HccSigner.host)\(path)")
    }

    @discardableResult
    public func post(path: String, accessToken: String, body: Data) async throws -> Data {
        guard let url = url(for: path) else {
            throw HccError(status: .invalidArgument, path: path, detail: "Malformed API path.")
        }

        let signature = HccSigner.sign(path: path, body: body, accessToken: accessToken)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 60
        for (name, value) in signature.httpHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HccError(
                status: .unavailable,
                path: path,
                detail: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw HccError(status: .unknown, path: path, detail: "The server response was not HTTP.")
        }

        guard http.statusCode == 200 else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw HccError(
                status: HccStatus(httpStatusCode: http.statusCode),
                path: path,
                detail: snippet.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return data
    }

    @discardableResult
    public func post(path: String, accessToken: String, json: [String: Any]) async throws -> Data {
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: json, options: [])
        } catch {
            throw HccError(status: .invalidArgument, path: path, detail: error.localizedDescription)
        }
        return try await post(path: path, accessToken: accessToken, body: body)
    }
}
