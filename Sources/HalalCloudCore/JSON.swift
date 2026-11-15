//
//  JSON.swift
//  HalalCloudCore
//
//  The Halal Cloud Open API returns numbers either as JSON numbers or as
//  strings (the reference client converts everything through a string
//  representation). These wrappers normalise both shapes.
//

import Foundation

public struct JNode {
    public let value: Any?

    public init(_ value: Any?) {
        self.value = value
    }

    public static func parse(_ data: Data) throws -> JNode {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        return JNode(object)
    }

    public func object(_ key: String) -> JNode {
        guard let dictionary = value as? [String: Any] else { return JNode(nil) }
        return JNode(dictionary[key])
    }

    public func array(_ key: String) -> [JNode] {
        guard let dictionary = value as? [String: Any] else { return [] }
        return (dictionary[key] as? [Any])?.map { JNode($0) } ?? []
    }

    public var string: String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return ""
        }
    }

    public var int64: Int64 {
        switch value {
        case let number as NSNumber:
            return number.int64Value
        case let string as String:
            if let parsed = Int64(string) { return parsed }
            if let parsed = Double(string) { return Int64(parsed) }
            return 0
        default:
            return 0
        }
    }

    public var uint64: UInt64 {
        let signed = int64
        return signed < 0 ? 0 : UInt64(signed)
    }

    public var int: Int {
        Int(int64)
    }

    public var bool: Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return ["true", "1", "yes"].contains(string.lowercased())
        default:
            return false
        }
    }

    public var isNull: Bool {
        value == nil || value is NSNull
    }
}
