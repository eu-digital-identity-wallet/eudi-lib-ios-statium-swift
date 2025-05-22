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

import Foundation

internal struct JWT {
  let header: [String: Any]
  let payload: Data
  let signature: Data?
  
  init(compactJWT: String) throws {
    let segments = compactJWT.components(separatedBy: ".")
    guard segments.count == 3 else {
      throw StatusError.invalidJWT
    }
    
    let headerData = try Data.base64URLDecode(segments[0])
    let payloadData = try Data.base64URLDecode(segments[1])
    let signatureData = try Data.base64URLDecode(segments[2])
    
    let headerJSON = try? JSONSerialization.jsonObject(with: headerData, options: [])
    guard let headerDict = headerJSON as? [String: Any] else {
      throw StatusError.invalidJWT
    }
    self.header = headerDict
    
    self.payload = payloadData
    self.signature = signatureData
  }
}

extension Data {
  static func base64URLDecode(_ str: String) throws -> Data {
    var base64 = str
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    
    let paddingLength = 4 - base64.count % 4
    if paddingLength < 4 {
      base64 += String(repeating: "=", count: paddingLength)
    }
    
    guard let data = Data(base64Encoded: base64) else {
      throw StatusError.invalidJWT
    }
    
    return data
  }
}

