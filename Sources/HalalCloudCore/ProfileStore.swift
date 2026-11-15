//
//  ProfileStore.swift
//  HalalCloudCore
//
//  A tiny JSON store for the refresh token. The layout matches the Windows
//  client (`<data>/Profiles/Default/Profile.json` with a `RefreshToken` key)
//  so an existing profile can be copied over from a Windows machine.
//
//  Tokens are stored in a file with 0600 permissions rather than the keychain:
//  the app is distributed unsigned/ad-hoc signed, so the keychain ACL would be
//  invalidated on every update.
//

import Foundation

public struct ProfileStore: Sendable {

    public let directory: URL
    public let name: String

    public static let defaultProfileName = "Default"

    public static var `default`: ProfileStore {
        ProfileStore(directory: Support.applicationDataDirectory
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(defaultProfileName, isDirectory: true))
    }

    public init(directory: URL, name: String = ProfileStore.defaultProfileName) {
        self.directory = directory
        self.name = name
    }

    public var fileURL: URL {
        directory.appendingPathComponent("Profile.json")
    }

    public func load() -> [String: Any] {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    public func loadRefreshToken() -> String? {
        let token = JNode(load()["RefreshToken"]).string
        return token.isEmpty ? nil : token
    }

    public func save(refreshToken: String?, mountPoint: String? = nil) {
        var object = load()
        if let refreshToken, !refreshToken.isEmpty {
            object["RefreshToken"] = refreshToken
        } else {
            object.removeValue(forKey: "RefreshToken")
        }
        if let mountPoint {
            object["MountPoint"] = mountPoint
        }
        guard !object.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path)
        } catch {
            // Losing the persisted token only means signing in again.
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
