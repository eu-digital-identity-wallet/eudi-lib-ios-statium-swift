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
  /// Compatibility notes (preserved):
  /// - Still skips the first 2 bytes (`subdata(in: 2..<count)`), matching your original behavior.
  /// - Still exposes a *computed property* `decompressed: Data` (non-throwing).
  /// - On failure, returns empty `Data()` (so existing call sites keep working).
  ///
  /// Security fix:
  /// - Uses streaming decompression with a dynamically sized output buffer to avoid silent truncation
  ///   when the decompressed output exceeds a fixed buffer size.
  ///
  /// - Parameter maxOutputSize: Safety cap to avoid memory DoS (tune as needed).
  var decompressed: Data {
    // Keep non-throwing API for compatibility.
    (try? decompressedZlibStreaming(maxOutputSize: 128 * 1024 * 1024)) ?? Data()
  }

  /// Streaming ZLIB decompression (dynamic output).
  /// This is internal/private-ish to preserve the original public surface area.
  private func decompressedZlibStreaming(
    chunkSize: Int = 64 * 1024,
    maxOutputSize: Int
  ) throws -> Data {

    enum DecompressionError: Error {
      case invalidInput
      case initializationFailed
      case corruptedData
      case outputTooLarge
    }

    guard count > 2 else { throw DecompressionError.invalidInput }
    let input = subdata(in: 2 ..< count)

    // Some SDKs expose compression_stream fields as non-optional pointers, so we can't init with nil.
    // Provide dummy pointers (they'll be overwritten before use).
    let dummyDst = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
    let dummySrcMut = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
    let dummySrc = UnsafePointer<UInt8>(dummySrcMut)

    defer {
      dummyDst.deallocate()
      dummySrcMut.deallocate()
    }

    var stream = compression_stream(
      dst_ptr: dummyDst,
      dst_size: 0,
      src_ptr: dummySrc,
      src_size: 0,
      state: nil
    )

    var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
    guard status != COMPRESSION_STATUS_ERROR else {
      throw DecompressionError.initializationFailed
    }
    defer { compression_stream_destroy(&stream) }

    var output = Data()

    return try input.withUnsafeBytes { srcRaw -> Data in
      guard let srcBase = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        throw DecompressionError.invalidInput
      }

      stream.src_ptr = srcBase
      stream.src_size = input.count

      var dstBuffer = [UInt8](repeating: 0, count: chunkSize)

      while true {
        var produced = 0

        status = try dstBuffer.withUnsafeMutableBytes { dstRaw -> compression_status in
          guard let dstBase = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            throw DecompressionError.corruptedData
          }

          stream.dst_ptr = dstBase
          stream.dst_size = dstRaw.count

          let st = compression_stream_process(&stream, 0)

          // Compute produced using dstRaw.count to avoid overlapping access errors.
          produced = dstRaw.count - stream.dst_size
          return st
        }

        if produced > 0 {
          if output.count + produced > maxOutputSize {
            throw DecompressionError.outputTooLarge
          }
          output.append(dstBuffer, count: produced)
        }

        switch status {
        case COMPRESSION_STATUS_OK:
          continue
        case COMPRESSION_STATUS_END:
          return output
        default:
          throw DecompressionError.corruptedData
        }
      }
    }
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
