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
import Compression

public extension Data {
  
  /// Decompresses the data using the ZLIB compression algorithm.
  ///
  /// This computed property attempts to decompress the data (excluding the first two bytes, which are assumed to be part of the ZLIB header).
  /// It uses the `compression_decode_buffer` function to decode the compressed data into a decompressed `Data` object.
  ///
  /// - Returns: A `Data` object containing the decompressed data.
  ///
  /// Example:
  /// ```
  /// let compressedData: Data = ...
  /// let decompressedData = compressedData.decompressed
  /// ```
  var decompressed: Data {
    let size = 8_000_000
    let buffer = UnsafeMutablePointer<Byte>.allocate(capacity: size)
    let result = subdata(in: 2 ..< count).withUnsafeBytes({
      let read = compression_decode_buffer(
        buffer,
        size,
        $0.baseAddress!.bindMemory(
          to: Byte.self,
          capacity: 1
        ),
        count - 2,
        nil,
        COMPRESSION_ZLIB
      )
      return Data(bytes: buffer, count: read)
    })
    buffer.deallocate()
    return result
  }
  
  /// Decodes a Base64URL string into a byte array ([UInt8]).
  /// - Parameter base64Url: The Base64URL encoded string.
  /// - Returns: An optional `[UInt8]` array if decoding is successful.
  static func fromBase64URL(_ base64Url: String) -> [UInt8]? {
    var base64 = base64Url
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    
    // Add padding if necessary
    let paddingLength = (4 - (base64.count % 4)) % 4
    base64 += String(repeating: "=", count: paddingLength)
    
    // Convert to Data
    guard let data = Data(base64Encoded: base64) else { return nil }
    
    return [UInt8](data)
  }
}
