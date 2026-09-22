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
final class JWTTests {
  
  @Test
  func testInitWithValidJWT_WhenGivenCorrectJWT_ThenHeaderContainsCorrectAlg() throws {
    let validJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    
    let jwt = try JWT(compactJWT: validJWT)
    
    if let alg = jwt.header["alg"] as? String {
      #expect(alg == "HS256")
    }
  }
  
  @Test
  func testInitWithJWT_WhenGivenSingleSegmentJWT_ThenThrowsInvalidJWTError() throws {
    let invalidJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    
    #expect(throws: StatusError.invalidJWT.self) {
      try JWT(compactJWT: invalidJWT)
    }
  }
  
  @Test
  func testInitWithJWT_WhenGivenTwoSegmentsJWT_ThenThrowsInvalidJWTError() throws {
    let invalidJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ"
    
    #expect(throws: StatusError.invalidJWT.self) {
      try JWT(compactJWT: invalidJWT)
    }
  }
  
  @Test
  func testInitWithJWT_WhenGivenMalformedSegments_ThenThrowsInvalidJWTError() throws {
    let invalidJWT = "eyJhbGciOiJIUzI1NIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMef36POk6yJV_adQssw5c"
    
    #expect(throws: StatusError.invalidJWT.self) {
      try JWT(compactJWT: invalidJWT)
    }
  }
  
  @Test
  func testInitWithJWT_WhenGivenCorruptedBase64_ThenThrowsInvalidJWTError() throws {
    let invalidJWT = "invalid-@@.jwt.signature"
    
    #expect(throws: StatusError.invalidJWT.self) {
      try JWT(compactJWT: invalidJWT)
    }
  }
  
  @Test
  func testInitWithJWT_WhenGivenInvalidJSONHeader_ThenThrowsInvalidJWTError() throws {
    let invalidJWT = "aW52YWxpZA.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

    #expect(throws: StatusError.invalidJWT.self) {
      try JWT(compactJWT: invalidJWT)
    }
  }

  // MARK: - Algorithm Policy Tests

  /// Verify that JWT with alg: none is rejected.
  @Test
  func testInitWithJWT_WhenAlgIsNone_ThenThrowsAlgorithmNoneNotAllowed() throws {
    // Header: {"alg":"none","typ":"JWT"} -> eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0
    // Payload: {"sub":"1234567890"} -> eyJzdWIiOiIxMjM0NTY3ODkwIn0
    // Signature: empty but we need something to pass segment count check
    let algNoneJWT = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dummysig"

    #expect(throws: StatusError.algorithmNoneNotAllowed) {
      try JWT(compactJWT: algNoneJWT)
    }
  }

  /// Verify that JWT with alg: NONE (uppercase) is also rejected.
  @Test
  func testInitWithJWT_WhenAlgIsNoneUppercase_ThenThrowsAlgorithmNoneNotAllowed() throws {
    // Header: {"alg":"NONE","typ":"JWT"} -> eyJhbGciOiJOT05FIiwidHlwIjoiSldUIn0
    let algNoneUpperJWT = "eyJhbGciOiJOT05FIiwidHlwIjoiSldUIn0.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dummysig"

    #expect(throws: StatusError.algorithmNoneNotAllowed) {
      try JWT(compactJWT: algNoneUpperJWT)
    }
  }

  /// Verify that JWT with empty signature is rejected.
  @Test
  func testInitWithJWT_WhenSignatureIsEmpty_ThenThrowsMissingSignature() throws {
    // Valid header and payload, but empty signature segment
    // Header: {"alg":"HS256","typ":"JWT"}
    // Payload: {"sub":"1234567890"}
    // Signature: (empty string)
    let emptySignatureJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0."

    #expect(throws: StatusError.missingSignature) {
      try JWT(compactJWT: emptySignatureJWT)
    }
  }

  /// Verify that JWT with valid algorithm and signature is accepted.
  @Test
  func testInitWithJWT_WhenAlgIsValidAndSignaturePresent_ThenSucceeds() throws {
    let validJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

    let jwt = try JWT(compactJWT: validJWT)

    #expect(jwt.header["alg"] as? String == "HS256")
    #expect(jwt.signature != nil)
    #expect(jwt.signature?.isEmpty == false)
  }
}
