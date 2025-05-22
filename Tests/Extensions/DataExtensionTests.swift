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
final class DataExtensionTests {
  
  @Test
  func testBase64URLDecode_WhenValidBase64URLStringProvided_ThenReturnsDecodedData() throws {
    let base64URL = "SFMyNTY=!"
    
    do {
      let decodedData = try Data.base64URLDecode(base64URL)
      let decodedString = String(data: decodedData, encoding: .utf8)
      #expect(decodedString == "HS256")
    } catch {
      #expect(true, "Caught error: \(error). Expected successful decoding.")
    }
  }
  
  @Test
  func testBase64URLDecode_WhenInvalidBase64URLStringProvided_ThenThrowsInvalidJWTError() throws {
    let invalidBase64URL = "invalid.base64.string"
    
    #expect(throws: StatusError.invalidJWT.self) {
      try Data.base64URLDecode(invalidBase64URL)
    }
  }
  
  @Test
  func testBase64URLDecode_WhenEmptyStringProvided_ThenReturnsEmptyData() throws {
    let emptyBase64URL = ""
    let decodedData = try Data.base64URLDecode(emptyBase64URL)
    
    #expect(decodedData.count == 0)
  }
}
