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

@testable import StatiumSwift

@Suite
final class BitsPerStatusTests {

  @Test
  func testBitsPerStatusEncoding() throws {

    let bitsPerStatus: BitsPerStatus = .four
    let encodedData = try JSONEncoder().encode(bitsPerStatus)
    let decodedValue = try JSONDecoder().decode(Int.self, from: encodedData)

    #expect(decodedValue == bitsPerStatus.rawValue)
  }

  @Test
  func testInvalidBitsPerStatusEncoding() throws {
    let invalidRawValue = 3
    let jsonData = try JSONEncoder().encode(invalidRawValue)

    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(BitsPerStatus.self, from: jsonData)
    }
  }
}
