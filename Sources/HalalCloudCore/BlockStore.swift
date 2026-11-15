//
//  BlockStore.swift
//  HalalCloudCore
//
//  Downloads storage blocks, decrypts them and verifies their content
//  identifier. Decrypted blocks are cached in memory, the encrypted bytes are
//  cached on disk (mirroring the Windows client's BlocksCache directory).
//

import Foundation

public enum BlockStoreError: LocalizedError, Sendable {
    case badStatus(Int)
    case sizeMismatch(expected: Int, actual: Int)
    case hashMismatch(String)
    case emptyResponse(String)

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return "The storage server returned HTTP \(code) for a block."
        case .sizeMismatch(let expected, let actual):
            return "A storage block was truncated (expected \(expected) bytes, received \(actual))."
        case .hashMismatch(let identity):
            return "A storage block failed its checksum (\(identity.prefix(12))…)."
        case .emptyResponse(let identity):
            return "The storage server returned no data for block \(identity.prefix(12))…"
        }
    }
}

public actor BlockStore {

    private let session: URLSession
    private let cacheDirectory: URL
    private let memoryLimit: Int

    private var memory: [String: Data] = [:]
    private var memoryOrder: [String] = []

    public init(
        cacheDirectory: URL = Support.blockCacheDirectory,
        memoryLimit: Int = 96 * 1024 * 1024
    ) {
        self.cacheDirectory = cacheDirectory
        self.memoryLimit = memoryLimit
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func cachedBlockCount() -> Int {
        memory.count
    }

    public func data(for block: BlockStorageInformation, expectedSize: Int) async throws -> Data {
        guard expectedSize > 0 else { return Data() }

        if let cached = memory[block.identity], cached.count == expectedSize {
            return cached
        }

        let cacheURL = cacheDirectory.appendingPathComponent(block.identity)
        var raw: Data?

        if let disk = try? Data(contentsOf: cacheURL), disk.count == expectedSize {
            raw = disk
        }

        if raw == nil {
            var request = URLRequest(url: block.downloadURL)
            request.timeoutInterval = 120
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                guard (200..<300).contains(http.statusCode) else {
                    throw BlockStoreError.badStatus(http.statusCode)
                }
            }
            guard !data.isEmpty else {
                throw BlockStoreError.emptyResponse(block.identity)
            }
            guard data.count == expectedSize else {
                throw BlockStoreError.sizeMismatch(expected: expectedSize, actual: data.count)
            }
            raw = data
            try? data.write(to: cacheURL, options: .atomic)
        }

        guard let rawData = raw else {
            throw BlockStoreError.sizeMismatch(expected: expectedSize, actual: 0)
        }

        let plain = HccCrypto.xor(rawData, with: block.encryptionByte)

        if let expectedHash = HccCrypto.cidSHA256(block.identity) {
            guard HccCrypto.sha256(plain) == expectedHash else {
                try? FileManager.default.removeItem(at: cacheURL)
                throw BlockStoreError.hashMismatch(block.identity)
            }
        }

        remember(block.identity, plain)
        return plain
    }

    private func remember(_ identity: String, _ data: Data) {
        if memory[identity] == nil {
            memoryOrder.append(identity)
        }
        memory[identity] = data

        var total = memoryOrder.reduce(0) { $0 + (memory[$1]?.count ?? 0) }
        while total > memoryLimit, memoryOrder.count > 1 {
            let evicted = memoryOrder.removeFirst()
            total -= memory[evicted]?.count ?? 0
            memory.removeValue(forKey: evicted)
        }
    }
}
