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

/// A concurrency-safe actor that provides methods to read status information
/// from a byte array, given the number of bits per status (defined by `BitsPerStatus`).
///
/// This actor takes a `BitsPerStatus` object and a byte array, and offers a method to retrieve
/// a specific status byte at a given index, factoring in bit positions for the status bytes.
public actor ReadStatus {

  /// The number of bits used per status in the byte array.
  public let bitsPerStatus: BitsPerStatus

  /// The byte array containing the status data.
  public let byteArray: [UInt8]

  /// Initializes a `ReadStatus` actor with the given `BitsPerStatus` and byte array.
  ///
  /// - Parameters:
  ///   - bitsPerStatus: A `BitsPerStatus` value that defines how many bits are used per status.
  ///   - byteArray: A byte array that contains the status data.
  ///
  /// This initializer sets up the actor with the necessary configuration for reading status data.
  public init(bitsPerStatus: BitsPerStatus, byteArray: [UInt8]) {
    self.bitsPerStatus = bitsPerStatus
    self.byteArray = byteArray
  }

  /// Reads the status at the specified index from the byte array.
  ///
  /// The function uses the `bitsPerStatus` to calculate the byte and bit positions of the status
  /// at the given index and extracts the value of the status byte accordingly.
  ///
  /// - Parameter index: The index of the status in the byte array.
  /// - Returns: An optional `Byte` value representing the status at the given index, or `nil` if the index is out of bounds or invalid.
  ///
  /// Example usage:
  /// ```swift
  /// let readStatus = ReadStatus(bitsPerStatus: .four, byteArray: [0xff])
  /// let status = await readStatus.readStatus(at: 2)
  /// print(status) // Prints the byte value at index 2
  /// ```
  public func readStatus(at index: Int) -> Byte? {

    // Ensure the index is non-negative.
    guard index >= .zero else {
      return nil
    }

    // Calculate the byte and bit position for the given index.
    let (bytePosition, bitPosition) = bitsPerStatus.byteAndBitPosition(
      index: UInt(index)
    )

    // Attempt to retrieve the byte from the byte array.
    guard let byte = byteArray[safe: Int(bytePosition)] else {
      return nil
    }

    // Read the status byte based on the bit position.
    let status = bitsPerStatus.readStatusByte(
      statusByte: byte,
      bitPosition: UInt8(bitPosition)
    )
    return status
  }
}

extension BitsPerStatus {

  /// Calculates the byte position and bit position for a given status index.
  ///
  /// This function breaks down the index into a byte position and a bit position
  /// based on the number of bits used per status. This helps in locating the exact
  /// bit in the byte array to read the status.
  ///
  /// - Parameter index: The index of the status.
  /// - Returns: A tuple containing the byte position and bit position for the status.
  ///
  func byteAndBitPosition(index: UInt) -> (Int, Int) {
    let statusesPerByte = 8 / self.rawValue
    let bytePosition = Int(index) / statusesPerByte
    let bitPosition: Int = {
      let positionInByte = Int(index) % statusesPerByte
      return positionInByte * self.rawValue
    }()
    return (bytePosition, bitPosition)
  }

  /// Reads a status byte at a specific bit position within the byte.
  ///
  /// This function extracts the status value from a byte by applying a bit mask
  /// to isolate the correct bit at the given position.
  ///
  /// - Parameter statusByte: The byte containing the status data.
  /// - Parameter bitPosition: The bit position within the byte to extract the status.
  /// - Returns: A `Byte` representing the status at the specified bit position.
  ///
  func readStatusByte(
    statusByte: Byte,
    bitPosition: Byte
  ) -> Byte {
    // Define the base mask for the status based on the bits per status.
    let baseMask: Int = switch self {
    case .one: 0b00000001
    case .two: 0b00000011
    case .four: 0b00001111
    case .eight: 0b11111111
    }

    // Use the bit mask to isolate the relevant status bit and shift it to the right.
    let statusValue = (Int(statusByte) & (baseMask << bitPosition)) >> bitPosition
    return Byte(statusValue)
  }
}
