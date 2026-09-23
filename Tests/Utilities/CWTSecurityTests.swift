/*
 * Copyright (c) 2023 European Commission
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import Testing
import Foundation
import SwiftCBOR

@testable import StatiumSwift

/// Security tests for CWT decoder - validates security hardening fixes.
/// These tests verify that malicious or malformed CWT tokens are properly rejected.
@Suite
final class CWTSecurityTests {

  // MARK: - Subject Binding Tests

  /// Verify that a CWT with mismatched subject claim is rejected.
  /// The subject claim MUST match the URL used to fetch the token.
  @Test
  func testDecodeCWT_WhenSubjectMismatchesFetchURL_ThenThrowsSubjectMismatch() throws {
    // Create a valid CWT structure with subject "https://other.example.com/status"
    let cwtData = try createValidCWT(
      subject: "https://other.example.com/status",
      issuedAt: Date().timeIntervalSince1970,
      expiration: Date().timeIntervalSince1970 + 3600
    )

    // Attempt to decode with a different URL
    let fetchedFrom = URL(string: "https://issuer.example.com/status")!

    #expect(throws: CWTDecodingError.subjectMismatch) {
      try CWTDecoder().decodeStatusListToken(
        from: cwtData,
        fetchedFrom: fetchedFrom,
        clockSkew: 300
      )
    }
  }

  /// Verify that a CWT with matching subject claim is accepted.
  @Test
  func testDecodeCWT_WhenSubjectMatchesFetchURL_ThenSucceeds() throws {
    let urlString = "https://issuer.example.com/status"
    let cwtData = try createValidCWT(
      subject: urlString,
      issuedAt: Date().timeIntervalSince1970,
      expiration: Date().timeIntervalSince1970 + 3600
    )

    let fetchedFrom = URL(string: urlString)!

    // Should not throw
    let claims = try CWTDecoder().decodeStatusListToken(
      from: cwtData,
      fetchedFrom: fetchedFrom,
      clockSkew: 300
    )

    #expect(claims.subject == urlString)
  }

  // MARK: - Protected Header Type Tests

  /// Verify that a CWT with typ only in unprotected header is rejected.
  /// The typ claim MUST be in the protected (signed) header for integrity protection.
  @Test
  func testDecodeCWT_WhenTypOnlyInUnprotectedHeader_ThenThrowsInvalidType() throws {
    // Create a CWT with typ in unprotected header only (not in protected header)
    let cwtData = try createCWTWithUnprotectedTyp()

    #expect(throws: CWTDecodingError.invalidType) {
      try CWTDecoder().decodeStatusListToken(from: cwtData)
    }
  }

  /// Verify that a CWT with typ in protected header is accepted.
  @Test
  func testDecodeCWT_WhenTypInProtectedHeader_ThenSucceeds() throws {
    let cwtData = try createValidCWT(
      subject: "https://issuer.example.com/status",
      issuedAt: Date().timeIntervalSince1970,
      expiration: Date().timeIntervalSince1970 + 3600
    )

    // Should not throw - typ is in protected header
    let claims = try CWTDecoder().decodeStatusListToken(from: cwtData)
    #expect(claims.subject == "https://issuer.example.com/status")
  }

  // MARK: - CBOR Depth Limit Tests

  /// Verify that deeply nested CBOR throws an error.
  /// This prevents stack overflow attacks using excessively nested structures.
  @Test
  func testDecodeCWT_WhenDeeplyNestedCBOR_ThenThrowsError() throws {
    // Create CBOR with nesting deeper than maxCBORDepth (64)
    let deeplyNestedData = createDeeplyNestedCBOR(depth: 100)

    // Should throw CBORError.maximumDepthExceeded (wrapped in some error)
    #expect(throws: (any Error).self) {
      try CWTDecoder().decodeStatusListToken(from: deeplyNestedData)
    }
  }

  /// Verify that input larger than 1MB is rejected.
  @Test
  func testDecodeCWT_WhenInputTooLarge_ThenThrowsInputTooLarge() throws {
    // Create data larger than 1MB
    let largeData = Data(repeating: 0, count: 1024 * 1024 + 1)

    #expect(throws: CWTDecodingError.inputTooLarge) {
      try CWTDecoder().decodeStatusListToken(from: largeData)
    }
  }

  // MARK: - Exp Claim Numeric Type Tests

  /// Verify that float-encoded exp is properly parsed.
  /// Note: Float32 has limited precision for large Unix timestamps, so we use a relative tolerance.
  @Test
  func testDecodeCWT_WhenExpIsFloat_ThenParsesCorrectly() throws {
    let expTime = Date().timeIntervalSince1970 + 3600
    let cwtData = try createCWTWithFloatExp(expiration: Float(expTime))

    let claims = try CWTDecoder().decodeStatusListToken(from: cwtData)

    // The exp should be parsed. Float32 has ~7 significant digits of precision,
    // so for Unix timestamps (~10 digits), we expect ~3 digits of error (up to ~1000 seconds).
    // The important thing is that the value is parsed, not silently dropped.
    #expect(claims.expirationTime != nil)
    if let exp = claims.expirationTime {
      // Use relative tolerance: within 0.01% of the value
      let tolerance = expTime * 0.0001
      #expect(abs(exp - expTime) < tolerance)
    }
  }

  /// Verify that double-encoded exp is properly parsed.
  @Test
  func testDecodeCWT_WhenExpIsDouble_ThenParsesCorrectly() throws {
    let expTime = Date().timeIntervalSince1970 + 3600
    let cwtData = try createCWTWithDoubleExp(expiration: expTime)

    let claims = try CWTDecoder().decodeStatusListToken(from: cwtData)

    #expect(claims.expirationTime != nil)
    if let exp = claims.expirationTime {
      #expect(abs(exp - expTime) < 0.001)
    }
  }

  /// Verify that invalid exp type causes failure (fail closed).
  @Test
  func testDecodeCWT_WhenExpIsInvalidType_ThenThrowsInvalidClaims() throws {
    // Create a CWT where exp is a string instead of a number
    let cwtData = try createCWTWithStringExp()

    #expect(throws: CWTDecodingError.invalidClaims) {
      try CWTDecoder().decodeStatusListToken(from: cwtData)
    }
  }

  // MARK: - CWT Framing Tests

  /// Verify that untagged 4-element array is rejected.
  /// COSE_Sign1 MUST have tag 18 to distinguish from COSE_Sign.
  @Test
  func testDecodeCWT_WhenUntaggedArray_ThenThrowsNotCoseSign1() throws {
    let untaggedData = try createUntaggedCOSEArray()

    #expect(throws: CWTDecodingError.notCoseSign1) {
      try CWTDecoder().decodeStatusListToken(from: untaggedData)
    }
  }

  /// Verify that trailing bytes after CBOR are rejected.
  @Test
  func testDecodeCWT_WhenTrailingBytes_ThenThrowsTrailingBytes() throws {
    var cwtData = try createValidCWT(
      subject: "https://issuer.example.com/status",
      issuedAt: Date().timeIntervalSince1970,
      expiration: Date().timeIntervalSince1970 + 3600
    )

    // Append trailing bytes
    cwtData.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF])

    #expect(throws: CWTDecodingError.trailingBytes) {
      try CWTDecoder().decodeStatusListToken(from: cwtData)
    }
  }

  /// Verify that signature element must be a byte string.
  @Test
  func testDecodeCWT_WhenSignatureNotByteString_ThenThrowsInvalidCoseStructure() throws {
    let invalidSignatureData = try createCWTWithInvalidSignatureElement()

    #expect(throws: CWTDecodingError.invalidCoseStructure) {
      try CWTDecoder().decodeStatusListToken(from: invalidSignatureData)
    }
  }

  // MARK: - TTL & Freshness Tests

  /// Verify that CWT with expired TTL is rejected.
  @Test
  func testDecodeCWT_WhenTTLExpired_ThenThrowsTTLExceeded() throws {
    // Create a CWT where iat is old enough that TTL has expired
    let oldIat = Date().timeIntervalSince1970 - 7200  // 2 hours ago
    let ttl: TimeInterval = 3600  // 1 hour TTL
    let cwtData = try createCWTWithTTL(
      subject: "https://example.com/status",
      issuedAt: oldIat,
      timeToLive: ttl
    )

    #expect(throws: CWTDecodingError.ttlExceeded) {
      try CWTDecoder().decodeStatusListToken(from: cwtData)
    }
  }

  /// Verify that CWT with valid TTL is accepted.
  @Test
  func testDecodeCWT_WhenTTLValid_ThenSucceeds() throws {
    let recentIat = Date().timeIntervalSince1970 - 60  // 1 minute ago
    let ttl: TimeInterval = 3600  // 1 hour TTL
    let cwtData = try createCWTWithTTL(
      subject: "https://example.com/status",
      issuedAt: recentIat,
      timeToLive: ttl
    )

    let claims = try CWTDecoder().decodeStatusListToken(from: cwtData)
    #expect(claims.timeToLive == ttl)
  }

  /// Verify that CWT without exp or ttl is rejected (no freshness constraint).
  @Test
  func testDecodeCWT_WhenNoFreshnessConstraint_ThenThrowsNoFreshnessConstraint() throws {
    let cwtData = try createCWTWithoutFreshnessConstraint()

    #expect(throws: CWTDecodingError.noFreshnessConstraint) {
      try CWTDecoder().decodeStatusListToken(from: cwtData)
    }
  }

  /// Verify that CWT with only ttl (no exp) is accepted.
  @Test
  func testDecodeCWT_WhenOnlyTTLPresent_ThenSucceeds() throws {
    let cwtData = try createCWTWithTTL(
      subject: "https://example.com/status",
      issuedAt: Date().timeIntervalSince1970,
      timeToLive: 3600
    )

    let claims = try CWTDecoder().decodeStatusListToken(from: cwtData)
    #expect(claims.expirationTime == nil)
    #expect(claims.timeToLive == 3600)
  }

  // MARK: - Helper Methods

  /// Creates a valid CWT with proper COSE_Sign1 structure.
  private func createValidCWT(
    subject: String,
    issuedAt: TimeInterval,
    expiration: TimeInterval
  ) throws -> Data {
    // Protected header with typ
    let protectedHeader: CBOR = .map([
      .unsignedInt(16): .utf8String("application/statuslist+cwt")  // typ
    ])
    let protectedHeaderBytes = Data(CBOR.encode(protectedHeader))

    // Unprotected header (empty)
    let unprotectedHeader: CBOR = .map([:])

    // Payload with claims
    let statusListMap: CBOR = .map([
      .utf8String("bits"): .unsignedInt(1),
      .utf8String("lst"): .byteString([0x78, 0x9c, 0x63, 0x60, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01])  // Compressed zeros
    ])

    let payload: CBOR = .map([
      .unsignedInt(2): .utf8String(subject),  // sub
      .unsignedInt(6): .unsignedInt(UInt64(issuedAt)),  // iat
      .unsignedInt(4): .unsignedInt(UInt64(expiration)),  // exp
      .unsignedInt(65533): statusListMap  // status_list
    ])
    let payloadBytes = Data(CBOR.encode(payload))

    // Signature (dummy for testing structure)
    let signature: [UInt8] = Array(repeating: 0, count: 64)

    // COSE_Sign1 structure with tag 18
    let coseSign1: CBOR = .tagged(
      CBOR.Tag(rawValue: 18),
      .array([
        .byteString([UInt8](protectedHeaderBytes)),
        unprotectedHeader,
        .byteString([UInt8](payloadBytes)),
        .byteString(signature)
      ])
    )

    return Data(CBOR.encode(coseSign1))
  }

  /// Creates a CWT with typ only in unprotected header.
  private func createCWTWithUnprotectedTyp() throws -> Data {
    // Protected header WITHOUT typ
    let protectedHeader: CBOR = .map([:])
    let protectedHeaderBytes = Data(CBOR.encode(protectedHeader))

    // Unprotected header WITH typ (this should be rejected)
    let unprotectedHeader: CBOR = .map([
      .unsignedInt(16): .utf8String("application/statuslist+cwt")
    ])

    // Minimal payload
    let statusListMap: CBOR = .map([
      .utf8String("bits"): .unsignedInt(1),
      .utf8String("lst"): .byteString([0x78, 0x9c, 0x63, 0x60, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01])
    ])

    let payload: CBOR = .map([
      .unsignedInt(2): .utf8String("https://example.com/status"),
      .unsignedInt(6): .unsignedInt(UInt64(Date().timeIntervalSince1970)),
      .unsignedInt(4): .unsignedInt(UInt64(Date().timeIntervalSince1970 + 3600)),
      .unsignedInt(65533): statusListMap
    ])
    let payloadBytes = Data(CBOR.encode(payload))

    let coseSign1: CBOR = .tagged(
      CBOR.Tag(rawValue: 18),
      .array([
        .byteString([UInt8](protectedHeaderBytes)),
        unprotectedHeader,
        .byteString([UInt8](payloadBytes)),
        .byteString(Array(repeating: 0, count: 64))
      ])
    )

    return Data(CBOR.encode(coseSign1))
  }

  /// Creates deeply nested CBOR structure.
  private func createDeeplyNestedCBOR(depth: Int) -> Data {
    var nested: CBOR = .unsignedInt(0)
    for _ in 0..<depth {
      nested = .array([nested])
    }
    return Data(CBOR.encode(nested))
  }

  /// Creates a CWT with float-encoded exp.
  private func createCWTWithFloatExp(expiration: Float) throws -> Data {
    let protectedHeader: CBOR = .map([
      .unsignedInt(16): .utf8String("application/statuslist+cwt")
    ])
    let protectedHeaderBytes = Data(CBOR.encode(protectedHeader))

    let statusListMap: CBOR = .map([
      .utf8String("bits"): .unsignedInt(1),
      .utf8String("lst"): .byteString([0x78, 0x9c, 0x63, 0x60, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01])
    ])

    let payload: CBOR = .map([
      .unsignedInt(2): .utf8String("https://example.com/status"),
      .unsignedInt(6): .unsignedInt(UInt64(Date().timeIntervalSince1970)),
      .unsignedInt(4): .float(expiration),  // exp as float
      .unsignedInt(65533): statusListMap
    ])
    let payloadBytes = Data(CBOR.encode(payload))

    let coseSign1: CBOR = .tagged(
      CBOR.Tag(rawValue: 18),
      .array([
        .byteString([UInt8](protectedHeaderBytes)),
        .map([:]),
        .byteString([UInt8](payloadBytes)),
        .byteString(Array(repeating: 0, count: 64))
      ])
    )

    return Data(CBOR.encode(coseSign1))
  }

  /// Creates a CWT with double-encoded exp.
  private func createCWTWithDoubleExp(expiration: Double) throws -> Data {
    let protectedHeader: CBOR = .map([
      .unsignedInt(16): .utf8String("application/statuslist+cwt")
    ])
    let protectedHeaderBytes = Data(CBOR.encode(protectedHeader))

    let statusListMap: CBOR = .map([
      .utf8String("bits"): .unsignedInt(1),
      .utf8String("lst"): .byteString([0x78, 0x9c, 0x63, 0x60, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01])
    ])

    let payload: CBOR = .map([
      .unsignedInt(2): .utf8String("https://example.com/status"),
      .unsignedInt(6): .unsignedInt(UInt64(Date().timeIntervalSince1970)),
      .unsignedInt(4): .double(expiration),  // exp as double
      .unsignedInt(65533): statusListMap
    ])
    let payloadBytes = Data(CBOR.encode(payload))

    let coseSign1: CBOR = .tagged(
      CBOR.Tag(rawValue: 18),
      .array([
        .byteString([UInt8](protectedHeaderBytes)),
        .map([:]),
        .byteString([UInt8](payloadBytes)),
        .byteString(Array(repeating: 0, count: 64))
      ])
    )

    return Data(CBOR.encode(coseSign1))
  }

  /// Creates a CWT with string-encoded exp (fail-closed test).
  private func createCWTWithStringExp() throws -> Data {
    let protectedHeader: CBOR = .map([
      .unsignedInt(16): .utf8String("application/statuslist+cwt")
    ])
    let protectedHeaderBytes = Data(CBOR.encode(protectedHeader))

    let statusListMap: CBOR = .map([
      .utf8String("bits"): .unsignedInt(1),
      .utf8String("lst"): .byteString([0x78, 0x9c, 0x63, 0x60, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01])
    ])

    let payload: CBOR = .map([
      .unsignedInt(2): .utf8String("https://example.com/status"),
      .unsignedInt(6): .unsignedInt(UInt64(Date().timeIntervalSince1970)),
      .unsignedInt(4): .utf8String("invalid"),  // exp as string - INVALID
      .unsignedInt(65533): statusListMap
    ])
    let payloadBytes = Data(CBOR.encode(payload))

    let coseSign1: CBOR = .tagged(
      CBOR.Tag(rawValue: 18),
      .array([
        .byteString([UInt8](protectedHeaderBytes)),
        .map([:]),
        .byteString([UInt8](payloadBytes)),
        .byteString(Array(repeating: 0, count: 64))
      ])
    )

    return Data(CBOR.encode(coseSign1))
  }

  /// Creates an untagged COSE array.
  private func createUntaggedCOSEArray() throws -> Data {
    let protectedHeader: CBOR = .map([
      .unsignedInt(16): .utf8String("application/statuslist+cwt")
    ])
    let protectedHeaderBytes = Data(CBOR.encode(protectedHeader))

    let statusListMap: CBOR = .map([
      .utf8String("bits"): .unsignedInt(1),
      .utf8String("lst"): .byteString([0x78, 0x9c, 0x63, 0x60, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01])
    ])

    let payload: CBOR = .map([
      .unsignedInt(2): .utf8String("https://example.com/status"),
      .unsignedInt(6): .unsignedInt(UInt64(Date().timeIntervalSince1970)),
      .unsignedInt(4): .unsignedInt(UInt64(Date().timeIntervalSince1970 + 3600)),
      .unsignedInt(65533): statusListMap
    ])
    let payloadBytes = Data(CBOR.encode(payload))

    // NO TAG - just a bare array (should be rejected)
    let coseArray: CBOR = .array([
      .byteString([UInt8](protectedHeaderBytes)),
      .map([:]),
      .byteString([UInt8](payloadBytes)),
      .byteString(Array(repeating: 0, count: 64))
    ])

    return Data(CBOR.encode(coseArray))
  }

  /// Creates a CWT with invalid signature element (not a byte string).
  private func createCWTWithInvalidSignatureElement() throws -> Data {
    let protectedHeader: CBOR = .map([
      .unsignedInt(16): .utf8String("application/statuslist+cwt")
    ])
    let protectedHeaderBytes = Data(CBOR.encode(protectedHeader))

    let statusListMap: CBOR = .map([
      .utf8String("bits"): .unsignedInt(1),
      .utf8String("lst"): .byteString([0x78, 0x9c, 0x63, 0x60, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01])
    ])

    let payload: CBOR = .map([
      .unsignedInt(2): .utf8String("https://example.com/status"),
      .unsignedInt(6): .unsignedInt(UInt64(Date().timeIntervalSince1970)),
      .unsignedInt(4): .unsignedInt(UInt64(Date().timeIntervalSince1970 + 3600)),
      .unsignedInt(65533): statusListMap
    ])
    let payloadBytes = Data(CBOR.encode(payload))

    // Signature as a string instead of byte string
    let coseSign1: CBOR = .tagged(
      CBOR.Tag(rawValue: 18),
      .array([
        .byteString([UInt8](protectedHeaderBytes)),
        .map([:]),
        .byteString([UInt8](payloadBytes)),
        .utf8String("not-a-byte-string")  // INVALID - should be byteString
      ])
    )

    return Data(CBOR.encode(coseSign1))
  }

  /// Creates a CWT with TTL (no exp) for TTL tests.
  private func createCWTWithTTL(
    subject: String,
    issuedAt: TimeInterval,
    timeToLive: TimeInterval
  ) throws -> Data {
    let protectedHeader: CBOR = .map([
      .unsignedInt(16): .utf8String("application/statuslist+cwt")
    ])
    let protectedHeaderBytes = Data(CBOR.encode(protectedHeader))

    let statusListMap: CBOR = .map([
      .utf8String("bits"): .unsignedInt(1),
      .utf8String("lst"): .byteString([0x78, 0x9c, 0x63, 0x60, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01])
    ])

    // NO exp claim, only ttl
    let payload: CBOR = .map([
      .unsignedInt(2): .utf8String(subject),  // sub
      .unsignedInt(6): .unsignedInt(UInt64(issuedAt)),  // iat
      .unsignedInt(65534): .unsignedInt(UInt64(timeToLive)),  // ttl
      .unsignedInt(65533): statusListMap  // status_list
    ])
    let payloadBytes = Data(CBOR.encode(payload))

    let coseSign1: CBOR = .tagged(
      CBOR.Tag(rawValue: 18),
      .array([
        .byteString([UInt8](protectedHeaderBytes)),
        .map([:]),
        .byteString([UInt8](payloadBytes)),
        .byteString(Array(repeating: 0, count: 64))
      ])
    )

    return Data(CBOR.encode(coseSign1))
  }

  /// Creates a CWT without exp or ttl - no freshness constraint.
  private func createCWTWithoutFreshnessConstraint() throws -> Data {
    let protectedHeader: CBOR = .map([
      .unsignedInt(16): .utf8String("application/statuslist+cwt")
    ])
    let protectedHeaderBytes = Data(CBOR.encode(protectedHeader))

    let statusListMap: CBOR = .map([
      .utf8String("bits"): .unsignedInt(1),
      .utf8String("lst"): .byteString([0x78, 0x9c, 0x63, 0x60, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01])
    ])

    // NO exp, NO ttl - this should be rejected
    let payload: CBOR = .map([
      .unsignedInt(2): .utf8String("https://example.com/status"),  // sub
      .unsignedInt(6): .unsignedInt(UInt64(Date().timeIntervalSince1970)),  // iat
      .unsignedInt(65533): statusListMap  // status_list
    ])
    let payloadBytes = Data(CBOR.encode(payload))

    let coseSign1: CBOR = .tagged(
      CBOR.Tag(rawValue: 18),
      .array([
        .byteString([UInt8](protectedHeaderBytes)),
        .map([:]),
        .byteString([UInt8](payloadBytes)),
        .byteString(Array(repeating: 0, count: 64))
      ])
    )

    return Data(CBOR.encode(coseSign1))
  }
}
