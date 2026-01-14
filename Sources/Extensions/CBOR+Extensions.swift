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

extension CBOR {
  func toSwift() -> Any {
    switch self {
    case .unsignedInt(let value):
      return value
    case .negativeInt(let value):
      return value
    case .utf8String(let value):
      return value
    case .byteString(let bytes):
      return Data(bytes)
    case .array(let array):
      return array.map { $0.toSwift() }
    case .map(let dict):
      return Dictionary(uniqueKeysWithValues: dict.map { (key, value) in
        (key.toSwiftKey(), value.toSwift())
      })
    case .tagged(_, let wrapped):
      // For your use case, just unwrap the inner value
      return wrapped.toSwift()
    default:
      return String(describing: self)
    }
  }
  
  fileprivate func toSwiftKey() -> String {
    switch self {
    case .utf8String(let str): return str
    case .unsignedInt(let int): return "\(int)"
    case .negativeInt(let int): return "\(int)"
    default: return String(describing: self)
    }
  }
}
