//
//  Support.swift
//  HalalCloudCore
//

import Foundation

public enum Support {

    public static let applicationName = "HalalCloud"

    public static var applicationDataDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(applicationName, isDirectory: true)
    }

    public static var cacheDirectory: URL {
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Caches", isDirectory: true)
        return base.appendingPathComponent(applicationName, isDirectory: true)
    }

    public static var blockCacheDirectory: URL {
        cacheDirectory.appendingPathComponent("Blocks", isDirectory: true)
    }

    @discardableResult
    public static func ensureDirectory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func byteString(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = .useAll
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: count)
    }

    public static func shortDateString(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    public static func join(parent: String, name: String) -> String {
        if parent == "/" || parent.isEmpty { return "/" + name }
        if parent.hasSuffix("/") { return parent + name }
        return parent + "/" + name
    }

    public static func parent(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    /// Splits a remote path into breadcrumbs, starting with the root.
    public static func breadcrumbs(for path: String) -> [(title: String, path: String)] {
        var items: [(title: String, path: String)] = [("Halal Cloud", "/")]
        guard path != "/" else { return items }
        var accumulated = ""
        for component in path.split(separator: "/") {
            accumulated += "/" + component
            items.append((String(component), accumulated))
        }
        return items
    }
}
