//
//  Models.swift
//  HalalCloudCore
//

import Foundation

public struct Credentials: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String

    public init(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    public var isValid: Bool {
        !accessToken.isEmpty && !refreshToken.isEmpty
    }
}

public struct UserInformation: Equatable, Sendable {
    public let identity: String
    public let name: String
    public let iconURL: URL?

    public init(identity: String, name: String, iconURL: URL?) {
        self.identity = identity
        self.name = name
        self.iconURL = iconURL
    }
}

public struct UserStatistics: Equatable, Sendable {
    public let bytesQuota: Int64
    public let bytesUsed: Int64

    public init(bytesQuota: Int64, bytesUsed: Int64) {
        self.bytesQuota = bytesQuota
        self.bytesUsed = bytesUsed
    }

    public var fraction: Double {
        guard bytesQuota > 0 else { return 0 }
        return min(1, max(0, Double(bytesUsed) / Double(bytesQuota)))
    }
}

public struct CloudFile: Identifiable, Hashable, Sendable {
    public let name: String
    public let path: String
    public let size: Int64
    public let isDirectory: Bool
    public let isHidden: Bool
    public let creationDate: Date?
    public let modificationDate: Date?
    public let contentIdentity: String

    public var id: String { path }

    public init(
        name: String,
        path: String,
        size: Int64,
        isDirectory: Bool,
        isHidden: Bool,
        creationDate: Date?,
        modificationDate: Date?,
        contentIdentity: String
    ) {
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.contentIdentity = contentIdentity
    }

    public init(json: JNode, parentPath: String) {
        let name = json.object("name").string
        self.init(
            name: name,
            path: Support.join(parent: parentPath, name: name),
            size: json.object("size").int64,
            isDirectory: json.object("dir").bool,
            isHidden: json.object("hidden").bool,
            creationDate: CloudFile.date(fromMilliseconds: json.object("create_ts").int64),
            modificationDate: CloudFile.date(fromMilliseconds: json.object("update_ts").int64),
            contentIdentity: json.object("content_identity").string)
    }

    static func date(fromMilliseconds value: Int64) -> Date? {
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(value) / 1000)
    }

    public var parentPath: String { Support.parent(of: path) }
}

/// A contiguous run of storage blocks that share the same block size.
public struct StorageSizeRange: Hashable, Sendable {
    public let startIndex: Int
    public let endIndex: Int
    public let blockSize: Int64

    public init(startIndex: Int, endIndex: Int, blockSize: Int64) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.blockSize = blockSize
    }

    public var blockCount: Int {
        guard endIndex >= startIndex else { return 0 }
        return endIndex - startIndex + 1
    }
}

/// The block-level layout of a file, as reported by
/// `/v6/userfile/parse_file_slice`.
public struct FileStorageInformation: Sendable {
    public let name: String
    public let path: String
    public let size: Int64
    public let storeType: Int
    public let contentIdentity: String
    public let nodes: [String]
    public let ranges: [StorageSizeRange]

    public init(
        name: String,
        path: String,
        size: Int64,
        storeType: Int,
        contentIdentity: String,
        nodes: [String],
        ranges: [StorageSizeRange]
    ) {
        self.name = name
        self.path = path
        self.size = size
        self.storeType = storeType
        self.contentIdentity = contentIdentity
        self.nodes = nodes
        self.ranges = ranges
    }

    public init(json: JNode) {
        var nodes: [String] = []
        for node in json.array("raw_nodes") {
            nodes.append(node.string)
        }
        var ranges: [StorageSizeRange] = []
        for size in json.array("sizes") {
            ranges.append(StorageSizeRange(
                startIndex: size.object("start_index").int,
                endIndex: size.object("end_index").int,
                blockSize: size.object("size").int64))
        }
        self.init(
            name: json.object("name").string,
            path: json.object("path").string,
            size: json.object("file_size").int64,
            storeType: json.object("store_type").int,
            contentIdentity: json.object("content_identity").string,
            nodes: nodes,
            ranges: ranges)
    }

    /// Files stored in Baidu Object Storage do not use CID identifiers.
    public var isLegacyObjectStorage: Bool { storeType == 10 }

    /// Flattens the nodes/ranges description into absolute offsets.
    public func layout() -> [LayoutBlock] {
        guard size > 0 else { return [] }
        var blocks: [LayoutBlock] = []
        var nodeIndex = 0
        var offset: Int64 = 0
        var finished = false

        for range in ranges {
            if finished { break }
            guard range.startIndex >= 0,
                  range.endIndex >= range.startIndex,
                  range.blockSize > 0 else { continue }
            for _ in range.startIndex...range.endIndex {
                guard nodeIndex < nodes.count else {
                    finished = true
                    break
                }
                var blockSize = range.blockSize
                if offset + blockSize > size {
                    blockSize = size - offset
                }
                guard blockSize > 0 else {
                    finished = true
                    break
                }
                blocks.append(LayoutBlock(
                    identity: nodes[nodeIndex],
                    offset: offset,
                    size: Int(blockSize)))
                offset += blockSize
                nodeIndex += 1
                if offset >= size {
                    finished = true
                    break
                }
            }
        }
        return blocks
    }
}

/// A single storage block mapped onto a byte range of the file.
public struct LayoutBlock: Hashable, Sendable {
    public let identity: String
    public let offset: Int64
    public let size: Int

    public init(identity: String, offset: Int64, size: Int) {
        self.identity = identity
        self.offset = offset
        self.size = size
    }
}

public struct BlockStorageInformation: Hashable, Sendable {
    public let identity: String
    public let downloadURL: URL
    public let encryptionByte: UInt8

    public init(identity: String, downloadURL: URL, encryptionByte: UInt8) {
        self.identity = identity
        self.downloadURL = downloadURL
        self.encryptionByte = encryptionByte
    }

    public init?(json: JNode) {
        let identity = json.object("identity").string
        let address = json.object("download_address").string
        guard !identity.isEmpty, let url = URL(string: address) else { return nil }
        self.init(
            identity: identity,
            downloadURL: url,
            encryptionByte: UInt8(truncatingIfNeeded: json.object("encrypt").int64))
    }
}

public enum AuthorizeState: String, Sendable {
    case pendingLogin = "AUTHORIZATION_PENDING_LOGIN"
    case pendingConfirmation = "AUTHORIZATION_PENDING_CONFIRMATION"
    case tokenCreated = "AUTHORIZATION_TOKEN_CREATED"
    case success = "AUTHORIZATION_SUCCESS"
    case failed = "FAILED"

    public var localizedDescription: String {
        switch self {
        case .pendingLogin:
            return "Waiting for you to sign in…"
        case .pendingConfirmation:
            return "Waiting for you to confirm the sign-in…"
        case .tokenCreated, .success:
            return "Signed in."
        case .failed:
            return "The sign-in request expired or was rejected."
        }
    }
}

public struct AuthorizationRequest: Sendable {
    public let code: String
    public let redirectURI: String
    public let codeVerifier: String

    public init(code: String, redirectURI: String, codeVerifier: String) {
        self.code = code
        self.redirectURI = redirectURI
        self.codeVerifier = codeVerifier
    }
}
