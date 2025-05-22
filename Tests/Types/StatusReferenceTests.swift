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
final class StatusReferenceTests {
  
  @Test
  func testInit_WhenURLStringIsValid_ThenReturnsInstanceWithCorrectValues() throws {
    let statusReference = StatusReference(idx: 1, uriString: "https://statium.com")
    
    #expect(statusReference?.idx == 1)
    #expect(statusReference?.uri.absoluteString == "https://statium.com")
  }
  
  @Test
  func testInit_WhenURLStringIsInvalid_ThenReturnsInstanceWithOriginalString() throws {
    let statusReference = StatusReference(idx: 1, uriString: "invalid_url_string")
    
    #expect(statusReference != nil)
    #expect(statusReference?.uri.absoluteString == "invalid_url_string")
  }
  
  @Test
  func testInit_WhenURLStringIsEmpty_ThenReturnsNil() throws {
    let statusReference = StatusReference(idx: 1, uriString: "")
    
    #expect(statusReference == nil)
  }
  
  @Test
  func testDecodable_WhenJSONIsValid_ThenDecodesCorrectly() throws {
    let json = """
          {
              "idx": 1,
              "uri": "https://statium.com"
          }
          """
    
    let data = json.data(using: .utf8)!
    let statusReference = try JSONDecoder().decode(StatusReference.self, from: data)
    
    #expect(statusReference.idx == 1)
    #expect(statusReference.uri.absoluteString == "https://statium.com")
  }

  @Test
  func testEncodable_WhenEncoded_ThenProducesCorrectJSON() throws {
    let statusReference = StatusReference(idx: 1, uri: URL(string: "https://statium.com")!)
    let encodedData = try JSONEncoder().encode(statusReference)
    let jsonString = String(data: encodedData, encoding: .utf8)
    
    let expectedDict: [String: Any] = ["idx": 1, "uri": "https://statium.com"]
    
    let data = jsonString?.data(using: .utf8)!
    let decodedDict = try JSONSerialization.jsonObject(with: data!, options: []) as? [String: Any]
    
    #expect(decodedDict?["idx"] as? Int == expectedDict["idx"] as? Int)
    #expect(decodedDict?["uri"] as? String == expectedDict["uri"] as? String)
  }
}
