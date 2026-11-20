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
import Compression

@testable import StatiumSwift

@Suite
final class ReadStatusTests {

  @Test
  func testBitsPerStatusOneOps() async throws {
    // Example 1: 1 bit per status
    // In this case, each bit represents a status (0 or 1)
    // Byte: 10101010 (binary) = 0xAA (hex) = 170 (decimal)
    // Status at index 0: 0 (rightmost bit)
    // Status at index 1: 1
    // Status at index 2: 0
    // Status at index 3: 1
    // Status at index 4: 0
    // Status at index 5: 1
    // Status at index 6: 0
    // Status at index 7: 1 (leftmost bit)

    let readStatus = ReadStatus(bitsPerStatus: .one, byteArray: [0xaa])

    #expect(try await readStatus.readStatus(at: 0) == 0)
    #expect(try await readStatus.readStatus(at: 1) == 1)
    #expect(try await readStatus.readStatus(at: 2) == 0)
    #expect(try await readStatus.readStatus(at: 3) == 1)
    #expect(try await readStatus.readStatus(at: 4) == 0)
    #expect(try await readStatus.readStatus(at: 5) == 1)
    #expect(try await readStatus.readStatus(at: 6) == 0)
    #expect(try await readStatus.readStatus(at: 7) == 1)
  }

  @Test
  func testBitsPerStatusOneOps2() async throws {
    // Test with multiple bytes
    // Byte 0: 10101010 (0xAA)
    // Byte 1: 11001100 (0xCC)
    let readStatus = ReadStatus(bitsPerStatus: .one, byteArray: [0xaa, 0xcc])

    // First byte (index 0-7)
    #expect(try await readStatus.readStatus(at: 0) == 0)
    #expect(try await readStatus.readStatus(at: 1) == 1)
    #expect(try await readStatus.readStatus(at: 2) == 0)
    #expect(try await readStatus.readStatus(at: 3) == 1)
    #expect(try await readStatus.readStatus(at: 4) == 0)
    #expect(try await readStatus.readStatus(at: 5) == 1)
    #expect(try await readStatus.readStatus(at: 6) == 0)
    #expect(try await readStatus.readStatus(at: 7) == 1)

    // Second byte (index 8-15)
    #expect(try await readStatus.readStatus(at: 8) == 0)
    #expect(try await readStatus.readStatus(at: 9) == 0)
    #expect(try await readStatus.readStatus(at: 10) == 1)
    #expect(try await readStatus.readStatus(at: 11) == 1)
    #expect(try await readStatus.readStatus(at: 12) == 0)
    #expect(try await readStatus.readStatus(at: 13) == 0)
    #expect(try await readStatus.readStatus(at: 14) == 1)
    #expect(try await readStatus.readStatus(at: 15) == 1)
  }

  @Test
  func testBitsPerStatusTwoOps() async throws {
    // Example 2: 2 bits per status
    // In this case, each 2 bits represent a status (0-3)
    // Byte: 11100100 (binary) = 0xE4 (hex) = 228 (decimal)
    // Status at index 0: 00 (binary) = 0 (decimal)
    // Status at index 1: 01 (binary) = 1 (decimal)
    // Status at index 2: 10 (binary) = 2 (decimal)
    // Status at index 3: 11 (binary) = 3 (decimal)
    let readStatus = ReadStatus(bitsPerStatus: .two, byteArray: [0xe4])

    #expect(try await readStatus.readStatus(at: 0) == 0)
    #expect(try await readStatus.readStatus(at: 1) == 1)
    #expect(try await readStatus.readStatus(at: 2) == 2)
    #expect(try await readStatus.readStatus(at: 3) == 3)
  }

  @Test
  func testBitsPerStatusTwoOps2() async throws {
    // Test with multiple bytes
    // Byte 0: 11100100 (0xE4)
    // Byte 1: 10011011 (0x9B)

    let readStatus = ReadStatus(bitsPerStatus: .two, byteArray: [0xe4, 0x9b])

    #expect(try await readStatus.readStatus(at: 0) == 0)
    #expect(try await readStatus.readStatus(at: 1) == 1)
    #expect(try await readStatus.readStatus(at: 2) == 2)
    #expect(try await readStatus.readStatus(at: 3) == 3)
    #expect(try await readStatus.readStatus(at: 4) == 3)
    #expect(try await readStatus.readStatus(at: 5) == 2)
    #expect(try await readStatus.readStatus(at: 6) == 1)
    #expect(try await readStatus.readStatus(at: 7) == 2)
  }

  @Test
  func testBitsPerStatusFourOps() async throws {
    // Example 3: 4 bits per status
    // In this case, each 4 bits (nibble) represent a status (0-15)
    // Byte: 11110000 (binary) = 0xF0 (hex) = 240 (decimal)
    // Status at index 0: 0000 (binary) = 0 (decimal)
    // Status at index 1: 1111 (binary) = 15 (decimal)
    let readStatus = ReadStatus(bitsPerStatus: .four, byteArray: [0xf0])

    #expect(try await readStatus.readStatus(at: 0) == 0)
    #expect(try await readStatus.readStatus(at: 1) == 15)
  }

  @Test
  func testBitsPerStatusFourOps2() async throws {
    // Test with multiple bytes
    // Byte 0: 11110000 (0xF0)
    // Byte 1: 10100101 (0xA5)
    let readStatus = ReadStatus(bitsPerStatus: .four, byteArray: [0xf0, 0xa5])

    // First byte (index 0-1)
    #expect(try await readStatus.readStatus(at: 0) == 0)
    #expect(try await readStatus.readStatus(at: 1) == 15)

    // Second byte (index 2-3)
    #expect(try await readStatus.readStatus(at: 2) == 5)
    #expect(try await readStatus.readStatus(at: 3) == 10)
  }

  @Test
  func testBitsPerStatusEightOps() async throws {
    // Example 4: 8 bits per status
    // In this case, each byte represents a status (0-255)
    // Byte 0: 11111111 (binary) = 0xFF (hex) = 255 (decimal)
    // Byte 1: 00000000 (binary) = 0x00 (hex) = 0 (decimal)
    // Byte 2: 10101010 (binary) = 0xAA (hex) = 170 (decimal)
    let readStatus = ReadStatus(bitsPerStatus: .eight, byteArray: [0xff, 0x00, 0xaa])

    #expect(try await readStatus.readStatus(at: 0) == 255)
    #expect(try await readStatus.readStatus(at: 1) == 0)
    #expect(try await readStatus.readStatus(at: 2) == 170)
  }

  @Test
  func testNegativeIndexThrowsOutOfRange() async {
    // Draft 20 §8.3: Negative index MUST be rejected
    let readStatus = ReadStatus(bitsPerStatus: .one, byteArray: [0x00])

    await #expect(throws: StatusError.outOfRange) {
      _ = try await readStatus.readStatus(at: -1)
    }
  }

  @Test
  func testOutOfBoundsIndexThrowsOutOfRange() async {
    // Draft 20 §8.3: When idx is out of bounds, the verifier MUST reject
    let readStatus = ReadStatus(bitsPerStatus: .one, byteArray: [0xaa])

    // Index 8 is out of bounds for a single byte with 1 bit per status
    await #expect(throws: StatusError.outOfRange) {
      _ = try await readStatus.readStatus(at: 8)
    }

    // Test with 2 bits per status - 4 statuses per byte, so index 4 is out of bounds
    let readStatus2 = ReadStatus(bitsPerStatus: .two, byteArray: [0xe4])
    await #expect(throws: StatusError.outOfRange) {
      _ = try await readStatus2.readStatus(at: 4)
    }

    // Test with 4 bits per status - 2 statuses per byte, so index 2 is out of bounds
    let readStatus4 = ReadStatus(bitsPerStatus: .four, byteArray: [0xf0])
    await #expect(throws: StatusError.outOfRange) {
      _ = try await readStatus4.readStatus(at: 2)
    }

    // Test with 8 bits per status - 1 status per byte, so index 1 is out of bounds for 1 byte
    let readStatus8 = ReadStatus(bitsPerStatus: .eight, byteArray: [0xff])
    await #expect(throws: StatusError.outOfRange) {
      _ = try await readStatus8.readStatus(at: 1)
    }
  }
}
