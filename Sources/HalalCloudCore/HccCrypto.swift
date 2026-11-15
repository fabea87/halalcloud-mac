//
//  HccCrypto.swift
//  HalalCloudCore
//
//  Hashing, HMAC, encoding and content-identifier helpers used by the
//  Halal Cloud (HL6) protocol.
//

import Foundation
import CryptoKit

public enum HccCrypto {

    /// Length of a SHA-256 hash in bytes.
    public static let sha256Length = 32

    // MARK: - Hashing

    public static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    public static func sha256Hex(_ data: Data) -> String {
        hexString(sha256(data))
    }

    public static func sha256Hex(_ string: String) -> String {
        sha256Hex(Data(string.utf8))
    }

    public static func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey))
    }

    // MARK: - Hex

    public static func hexString(_ data: Data) -> String {
        let digits = Array("0123456789abcdef")
        var output = String()
        output.reserveCapacity(data.count * 2)
        for byte in data {
            output.append(digits[Int(byte >> 4)])
            output.append(digits[Int(byte & 0x0F)])
        }
        return output
    }

    public static func data(hexString: String) -> Data? {
        let characters = Array(hexString)
        guard characters.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(characters.count / 2)
        var index = 0
        while index < characters.count {
            guard let high = nibble(characters[index]),
                  let low = nibble(characters[index + 1]) else { return nil }
            bytes.append((high << 4) | low)
            index += 2
        }
        return Data(bytes)
    }

    private static func nibble(_ character: Character) -> UInt8? {
        guard let ascii = character.asciiValue else { return nil }
        if ascii >= 48 && ascii <= 57 { return ascii - 48 }        // 0-9
        if ascii >= 97 && ascii <= 102 { return ascii - 87 }       // a-f
        if ascii >= 65 && ascii <= 70 { return ascii - 55 }        // A-F
        return nil
    }

    // MARK: - Randomness

    public static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8]()
        bytes.reserveCapacity(count)
        for _ in 0..<count {
            bytes.append(UInt8.random(in: 0...255, using: &generator))
        }
        return Data(bytes)
    }

    /// Generates a random identifier in the canonical GUID layout, which is
    /// what the Windows client sends in the `x-hl-nonce` header.
    public static func randomNonce() -> String {
        let bytes = [UInt8](randomBytes(16))
        let first = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        let second = (UInt16(bytes[4]) << 8) | UInt16(bytes[5])
        let third = (UInt16(bytes[6]) << 8) | UInt16(bytes[7])
        return String(
            format: "%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            first, second, third,
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15])
    }

    // MARK: - Encoding

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes RFC 4648 Base32 (case insensitive, padding optional).
    public static func decodeBase32(_ input: String) -> Data? {
        var buffer: UInt64 = 0
        var bitCount: UInt8 = 0
        var output = [UInt8]()
        output.reserveCapacity(input.count * 5 / 8 + 1)

        for character in input.uppercased() {
            if character == "=" { break }
            guard let ascii = character.asciiValue else { return nil }
            let value: UInt8
            if ascii >= 65 && ascii <= 90 {
                value = ascii - 65
            } else if ascii >= 50 && ascii <= 55 {
                value = ascii - 50 + 26
            } else {
                return nil
            }
            buffer = (buffer << 5) | UInt64(value)
            bitCount += 5
            if bitCount < 8 { continue }
            bitCount -= 8
            output.append(UInt8((buffer >> UInt64(bitCount)) & 0xFF))
        }
        return Data(output)
    }

    // MARK: - Blocks

    /// The Halal Cloud service XORs every storage block with a per-block byte
    /// before handing it out. The same operation decrypts it.
    public static func xor(_ data: Data, with byte: UInt8) -> Data {
        guard byte != 0, !data.isEmpty else { return data }
        var bytes = [UInt8](data)
        for index in bytes.indices {
            bytes[index] ^= byte
        }
        return Data(bytes)
    }

    // MARK: - Content identifiers

    /// Number of bytes in the binary form of a Halal Cloud CID
    /// (CIDv1 + IPLD raw + SHA2-256 + 32 byte digest).
    public static let cidContentLength = 1 + 1 + 1 + 1 + sha256Length

    /// Number of characters in a Base32 encoded Halal Cloud CID.
    public static let cidStringLength = 59

    /// Extracts the SHA-256 digest from a Halal Cloud CID string.
    ///
    /// Returns `nil` for legacy Baidu Object Storage identifiers, which are not
    /// CIDs, so callers can fall back to size-only validation.
    public static func cidSHA256(_ cid: String) -> Data? {
        guard cid.count == cidStringLength, cid.hasPrefix("b") else { return nil }
        guard let content = decodeBase32(String(cid.dropFirst())),
              content.count == cidContentLength else { return nil }
        let prefix = [UInt8](content.prefix(4))
        guard prefix[0] == 0x01,   // CIDv1
              prefix[1] == 0x55,   // IPLD raw
              prefix[2] == 0x12,   // SHA2-256
              prefix[3] == 0x20 else { return nil }
        return content.subdata(in: 4..<cidContentLength)
    }
}
