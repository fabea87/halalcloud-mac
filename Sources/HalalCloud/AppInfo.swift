//
//  AppInfo.swift
//  HalalCloud
//

import Foundation
import HalalCloudCore

enum AppInfo {

    static let displayName = "Halal Cloud"

    /// The upstream Windows client links.
    static let websiteURL = URL(string: "https://2dland.cn/")!
    static let repositoryURL = URL(string: "https://github.com/halalcloud/halalcloud-mac")!

    static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty {
            return "\(displayName) \(version) (Build \(build))"
        }
        return "\(displayName) \(version)"
    }
}

/// Minimal append-only log, so that the "View Log" button has something to show.
enum AppLog {

    private static let lock = NSLock()

    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return base
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("HalalCloud", isDirectory: true)
            .appendingPathComponent("HalalCloud.log")
    }

    static func write(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        lock.lock()
        defer { lock.unlock() }

        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func flush() {
        // Every write is flushed by closing the handle; nothing buffered.
    }
}
