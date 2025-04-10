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

@testable import eudi_lib_ios_statium_swift

final class ReadStatusTests {
  
  @Test
  func testBitsPerStatusOneOps() async {
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
    var result: Byte? = nil
    
    result = await readStatus.readStatus(at: 0)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 1)
    #expect(result == 1)
    
    result = await readStatus.readStatus(at: 2)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 3)
    #expect(result == 1)
    
    result = await readStatus.readStatus(at: 4)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 5)
    #expect(result == 1)
    
    result = await readStatus.readStatus(at: 6)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 7)
    #expect(result == 1)
  }
  
  @Test
  func testBitsPerStatusOneOps2() async {
    // Test with multiple bytes
    // Byte 0: 10101010 (0xAA)
    // Byte 1: 11001100 (0xCC)
    let readStatus = ReadStatus(bitsPerStatus: .one, byteArray: [0xaa, 0xcc])
    var result: Byte? = nil
    
    // First byte (index 0-7)
    result = await readStatus.readStatus(at: 0)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 1)
    #expect(result == 1)
    
    result = await readStatus.readStatus(at: 2)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 3)
    #expect(result == 1)
    
    result = await readStatus.readStatus(at: 4)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 5)
    #expect(result == 1)
    
    result = await readStatus.readStatus(at: 6)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 7)
    #expect(result == 1)
    
    // Second byte (index 8-15)
    result = await readStatus.readStatus(at: 8)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 9)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 10)
    #expect(result == 1)
    
    result = await readStatus.readStatus(at: 11)
    #expect(result == 1)
    
    result = await readStatus.readStatus(at: 12)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 13)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 14)
    #expect(result == 1)
    
    result = await readStatus.readStatus(at: 15)
    #expect(result == 1)
  }
  
  @Test
  func testBitsPerStatusTwoOps() async {
    // Example 2: 2 bits per status
    // In this case, each 2 bits represent a status (0-3)
    // Byte: 11100100 (binary) = 0xE4 (hex) = 228 (decimal)
    // Status at index 0: 00 (binary) = 0 (decimal)
    // Status at index 1: 01 (binary) = 1 (decimal)
    // Status at index 2: 10 (binary) = 2 (decimal)
    // Status at index 3: 11 (binary) = 3 (decimal)
    let readStatus = ReadStatus(bitsPerStatus: .two, byteArray: [0xe4])
    var result: Byte? = nil
    
    result = await readStatus.readStatus(at: 0)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 1)
    #expect(result == 1)
    
    result = await readStatus.readStatus(at: 2)
    #expect(result == 2)
    
    result = await readStatus.readStatus(at: 3)
    #expect(result == 3)
  }
  
  @Test
  func testBitsPerStatusTwoOps2() async {
    
    // Test with multiple bytes
    // Byte 0: 11100100 (0xE4)
    // Byte 1: 10011011 (0x9B)
    
    let readStatus = ReadStatus(bitsPerStatus: .two, byteArray: [0xe4, 0x9b])
    var result: Byte? = nil
    
    result = await readStatus.readStatus(at: 0)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 1)
    #expect(result == 1)
    
    result = await readStatus.readStatus(at: 2)
    #expect(result == 2)
    
    result = await readStatus.readStatus(at: 3)
    #expect(result == 3)
    
    result = await readStatus.readStatus(at: 4)
    #expect(result == 3)
    
    result = await readStatus.readStatus(at: 5)
    #expect(result == 2)
    
    result = await readStatus.readStatus(at: 6)
    #expect(result == 1)
    
    result = await readStatus.readStatus(at: 7)
    #expect(result == 2)
  }
  
  @Test
  func testBitsPerStatusFourOps() async {
    // Example 3: 4 bits per status
    // In this case, each 4 bits (nibble) represent a status (0-15)
    // Byte: 11110000 (binary) = 0xF0 (hex) = 240 (decimal)
    // Status at index 0: 0000 (binary) = 0 (decimal)
    // Status at index 1: 1111 (binary) = 15 (decimal)
    let readStatus = ReadStatus(bitsPerStatus: .four, byteArray: [0xf0])
    var result: Byte? = nil
    
    result = await readStatus.readStatus(at: 0)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 1)
    #expect(result == 15)
  }
  
  @Test
  func testBitsPerStatusFourOps2() async {
    // Test with multiple bytes
    // Byte 0: 11110000 (0xF0)
    // Byte 1: 10100101 (0xA5)
    let readStatus = ReadStatus(bitsPerStatus: .four, byteArray: [0xf0, 0xa5])
    var result: Byte? = nil
    
    // First byte (index 0-1)
    result = await readStatus.readStatus(at: 0)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 1)
    #expect(result == 15)
    
    // Second byte (index 2-3)
    result = await readStatus.readStatus(at: 2)
    #expect(result == 5)
    
    result = await readStatus.readStatus(at: 3)
    #expect(result == 10)
  }
  
  @Test
  func testBitsPerStatusEightOps() async {
    // Example 4: 8 bits per status
    // In this case, each byte represents a status (0-255)
    // Byte 0: 11111111 (binary) = 0xFF (hex) = 255 (decimal)
    // Byte 1: 00000000 (binary) = 0x00 (hex) = 0 (decimal)
    // Byte 2: 10101010 (binary) = 0xAA (hex) = 170 (decimal)
    let readStatus = ReadStatus(bitsPerStatus: .eight, byteArray: [0xff, 0x00, 0xaa])
    var result: Byte? = nil
    
    result = await readStatus.readStatus(at: 0)
    #expect(result == 255)
    
    result = await readStatus.readStatus(at: 1)
    #expect(result == 0)
    
    result = await readStatus.readStatus(at: 2)
    #expect(result == 170)
  }
  
  @Test
  func testNegativeIndexOps() async {
    let readStatus = ReadStatus(bitsPerStatus: .one, byteArray: [0x00])
    var result: Byte? = nil
    
    result = await readStatus.readStatus(at: -1)
    #expect(result == nil)
  }
}

