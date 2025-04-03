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
  
  func testStatusListFlowValid() async throws {
    
    guard let statusReference: StatusReference = .init(
      idx: 1,
      uriString: "https://issuer.eudiw.dev/token_status_list/FC/eu.europa.ec.eudi.pid.1/b6ce44dc-d240-42e8-ada6-e62743ddc61f"
    ) else {
      XCTFail("Cannot decode status reference")
      return
    }
    
    let result = await GetStatus(
      verifier: VerifyStatusListTokenSignatureFactory.make()
    ).getStatus(
      index: statusReference.idx,
      url: statusReference.uri
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
      uriString: "https://issuer.eudiw.dev/token_status_list/FC/eu.europa.ec.eudi.pid.1/b6ce44dc-d240-42e8-ada6-e62743ddc61f"
    ) else {
      XCTFail("Cannot decode status reference")
      return
    }
    
    let result = await GetStatus(
      verifier: VerifyStatusListTokenSignatureFactory.make()
    ).getStatus(
      index: statusReference.idx,
      url: statusReference.uri
    )
    
    switch result {
    case .success:
      XCTAssert(false)
    case .failure:
      XCTAssert(true)
    }
  }
}
