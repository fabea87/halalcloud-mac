//
//  FileDownloader.swift
//  HalalCloudCore
//
//  Reassembles a file from its storage blocks. Blocks are fetched in small
//  parallel batches; writes are serialised through a single file handle.
//

import Foundation

public enum DownloadError: LocalizedError, Sendable {
    case missingBlock(String)
    case cannotCreateFile(String)
    case emptyFile(String)

    public var errorDescription: String? {
        switch self {
        case .missingBlock(let identity):
            return "The server did not provide a download address for block \(identity.prefix(12))…"
        case .cannotCreateFile(let path):
            return "Could not create the file at \(path)."
        case .emptyFile(let path):
            return "The server reported no storage blocks for \(path)."
        }
    }
}

public struct FileDownloader: Sendable {

    private let store: BlockStore
    private let blocks: [String: BlockStorageInformation]
    private let maxConcurrent: Int

    public init(
        store: BlockStore,
        blocks: [String: BlockStorageInformation],
        maxConcurrent: Int = 4
    ) {
        self.store = store
        self.blocks = blocks
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// Downloads `layout` into `destination`, overwriting any existing file.
    /// `progress` is called with the number of bytes written so far.
    public func download(
        layout: [LayoutBlock],
        to destination: URL,
        totalBytes: Int64,
        progress: (Int64) -> Void
    ) async throws {
        guard !layout.isEmpty else {
            throw DownloadError.emptyFile(destination.lastPathComponent)
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw DownloadError.cannotCreateFile(destination.path)
        }

        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        if totalBytes > 0 {
            try handle.truncate(atOffset: UInt64(totalBytes))
        }

        var written: Int64 = 0
        var index = 0

        while index < layout.count {
            let end = min(index + maxConcurrent, layout.count)
            let batch = Array(layout[index..<end])

            try await withThrowingTaskGroup(of: (Int64, Data).self) { group in
                for item in batch {
                    guard let block = blocks[item.identity] else {
                        throw DownloadError.missingBlock(item.identity)
                    }
                    group.addTask {
                        let data = try await store.data(for: block, expectedSize: item.size)
                        return (item.offset, data)
                    }
                }
                for try await (offset, data) in group {
                    try handle.seek(toOffset: UInt64(offset))
                    try handle.write(contentsOf: data)
                    written += Int64(data.count)
                    progress(written)
                }
            }

            index = end
        }
    }
}
