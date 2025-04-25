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
  func testValidJWTDecoding() throws {
    let validJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    
    let jwt = try JWT(compactJWT: validJWT)
    
    if let alg = jwt.header["alg"] as? String {
      #expect(alg == "HS256")
    }
  }
  
  @Test
  func testInvalidJWTDecoding() throws {
    let invalidJWT = "invalid.jwt"
    
    #expect(throws: StatusError.invalidJWT.self) {
      try JWT(compactJWT: invalidJWT)
    }
  }
}
