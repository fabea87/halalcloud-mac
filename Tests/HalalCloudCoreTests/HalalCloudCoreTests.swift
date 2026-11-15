import XCTest
@testable import HalalCloudCore

final class SignerTests: XCTestCase {

    // Vector cross-checked against HccApi.cpp: the canonical request contains
    // a blank line after the API path and after the header block.
    private let nonce = "3f2504e0-4f89-11d3-9a0c-0305e82c3301"
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    func testTimestampFormatting() {
        let stamp = HccSigner.Timestamp(date: timestamp)
        XCTAssertEqual(stamp.date, "2023-11-14")
        XCTAssertEqual(stamp.full, "2023-11-14T22:13:20Z")
    }

    func testCanonicalRequest() {
        let canonical = HccSigner.canonicalRequest(
            path: "/v6/user/get",
            body: Data("{}".utf8),
            contentType: HccSigner.contentType,
            timestamp: "2023-11-14T22:13:20Z",
            nonce: nonce)

        let expected = """
        POST
        /v6/user/get

        content-type:application/json; charset=utf-8
        host:openapi.2dland.cn
        x-hl-nonce:\(nonce)
        x-hl-timestamp:2023-11-14T22:13:20Z

        content-type;host;x-hl-nonce;x-hl-timestamp
        44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a
        """

        XCTAssertEqual(canonical, expected)
    }

    func testAuthorizationHeader() {
        let signature = HccSigner.sign(
            path: "/v6/user/get",
            body: Data("{}".utf8),
            accessToken: "TESTTOKEN",
            timestamp: timestamp,
            nonce: nonce)

        XCTAssertEqual(signature.timestamp, "2023-11-14T22:13:20Z")
        XCTAssertEqual(signature.nonce, nonce)
        XCTAssertEqual(signature.contentType, "application/json; charset=utf-8")
        XCTAssertEqual(
            signature.authorization,
            "HL6-HMAC-SHA256 "
                + "Credential=puc_5_dcpqfdvu8qnt_v1/2023-11-14/TESTTOKEN/hl6_request,"
                + "SignedHeaders=content-type;host;x-hl-nonce;x-hl-timestamp,"
                + "Signature=cbfe8babc32602eef3b1115d640db53ae01182134c3f04e1aeb1e6549f715123")
        XCTAssertEqual(signature.httpHeaders["authorization"], signature.authorization)
        XCTAssertEqual(signature.httpHeaders["x-hl-timestamp"], "2023-11-14T22:13:20Z")
        XCTAssertNil(signature.httpHeaders["host"])
    }

    func testBodyHashMatchesReference() {
        XCTAssertEqual(
            HccCrypto.sha256Hex("{}"),
            "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a")
    }
}

final class CryptoTests: XCTestCase {

    private let helloWorldCID = "bafkreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e"

    func testCIDDigest() {
        XCTAssertEqual(helloWorldCID.count, HccCrypto.cidStringLength)
        let digest = HccCrypto.cidSHA256(helloWorldCID)
        XCTAssertEqual(digest, HccCrypto.sha256(Data("hello world".utf8)))
        XCTAssertEqual(
            digest.map(HccCrypto.hexString),
            "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")
    }

    func testInvalidCIDs() {
        XCTAssertNil(HccCrypto.cidSHA256(""))
        XCTAssertNil(HccCrypto.cidSHA256("not-a-cid"))
        XCTAssertNil(HccCrypto.cidSHA256("zafkreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e"))
    }

    func testBase32Decoding() {
        XCTAssertEqual(HccCrypto.decodeBase32("MZXW6==="), Data("foo".utf8))
        XCTAssertEqual(HccCrypto.decodeBase32("mzxw6"), Data("foo".utf8))
        XCTAssertNil(HccCrypto.decodeBase32("MZXW6!"))
    }

    func testXorRoundTrip() {
        let data = Data((0..<64).map { UInt8($0) })
        let masked = HccCrypto.xor(data, with: 0x5A)
        XCTAssertNotEqual(masked, data)
        XCTAssertEqual(HccCrypto.xor(masked, with: 0x5A), data)
        XCTAssertEqual(HccCrypto.xor(data, with: 0x00), data)
    }

    func testRandomNonceLayout() {
        let nonce = HccCrypto.randomNonce()
        XCTAssertEqual(nonce.count, 36)
        let groups = nonce.split(separator: "-").map(\.count)
        XCTAssertEqual(groups, [8, 4, 4, 4, 12])
        XCTAssertNotEqual(nonce, HccCrypto.randomNonce())
    }

    func testBase64URL() {
        let encoded = HccCrypto.base64URL(Data([0xFB, 0xFF, 0xFE]))
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
    }
}

final class LayoutTests: XCTestCase {

    private func information(size: Int64) -> FileStorageInformation {
        FileStorageInformation(
            name: "sample.bin",
            path: "/sample.bin",
            size: size,
            storeType: 0,
            contentIdentity: "",
            nodes: ["n0", "n1", "n2"],
            ranges: [
                StorageSizeRange(startIndex: 0, endIndex: 0, blockSize: 4),
                StorageSizeRange(startIndex: 1, endIndex: 2, blockSize: 2)
            ])
    }

    func testLayout() {
        let blocks = information(size: 8).layout()
        XCTAssertEqual(blocks.map(\.identity), ["n0", "n1", "n2"])
        XCTAssertEqual(blocks.map(\.offset), [0, 4, 6])
        XCTAssertEqual(blocks.map(\.size), [4, 2, 2])
    }

    func testLayoutClampsTrailingBlock() {
        let blocks = information(size: 7).layout()
        XCTAssertEqual(blocks.map(\.offset), [0, 4, 6])
        XCTAssertEqual(blocks.map(\.size), [4, 2, 1])
    }

    func testLayoutIgnoresExtraNodes() {
        let storage = FileStorageInformation(
            name: "sample.bin",
            path: "/sample.bin",
            size: 3,
            storeType: 0,
            contentIdentity: "",
            nodes: ["n0", "n1"],
            ranges: [StorageSizeRange(startIndex: 0, endIndex: 0, blockSize: 4)])
        let blocks = storage.layout()
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.size, 3)
    }

    func testEmptyFileHasNoBlocks() {
        XCTAssertTrue(information(size: 0).layout().isEmpty)
    }
}

final class JSONTests: XCTestCase {

    func testCoercion() throws {
        let json = try JNode.parse(Data("""
        {"size":"1234","dir":true,"hidden":0,"nested":{"token":"abc"},"files":[{"name":"a"}],"encrypt":"7"}
        """.utf8))

        XCTAssertEqual(json.object("size").int64, 1234)
        XCTAssertEqual(json.object("dir").bool, true)
        XCTAssertEqual(json.object("hidden").bool, false)
        XCTAssertEqual(json.object("nested").object("token").string, "abc")
        XCTAssertEqual(json.array("files").count, 1)
        XCTAssertEqual(json.array("files").first?.object("name").string, "a")
        XCTAssertEqual(json.object("encrypt").int64, 7)
        XCTAssertTrue(json.object("missing").isNull)
        XCTAssertEqual(json.object("missing").string, "")
        XCTAssertEqual(json.object("missing").int64, 0)
    }

    func testBoolFromNumber() throws {
        let json = try JNode.parse(Data("{\"a\":1,\"b\":0}".utf8))
        XCTAssertTrue(json.object("a").bool)
        XCTAssertFalse(json.object("b").bool)
    }
}
