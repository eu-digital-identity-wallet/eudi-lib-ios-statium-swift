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

  // Added for required validation
  case invalidType
  case subjectMismatch
  case issuedAtInFuture
  case expired
}

public struct CWTDecoder {

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

    let root = try Self.decodeCBOR(from: data)
    
    // Expect COSE_Sign1: tag(18, array[4])
    let coseArray: [CBOR]
    switch root {
    case .tagged(let tag, let value) where tag.rawValue == 18:
      guard case let .array(arr) = value, arr.count == 4 else {
        throw CWTDecodingError.invalidCoseStructure
      }
      coseArray = arr
      
    case .array(let arr) where arr.count == 4:
      coseArray = arr
      
    default:
      throw CWTDecodingError.notCoseSign1
    }

    // COSE_Sign1 structure: [protected, unprotected, payload, signature]
    guard case let .byteString(protectedHeaderBytes) = coseArray[0] else {
      throw CWTDecodingError.invalidCoseStructure
    }

    guard case let .map(unprotectedHeaderMap) = coseArray[1] else {
      throw CWTDecodingError.invalidCoseStructure
    }

    // Validate typ == "application/statuslist+cwt" (protected preferred)
    try Self.validateType(
      protectedHeaderBytes: Data(protectedHeaderBytes),
      unprotectedHeaderMap: unprotectedHeaderMap
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
    
    // Claim 4 = exp (optional)
    var exp: TimeInterval?
    if let expCbor = claim(4),
       case let .unsignedInt(expRaw) = expCbor {
      exp = TimeInterval(expRaw)
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
  
  private static func decodeCBOR(from data: Data) throws -> CBOR? {
    try? CBORDecoder(input: [UInt8](data)).decodeItem()
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
    fetchedFrom: URL?,
    clockSkew: TimeInterval
  ) throws {

    // Compare fetched URI origin (scheme://host[:port]) with subject, if URL is provided.
    if let fetchedFrom {
      let fetchedOrigin = originString(fetchedFrom)
      guard fetchedOrigin == subject else {
        throw CWTDecodingError.subjectMismatch
      }
    }

    let now = Date().timeIntervalSince1970

    // iat should not be in the future (allow skew)
    if issuedAt > now + clockSkew {
      throw CWTDecodingError.issuedAtInFuture
    }

    // exp must exist and must not be expired (allow skew)
    guard let exp = expiration else {
      throw CWTDecodingError.invalidClaims
    }
    if exp < now - clockSkew {
      throw CWTDecodingError.expired
    }
  }

  private static func validateType(
    protectedHeaderBytes: Data,
    unprotectedHeaderMap: OrderedDictionary<CBOR, CBOR>
  ) throws {
    let expected = "application/statuslist+cwt"

    // Protected header is a bstr containing a CBOR map
    if let protected = try? CBORDecoder(input: [UInt8](protectedHeaderBytes)).decodeItem(),
       case let .map(m) = protected,
       let typ = coseTyp(from: m),
       typ == expected {
      return
    }

    // Fallback to unprotected header map
    if let typ = coseTyp(from: unprotectedHeaderMap),
       typ == expected {
      return
    }

    throw CWTDecodingError.invalidType
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

  private static func originString(_ url: URL) -> String {
    var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    comps?.path = ""
    comps?.query = nil
    comps?.fragment = nil
    var s = comps?.string ?? url.absoluteString
    if s.hasSuffix("/") { s.removeLast() }
    return s
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
