//
//  HalalCloudService.swift
//  HalalCloudCore
//
//  High level client: OAuth sign-in, account details, file listing and
//  downloads.
//

import Foundation

public actor HalalCloudService {

    public enum Endpoint {
        public static let authorize = "/v6/oauth/authorize"
        public static let authorizeState = "/v6/oauth/get_authorize_state"
        public static let token = "/v6/oauth/get_token"
        public static let refreshToken = "/v6/oauth/refresh_token"
        public static let logoff = "/v6/user/logoff"
        public static let user = "/v6/user/get"
        public static let quota = "/v6/user/get_statistics_and_quota"
        public static let fileGet = "/v6/userfile/get"
        public static let fileList = "/v6/userfile/list"
        public static let fileCreate = "/v6/userfile/create"
        public static let parseFileSlice = "/v6/userfile/parse_file_slice"
        public static let sliceDownloadAddress = "/v6/userfile/get_slice_download_address"
        public static let recentUpdatedFiles = "/v6/userfile/list_recent_updated_files"
    }

    private let api: HccAPIClient
    private let profile: ProfileStore
    private let store: BlockStore
    private var credentials: Credentials?

    public init(
        api: HccAPIClient = HccAPIClient(),
        profile: ProfileStore = .default,
        store: BlockStore = BlockStore()
    ) {
        self.api = api
        self.profile = profile
        self.store = store
    }

    public func hasSession() -> Bool {
        credentials?.isValid ?? false
    }

    // MARK: - Transport

    private func encode(_ object: [String: Any]) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [])
        } catch {
            throw HccError(status: .invalidArgument, path: "", detail: error.localizedDescription)
        }
    }

    private func json(_ data: Data) throws -> JNode {
        guard !data.isEmpty else { return JNode(nil) }
        do {
            return try JNode.parse(data)
        } catch {
            throw HccError(status: .unknown, path: "", detail: "The server response was not valid JSON.")
        }
    }

    private func rawRequest(path: String, body: Data) async throws -> Data {
        if let token = credentials?.accessToken, !token.isEmpty {
            do {
                return try await api.post(path: path, accessToken: token, body: body)
            } catch let error as HccError where error.status == .unauthenticated {
                try await refreshCredentials()
                guard let refreshed = credentials?.accessToken, !refreshed.isEmpty else {
                    throw error
                }
                return try await api.post(path: path, accessToken: refreshed, body: body)
            }
        }
        return try await api.post(
            path: path,
            accessToken: HccSigner.anonymousAccessToken,
            body: body)
    }

    private func request(path: String, body: [String: Any] = [:]) async throws -> JNode {
        let payload = try encode(body)
        let data = try await rawRequest(path: path, body: payload)
        return try json(data)
    }

    /// Sends a request with the anonymous access token. Token endpoints must
    /// never go through `rawRequest`, otherwise an expired access token would
    /// trigger a refresh loop.
    private func anonymousRequest(path: String, body: [String: Any]) async throws -> JNode {
        let payload = try encode(body)
        let data = try await api.post(
            path: path,
            accessToken: HccSigner.anonymousAccessToken,
            body: payload)
        return try json(data)
    }

    // MARK: - Session

    /// Restores a saved session by exchanging the stored refresh token.
    public func restoreSession() async -> Bool {
        guard let saved = profile.loadRefreshToken(), !saved.isEmpty else {
            credentials = nil
            return false
        }
        credentials = Credentials(accessToken: "", refreshToken: saved)
        do {
            try await refreshCredentials()
            return credentials?.isValid ?? false
        } catch {
            credentials = nil
            return false
        }
    }

    private func refreshCredentials() async throws {
        guard let current = credentials, !current.refreshToken.isEmpty else {
            throw HccError(
                status: .unauthenticated,
                path: Endpoint.refreshToken,
                detail: "No refresh token is available.")
        }
        let response = try await anonymousRequest(
            path: Endpoint.refreshToken,
            body: ["refresh_token": current.refreshToken])
        let accessToken = response.object("access_token").string
        let refreshToken = response.object("refresh_token").string
        guard !accessToken.isEmpty else {
            throw HccError(
                status: .unauthenticated,
                path: Endpoint.refreshToken,
                detail: "The server did not return an access token.")
        }
        let updated = Credentials(
            accessToken: accessToken,
            refreshToken: refreshToken.isEmpty ? current.refreshToken : refreshToken)
        credentials = updated
        profile.save(refreshToken: updated.refreshToken)
    }

    /// Starts the QR-code / link based sign-in flow (PKCE + legacy mode).
    public func startAuthorization() async throws -> AuthorizationRequest {
        let codeVerifier = HccCrypto.base64URL(HccCrypto.randomBytes(32))
        let codeChallenge = HccCrypto.base64URL(HccCrypto.sha256(Data(codeVerifier.utf8)))
        let response = try await anonymousRequest(
            path: Endpoint.authorize,
            body: [
                "client_id": HccSigner.secretID,
                "code_challenge": codeChallenge,
                "code_challenge_method": "S256",
                "legacy": true
            ])
        let code = response.object("code").string
        let redirectURI = response.object("redirect_uri").string
        guard !code.isEmpty, !redirectURI.isEmpty else {
            throw HccError(
                status: .unknown,
                path: Endpoint.authorize,
                detail: "The server did not return a sign-in code and link.")
        }
        return AuthorizationRequest(
            code: code,
            redirectURI: redirectURI,
            codeVerifier: codeVerifier)
    }

    public func authorizationState(code: String) async throws -> AuthorizeState {
        let response = try await anonymousRequest(
            path: Endpoint.authorizeState,
            body: ["code": code])
        let status = response.object("status").string
        if let state = AuthorizeState(rawValue: status) {
            return state
        }
        return .failed
    }

    public func finishAuthorization(_ request: AuthorizationRequest) async throws {
        let response = try await self.anonymousRequest(
            path: Endpoint.token,
            body: [
                "code": request.code,
                "code_verifier": request.codeVerifier
            ])
        let accessToken = response.object("access_token").string
        let refreshToken = response.object("refresh_token").string
        guard !accessToken.isEmpty, !refreshToken.isEmpty else {
            throw HccError(
                status: .unauthenticated,
                path: Endpoint.token,
                detail: "The server did not return a complete token pair.")
        }
        let updated = Credentials(accessToken: accessToken, refreshToken: refreshToken)
        credentials = updated
        profile.save(refreshToken: refreshToken)
    }

    public func signOut() async {
        if let current = credentials {
            _ = try? await request(
                path: Endpoint.logoff,
                body: [
                    "access_token": current.accessToken,
                    "refresh_token": current.refreshToken
                ])
        }
        credentials = nil
        profile.clear()
    }

    // MARK: - Account

    public func currentUser() async throws -> UserInformation {
        let response = try await request(path: Endpoint.user)
        let icon = response.object("icon").string
        return UserInformation(
            identity: response.object("identity").string,
            name: response.object("name").string,
            iconURL: icon.isEmpty ? nil : URL(string: icon))
    }

    public func statistics() async throws -> UserStatistics {
        let response = try await request(path: Endpoint.quota)
        let quota = response.object("disk_statistics_quota")
        return UserStatistics(
            bytesQuota: quota.object("bytes_quota").int64,
            bytesUsed: quota.object("bytes_used").int64)
    }

    // MARK: - Files

    public func list(path: String) async throws -> [CloudFile] {
        var files: [CloudFile] = []
        var token = ""
        var seenTokens = Set<String>()

        for _ in 0..<10_000 {
            let response = try await request(
                path: Endpoint.fileList,
                body: [
                    "parent": ["path": path],
                    "list_info": ["token": token]
                ])
            token = response.object("list_info").object("token").string
            for item in response.array("files") {
                files.append(CloudFile(json: item, parentPath: path))
            }
            if token.isEmpty || seenTokens.contains(token) {
                break
            }
            seenTokens.insert(token)
        }
        return files
    }

    public func fileInformation(path: String) async throws -> CloudFile {
        let response = try await request(
            path: Endpoint.fileGet,
            body: ["path": path])
        return CloudFile(json: response, parentPath: Support.parent(of: path))
    }

    public func createFolder(path: String) async throws {
        _ = try await request(
            path: Endpoint.fileCreate,
            body: ["path": path])
    }

    // MARK: - Downloads

    public func storageInformation(path: String) async throws -> FileStorageInformation {
        let response = try await request(
            path: Endpoint.parseFileSlice,
            body: ["path": path])
        let information = FileStorageInformation(json: response)
        return information
    }

    /// Looks up download addresses for a batch of content identifiers.
    public func blockAddresses(identities: [String]) async throws -> [String: BlockStorageInformation] {
        var result: [String: BlockStorageInformation] = [:]
        var index = 0
        while index < identities.count {
            let end = min(index + 200, identities.count)
            let chunk = Array(identities[index..<end])
            let response = try await request(
                path: Endpoint.sliceDownloadAddress,
                body: [
                    "version": 1,
                    "identity": chunk
                ])
            for address in response.array("addresses") {
                if let block = BlockStorageInformation(json: address) {
                    result[block.identity] = block
                }
            }
            index = end
        }
        return result
    }

    /// Downloads a single file, calling `progress` with the bytes written.
    public func download(
        path: String,
        to destination: URL,
        progress: (Int64) -> Void
    ) async throws {
        let information = try await storageInformation(path: path)
        let layout = information.layout()
        guard !layout.isEmpty else {
            throw DownloadError.emptyFile(path)
        }
        let blocks = try await blockAddresses(identities: layout.map(\.identity))
        let downloader = FileDownloader(store: store, blocks: blocks)
        try await downloader.download(
            layout: layout,
            to: destination,
            totalBytes: information.size,
            progress: progress)
    }
}
