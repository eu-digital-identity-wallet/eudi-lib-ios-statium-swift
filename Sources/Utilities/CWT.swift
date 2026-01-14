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
 * distributed unclearder the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import Foundation
import SwiftCBOR

public enum CWTDecodingError: Error {
  case notCoseSign1
  case invalidCoseStructure
  case invalidPayload
  case invalidClaims
  case missingStatusList
  case invalidBitsValue
  case invalidListBytes
}

public struct CWTDecoder {
  
  public init() {}
  
  public func decodeStatusListToken(from data: Data) throws -> StatusListTokenClaims {
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
    
    // Claim 65533 = StatusList CBOR map
    guard let statusListCBOR = claim(65533),
          case let .map(slMap) = statusListCBOR else {
      throw CWTDecodingError.missingStatusList
    }
    
    let statusList = try Self.decodeStatusList(from: slMap)
    
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
}

extension Data {
  func base64URLEncodedString() -> String {
    self.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
