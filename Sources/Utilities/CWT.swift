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
import Foundation
import SwiftCBOR
import Collections

public enum CWTDecodingError: Error {
  case notCoseSign1
  case invalidCoseStructure
  case invalidPayload
  case invalidClaims
  case missingStatusList
  case invalidBitsValue
  case invalidListBytes
  case inputTooLarge
  case trailingBytes

  // Added for required validation
  case invalidType
  case subjectMismatch
  case issuedAtInFuture
  case expired
  case ttlExceeded
  case noFreshnessConstraint
}

public struct CWTDecoder {

  /// Maximum allowed input size for CBOR decoding (1 MB).
  private static let maxInputSize = 1024 * 1024  // 1 MB

  /// Maximum nesting depth for CBOR structures.
  /// This prevents stack overflow attacks using deeply nested structures in the unprotected header.
  private static let maxCBORDepth = 64

  public init() {}

  /// Backwards-compatible API.
  /// Performs claim parsing + (minimum) validation of exp/iat.
  /// Does not validate subject vs fetched URL because no URL context is provided.
  public func decodeStatusListToken(from data: Data) throws -> StatusListTokenClaims {
    try decodeStatusListToken(from: data, fetchedFrom: nil, clockSkew: 0)
  }

  /// Decode + validate:
  /// - typ header == "application/statuslist+cwt"
  /// - sub matches the origin of the URL used to fetch the token (if provided)
  /// - iat not in the future (with clock skew)
  /// - exp present and not expired (with clock skew)
  public func decodeStatusListToken(
    from data: Data,
    fetchedFrom: URL?,
    clockSkew: TimeInterval = 300
  ) throws -> StatusListTokenClaims {

    // Enable trailing bytes checking for the root COSE structure.
    // Trailing bytes are not covered by the signature and could be used for covert channels.
    let root = try Self.decodeCBOR(from: data, checkTrailingBytes: true)

    // Expect COSE_Sign1: tag(18, array[4])
    // NOTE: We require the COSE_Sign1 tag (18) and reject untagged arrays.
    // Untagged 4-element arrays are ambiguous with COSE_Sign (multi-signature) format.
    let coseArray: [CBOR]
    switch root {
    case .tagged(let tag, let value) where tag.rawValue == 18:
      guard case let .array(arr) = value, arr.count == 4 else {
        throw CWTDecodingError.invalidCoseStructure
      }
      coseArray = arr

    default:
      throw CWTDecodingError.notCoseSign1
    }

    // COSE_Sign1 structure: [protected, unprotected, payload, signature]
    guard case let .byteString(protectedHeaderBytes) = coseArray[0] else {
      throw CWTDecodingError.invalidCoseStructure
    }

    guard case .map = coseArray[1] else {
      throw CWTDecodingError.invalidCoseStructure
    }

    // Validate signature element is a byte string (COSE_Sign1 requirement)
    guard case .byteString = coseArray[3] else {
      throw CWTDecodingError.invalidCoseStructure
    }

    // Validate typ == "application/statuslist+cwt" (protected header only)
    try Self.validateType(
      protectedHeaderBytes: Data(protectedHeaderBytes)
    )

    // Extract payload (3rd element)
    guard case let .byteString(payloadBytes) = coseArray[2] else {
      throw CWTDecodingError.invalidCoseStructure
    }
    
    // Decode payload as CBOR map (CWT claims)
    let payloadCBOR = try Self.decodeCBOR(from: Data(payloadBytes))
    guard case let .map(claimsMap) = payloadCBOR else {
      throw CWTDecodingError.invalidPayload
    }
    
    #if DEBUG
    print("CWT claims keys:")
    for (k, _) in claimsMap {
      print(" - \(k)")
    }
    #endif
    
    func claim(_ key: UInt64) -> CBOR? {
      claimsMap.first { k, _ in
        if case let .unsignedInt(v) = k { return v == key }
        return false
      }?.1
    }
    
    // Claim 2 = sub
    guard case let .utf8String(sub) = claim(2) else {
      throw CWTDecodingError.invalidClaims
    }
    
    // Claim 6 = iat
    guard case let .unsignedInt(iatRaw)? = claim(6) else {
      throw CWTDecodingError.invalidClaims
    }
    let iat = TimeInterval(iatRaw)
    
    // Claim 4 = exp (optional, but must be valid numeric if present)
    // Handle all valid CBOR numeric types to avoid silently dropping float-encoded exp values.
    var exp: TimeInterval?
    if let expCbor = claim(4) {
      switch expCbor {
      case .unsignedInt(let v):
        exp = TimeInterval(v)
      case .negativeInt(let v):
        exp = TimeInterval(v)
      case .float(let v):
        exp = TimeInterval(v)
      case .double(let v):
        exp = v
      case .half(let v):
        exp = TimeInterval(v)
      default:
        // exp claim is present but has invalid type - fail closed
        throw CWTDecodingError.invalidClaims
      }
    }
    
    // Claim 65534 = ttl (optional)
    var ttl: TimeInterval?
    if let ttlCbor = claim(65534),
       case let .unsignedInt(ttlRaw) = ttlCbor {
      ttl = TimeInterval(ttlRaw)
    }

    // Required validations
    try Self.validateClaims(
      subject: sub,
      issuedAt: iat,
      expiration: exp,
      timeToLive: ttl,
      fetchedFrom: fetchedFrom,
      clockSkew: clockSkew
    )

    // Claim 65533 = StatusList CBOR map
    guard let statusListCBOR = claim(65533),
          case let .map(slMap) = statusListCBOR else {
      throw CWTDecodingError.missingStatusList
    }
    
    let dict: [CBOR: CBOR] = Dictionary(uniqueKeysWithValues: slMap.map { ($0.key, $0.value) })
    let statusList = try Self.decodeStatusList(from: dict)
    
    return .init(
      subject: sub,
      issuedAt: iat,
      expirationTime: exp,
      timeToLive: ttl,
      statusList: statusList
    )
  }
  
  private static func decodeCBOR(from data: Data, checkTrailingBytes: Bool = false) throws -> CBOR? {
    // Defense against excessively large input
    guard data.count <= maxInputSize else {
      throw CWTDecodingError.inputTooLarge
    }

    let bytes = [UInt8](data)

    // Use CBOROptions with maximumDepth to prevent stack overflow from deeply nested structures.
    // The unprotected header is not covered by the signature, so an attacker could inject
    // deeply nested CBOR to trigger a stack overflow crash.
    let options = CBOROptions(maximumDepth: maxCBORDepth)
    let stream = TrackingCBORInputStream(bytes: bytes)
    let decoder = CBORDecoder(stream: stream, options: options)

    let item = try decoder.decodeItem()

    // Check for trailing bytes after decoding (security: prevents covert channel / integrity bypass).
    // Trailing bytes are not covered by the COSE signature and could be used for:
    // - Covert channel inside response
    // - Defeating byte-level integrity controls (response hashing, ETags, etc.)
    if checkTrailingBytes && stream.hasRemainingBytes {
      throw CWTDecodingError.trailingBytes
    }

    return item
  }
  
  /// Decode CBOR into StatusList into
  private static func decodeStatusList(from map: [CBOR: CBOR]) throws -> StatusList {
    var bits: BitsPerStatus?
    var lstData: Data?
    var aggregationURI: String?
    
    for (key, value) in map {
      guard case let .utf8String(k) = key else { continue }
      
      switch k {
      case "bits":
        if case let .unsignedInt(b) = value,
           let parsed = BitsPerStatus(rawValue: Int(b)) {
          bits = parsed
        }
        
      case "lst":
        if case let .byteString(bytes) = value {
          lstData = Data(bytes)
        }
        
      case "aggregation_uri":
        if case let .utf8String(uri) = value {
          aggregationURI = uri
        }
        
      default:
        continue
      }
    }
    
    guard let bitsValue = bits else {
      throw CWTDecodingError.invalidBitsValue
    }
    
    guard let lstDataValue = lstData else {
      throw CWTDecodingError.invalidListBytes
    }
    
    // JWT uses base64url, so we match that format here.
    let compressedListB64Url = lstDataValue.base64URLEncodedString()
    
    return .init(
      bytesPerStatus: bitsValue,
      compressedList: compressedListB64Url,
      aggregationUri: aggregationURI
    )
  }

  private static func validateClaims(
    subject: String,
    issuedAt: TimeInterval,
    expiration: TimeInterval?,
    timeToLive: TimeInterval?,
    fetchedFrom: URL?,
    clockSkew: TimeInterval
  ) throws {

    // Compare fetched URI with subject claim to prevent token substitution attacks.
    // The subject claim MUST match the URL used to fetch the token (consistent with JWT path).
    if let fetchedFrom {
      guard fetchedFrom.absoluteString == subject else {
        throw CWTDecodingError.subjectMismatch
      }
    }

    let now = Date().timeIntervalSince1970

    // iat should not be in the future (allow skew)
    if issuedAt > now + clockSkew {
      throw CWTDecodingError.issuedAtInFuture
    }

    // exp must not be expired (allow skew)
    if let exp = expiration,
       exp < now - clockSkew {
      throw CWTDecodingError.expired
    }

    // Enforce TTL: token age must not exceed ttl value
    // TTL defines how many seconds after iat the client should trust the token,
    // taking precedence over HTTP cache headers.
    if let ttl = timeToLive {
      let tokenAge = now - issuedAt
      guard tokenAge <= ttl + clockSkew else {
        throw CWTDecodingError.ttlExceeded
      }
    }

    // Require at least exp OR ttl to be present for freshness guarantee
    // A token without either constraint could be replayed indefinitely.
    if expiration == nil && timeToLive == nil {
      throw CWTDecodingError.noFreshnessConstraint
    }
  }

  private static func validateType(
    protectedHeaderBytes: Data
  ) throws {
    let expected = "application/statuslist+cwt"

    // Protected header is a bstr containing a CBOR map
    // NOTE: typ MUST be in the protected header for integrity protection.
    // Unprotected headers are not signed and can be modified by attackers.
    guard let protected = try? CBORDecoder(input: [UInt8](protectedHeaderBytes)).decodeItem(),
          case let .map(m) = protected,
          let typ = coseTyp(from: m),
          typ == expected else {
      throw CWTDecodingError.invalidType
    }
  }

  // COSE header parameter "typ" has label 16
  private static func coseTyp(from map: OrderedDictionary<CBOR, CBOR>) -> String? {
    for (k, v) in map {
      if case let .unsignedInt(label) = k, label == 16 {
        switch v {
        case .utf8String(let s):
          return s
        case .byteString(let b):
          return String(data: Data(b), encoding: .utf8)
        default:
          return nil
        }
      }
    }
    return nil
  }

}

// MARK: - TrackingCBORInputStream

/// A CBORInputStream wrapper that tracks remaining bytes for trailing bytes detection.
/// This is used to detect when a CBOR structure is followed by extra bytes that are
/// not part of the signed content (potential covert channel or integrity bypass).
private class TrackingCBORInputStream: CBORInputStream {
  private var bytes: ArraySlice<UInt8>

  init(bytes: [UInt8]) {
    self.bytes = ArraySlice(bytes)
  }

  var hasRemainingBytes: Bool {
    return !bytes.isEmpty
  }

  func popByte() throws -> UInt8 {
    guard !bytes.isEmpty else {
      throw CBORError.unfinishedSequence
    }
    return bytes.removeFirst()
  }

  func popBytes(_ n: Int) throws -> ArraySlice<UInt8> {
    guard bytes.count >= n else {
      throw CBORError.unfinishedSequence
    }
    let result = bytes.prefix(n)
    bytes = bytes.dropFirst(n)
    return result
  }
}

extension Data {
  func base64URLEncodedString() -> String {
    self.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
