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
import XCTest
import Compression

@testable import eudi_lib_ios_statium_swift

final class GetStatusTests: XCTestCase {
  
  func testStatusListToken() async throws {
    
    guard let statusReference: StatusReference = .init(
      idx: 1,
      uriString: TestsConstants.testStatusUrlString
    ) else {
      XCTFail("Cannot decode status reference")
      return
    }
    
    let getStatusToken = GetStatusListToken(
      verifier: VerifyStatusListTokenSignatureFactory.make(),
      date: Date()
    )
    
    let result = await getStatusToken.getStatusClaims(url: statusReference.uri)
    switch result {
    case .success(let claims):
      XCTAssert(true)
    case .failure:
      XCTAssert(false, "Invalid status")
    }
  }
  
  func testStatusListFlowValid() async throws {
    
    guard let statusReference: StatusReference = .init(
      idx: 1,
      uriString: TestsConstants.testStatusUrlString
    ) else {
      XCTFail("Cannot decode status reference")
      return
    }
    
    let getStatus = GetStatus()
    let getStatusToken = GetStatusListToken(
      verifier: VerifyStatusListTokenSignatureFactory.make()
    )
    
    let result = await getStatus.getStatus(
      index: statusReference.idx,
      url: statusReference.uri,
      fetchClaims: getStatusToken.getStatusClaims
    )
    
    switch result {
    case .success(let status):
      switch status {
      case .valid:
        XCTAssert(true)
      case .invalid:
        XCTAssert(false)
      case .suspended:
        XCTAssert(false)
      case .applicationSpecific(_):
        XCTAssert(false)
      case .reserved(_):
        XCTAssert(false)
      }
      
    case .failure:
      XCTAssert(false, "Invalid status")
    }
  }
  
  func testStatusListFlowValidWithStatusReference() async throws {
    
    let getStatus = GetStatus()
    let getStatusToken = GetStatusListToken(
      verifier: VerifyStatusListTokenSignatureFactory.make()
    )
    
    let result = await getStatus.getStatus(
      reference: .init(
        idx: 1,
        uriString: TestsConstants.testStatusUrlString
      )!,
      fetchClaims: getStatusToken.getStatusClaims
    )
    
    switch result {
    case .success(let status):
      XCTAssert(status == .valid)
    case .failure:
      XCTAssert(false, "Invalid status")
    }
  }
  
  func testStatusListFlowInvalid() async throws {
    
    guard let statusReference: StatusReference = .init(
      idx: 2000,
      uriString: TestsConstants.testStatusUrlString
    ) else {
      XCTFail("Cannot decode status reference")
      return
    }
    
    let getStatus = GetStatus()
    let getStatusToken = GetStatusListToken(
      verifier: VerifyStatusListTokenSignatureFactory.make()
    )
    
    let result = await getStatus.getStatus(
      index: statusReference.idx,
      url: statusReference.uri,
      fetchClaims: getStatusToken.getStatusClaims
    )
    
    switch result {
    case .success:
      XCTAssert(false)
    case .failure:
      XCTAssert(true)
    }
  }
}
