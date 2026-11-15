//
//  HccSigner.swift
//  HalalCloudCore
//
//  Request signing for the Halal Cloud Open API ("HL6-HMAC-SHA256").
//
//  The scheme is a SigV4-like derivation:
//
//      key      = HMAC(HMAC(HMAC(HMAC("HL6" + secret_key, date),
//                               access_token), "hl6_request"), string_to_sign)
//      signature = hex(key)
//
//  Note that the `host` header takes part in the signature even though it is
//  not sent explicitly (URLSession sets it from the URL).
//

import Foundation

public struct HccSignature: Equatable, Sendable {
    public let authorization: String
    public let contentType: String
    public let nonce: String
    public let timestamp: String

    public var httpHeaders: [String: String] {
        [
            "content-type": contentType,
            "x-hl-nonce": nonce,
            "x-hl-timestamp": timestamp,
            "authorization": authorization
        ]
    }
}

public enum HccSigner {

    public static let host = "openapi.2dland.cn"
    public static let secretID = "puc_5_dcpqfdvu8qnt_v1"
    public static let secretKey = "c8303e83dc164352a38289409681df8d"
    public static let signatureAlgorithm = "HL6-HMAC-SHA256"
    public static let requestSuffix = "hl6_request"
    public static let contentType = "application/json; charset=utf-8"
    public static let signatureKeyPrefix = "HL6"

    /// The access token used for requests that do not require authentication.
    public static let anonymousAccessToken = "*"

    /// Header names in the canonical order used by the Windows client.
    public static let signedHeaderNames = [
        "content-type", "host", "x-hl-nonce", "x-hl-timestamp"
    ]

    // MARK: - Timestamps

    public struct Timestamp: Equatable, Sendable {
        /// `yyyy-MM-dd` in UTC.
        public let date: String
        /// `yyyy-MM-ddTHH:mm:ssZ` in UTC.
        public let full: String

        public init(date: Date) {
            self.date = HccSigner.format(date, pattern: "yyyy-MM-dd")
            self.full = HccSigner.format(date, pattern: "yyyy-MM-dd'T'HH:mm:ss'Z'")
        }
    }

    private static func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    // MARK: - Canonical request

    public static func canonicalRequest(
        path: String,
        body: Data,
        contentType: String,
        timestamp: String,
        nonce: String
    ) -> String {
        let headerValues = [
            "content-type": contentType,
            "host": host,
            "x-hl-nonce": nonce,
            "x-hl-timestamp": timestamp
        ]

        var canonical = "POST\n"
        canonical += path + "\n"
        canonical += "\n" // POST requests never carry a query string.
        for name in signedHeaderNames {
            canonical += name + ":" + (headerValues[name] ?? "") + "\n"
        }
        canonical += "\n"
        canonical += signedHeaderNames.joined(separator: ";") + "\n"
        canonical += HccCrypto.sha256Hex(body)
        return canonical
    }

    public static func credentialScope(date: String, accessToken: String) -> String {
        "\(date)/\(accessToken)/\(requestSuffix)"
    }

    public static func stringToSign(
        path: String,
        body: Data,
        contentType: String,
        timestamp: String,
        nonce: String,
        date: String,
        accessToken: String
    ) -> String {
        let canonical = canonicalRequest(
            path: path,
            body: body,
            contentType: contentType,
            timestamp: timestamp,
            nonce: nonce)
        var stringToSign = signatureAlgorithm + "\n"
        stringToSign += timestamp + "\n"
        stringToSign += credentialScope(date: date, accessToken: accessToken) + "\n"
        stringToSign += HccCrypto.sha256Hex(canonical)
        return stringToSign
    }

    public static func signature(
        stringToSign: String,
        date: String,
        accessToken: String
    ) -> String {
        var key = Data((signatureKeyPrefix + secretKey).utf8)
        key = HccCrypto.hmacSHA256(key: key, data: Data(date.utf8))
        key = HccCrypto.hmacSHA256(key: key, data: Data(accessToken.utf8))
        key = HccCrypto.hmacSHA256(key: key, data: Data(requestSuffix.utf8))
        let digest = HccCrypto.hmacSHA256(key: key, data: Data(stringToSign.utf8))
        return HccCrypto.hexString(digest)
    }

    // MARK: - Entry point

    public static func sign(
        path: String,
        body: Data,
        accessToken: String,
        timestamp: Date = Date(),
        nonce: String = HccCrypto.randomNonce()
    ) -> HccSignature {
        let stamp = Timestamp(date: timestamp)
        let stringToSign = stringToSign(
            path: path,
            body: body,
            contentType: contentType,
            timestamp: stamp.full,
            nonce: nonce,
            date: stamp.date,
            accessToken: accessToken)
        let signature = signature(
            stringToSign: stringToSign,
            date: stamp.date,
            accessToken: accessToken)
        let scope = credentialScope(date: stamp.date, accessToken: accessToken)
        let authorization = "\(signatureAlgorithm) "
            + "Credential=\(secretID)/\(scope),"
            + "SignedHeaders=\(signedHeaderNames.joined(separator: ";")),"
            + "Signature=\(signature)"
        return HccSignature(
            authorization: authorization,
            contentType: contentType,
            nonce: nonce,
            timestamp: stamp.full)
    }
}
