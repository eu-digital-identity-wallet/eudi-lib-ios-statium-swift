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

/// An enumeration that represents the number of bits used per status.
///
/// The enum defines the allowed bit sizes for status values, which are typically used to control
/// the size of each status in a byte array. The possible values are 1, 2, 4, and 8 bits per status.
public enum BitsPerStatus: Int, Codable, Sendable {

  /// Represents 1 bit per status.
  case one = 1

  /// Represents 2 bits per status.
  case two = 2

  /// Represents 4 bits per status.
  case four = 4

  /// Represents 8 bits per status.
  case eight = 8

  /// Custom decoding to ensure that only valid values (1, 2, 4, 8) are allowed.
  ///
  /// This initializer allows `BitsPerStatus` to be decoded from an external data source. If the decoded
  /// value is not one of the allowed cases (1, 2, 4, or 8), it throws a `DecodingError.dataCorruptedError`.
  ///
  /// - Parameter decoder: The decoder used to decode the value.
  /// - Throws: A `DecodingError` if the decoded value is not valid.
  ///
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(Int.self)

    // Ensure the decoded value matches one of the valid cases
    guard
      let validCase = BitsPerStatus(rawValue: value)
    else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid value \(value). Allowed values: 1, 2, 4, 8."
      )
    }
    self = validCase
  }

  /// Custom encoding to encode the raw value of `BitsPerStatus`.
  ///
  /// This method encodes the raw integer value (1, 2, 4, or 8) when encoding a `BitsPerStatus` to an external
  /// data source. It ensures that the `BitsPerStatus` is serialized correctly.
  ///
  /// - Parameter encoder: The encoder used to encode the value.
  /// - Throws: A `EncodingError` if the encoding fails.
  ///
  /// Example usage:
  /// ```swift
  /// let encodedData = try JSONEncoder().encode(bitsPerStatus)
  /// ```
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(self.rawValue)
  }
}
