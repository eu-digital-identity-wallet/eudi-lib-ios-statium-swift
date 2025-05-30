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
final class GetStatusTests {
  
  // Uncomment to run locally
  @Test
  func testDecodeStatusReference_WhenValidInputProvided_ThenReturnsCorrectStatusReference() async throws {
    let statusReference = try #require(StatusReference(
      idx: 1,
      uriString: ConstantsTests.testStatusUrlString
    ))
    
    #expect(statusReference.idx == 1)
    #expect(statusReference.uri.absoluteString == ConstantsTests.testStatusUrlString)
  }

  // @Test
  func testGetStatusClaims_WhenValidStatusReferenceProvided_ThenReturnsSuccess() async throws {
    
    guard let statusReference: StatusReference = .init(
      idx: 1,
      uriString: ConstantsTests.testStatusUrlString
    ) else {
      Issue.record("Cannot decode status reference")
      return
    }
    
    let tokenFetcher = StatusListTokenFetcher(
      verifier: VerifyStatusListTokenSignatureFactory.make(),
      date: Date()
    )
    
    let result = await tokenFetcher.getStatusClaims(
      url: statusReference.uri,
      clockSkew: TimeIntervalUnit.weeks.toTimeInterval(multiplier: 3)
    )
    
    switch result {
    case .success:
      #expect(true)
    case .failure:
      Issue.record("Invalid status")
    }
  }
  
  // @Test
  func testGetStatus_WhenCalledWithValidStatusReference_ThenReturnsValidStatus() async throws {
    
    guard let statusReference: StatusReference = .init(
      idx: 1,
      uriString: ConstantsTests.testStatusUrlString
    ) else {
      Issue.record("Cannot decode status reference")
      return
    }
    
    let getStatus = GetStatus()
    let tokenFetcher = StatusListTokenFetcher(
      verifier: VerifyStatusListTokenSignatureFactory.make()
    )
    
    let result = await getStatus.getStatus(
      index: statusReference.idx,
      url: statusReference.uri,
      fetchClaims: tokenFetcher.getStatusClaims,
      clockSkew: TimeIntervalUnit.weeks.toTimeInterval(multiplier: 3)
    )
    
    switch result {
    case .success(let status):
      switch status {
      case .valid:
        #expect(true)
      case .invalid:
        Issue.record("Invalid status")
      case .suspended:
        Issue.record("Invalid status")
      case .applicationSpecific:
        Issue.record("Invalid status")
      case .reserved:
        Issue.record("Invalid status")
      }
      
    case .failure:
      Issue.record("Invalid status")
    }
  }
  
  // @Test
  func testGetStatus_WhenCalledWithValidStatusReferenceObject_ThenReturnsValidStatus() async throws {
    
    let getStatus = GetStatus()
    let tokenFetcher = StatusListTokenFetcher(
      verifier: VerifyStatusListTokenSignatureFactory.make()
    )
    
    let result = await getStatus.getStatus(
      reference: .init(
        idx: 1,
        uriString: ConstantsTests.testStatusUrlString
      )!,
      fetchClaims: tokenFetcher.getStatusClaims,
      clockSkew: TimeIntervalUnit.weeks.toTimeInterval(multiplier: 3)
    )
    
    switch result {
    case .success(let status):
      #expect(status == .valid)
    case .failure:
      Issue.record("Invalid status")
    }
  }
  
  // @Test
  func testGetStatus_WhenCalledWithInvalidStatusReference_ThenReturnsFailure() async throws {
    
    guard let statusReference: StatusReference = .init(
      idx: 1,
      uriString: "https://statium.com"
    ) else {
      Issue.record("Cannot decode status reference")
      return
    }
    
    let getStatus = GetStatus()
    let tokenFetcher = StatusListTokenFetcher(
      verifier: VerifyStatusListTokenSignatureFactory.make()
    )
    
    let result = await getStatus.getStatus(
      index: statusReference.idx,
      url: statusReference.uri,
      fetchClaims: tokenFetcher.getStatusClaims,
      clockSkew: TimeIntervalUnit.weeks.toTimeInterval(multiplier: 3)
    )
    
    switch result {
    case .success:
      Issue.record("Invalid status")
    case .failure:
      #expect(true)
    }
  }
}
