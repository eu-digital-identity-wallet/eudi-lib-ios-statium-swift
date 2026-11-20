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
struct GetStatusTests {
  
  init() {
    URLCache.shared.removeAllCachedResponses()
  }
  
  // Uncomment to run locally, procure a valid status url first
  @Test
  func testDecodeStatusReference_WhenValidInputProvided_ThenReturnsCorrectStatusReference() async throws {
    let statusReference = try #require(StatusReference(
      idx: 1,
      uriString: ConstantsTests.testStatusUrlString
    ))
    
    #expect(statusReference.idx == 1)
    #expect(statusReference.uri.absoluteString == ConstantsTests.testStatusUrlString)
  }

  // Uncomment to run locally, procure a valid status url first
  // @Test
  func testGetStatusClaimsFor_WhenValidJWTStatusReferenceProvided_ThenReturnsSuccess() async throws {
    
    guard let statusReference: StatusReference = .init(
      idx: 1,
      uriString: ConstantsTests.testStatusUrlString
    ) else {
      Issue.record("Cannot decode status reference")
      return
    }
    
    let tokenFetcher = StatusListTokenFetcher(
      verifier: VerifyStatusListTokenSignatureFactory.make()
    )

    let result = await tokenFetcher.getStatusClaims(
      url: statusReference.uri,
      clockSkew: TimeIntervalUnit.weeks.toTimeInterval(multiplier: 3)
    )

    switch result {
    case .success:
      #expect(true)
    case .failure(let error):
      Issue.record("Failed: \(error)")
    }
  }

  // Uncomment to run locally, procure a valid status url first
  // @Test
  func testGetStatusClaimsFor_WhenValidCWTStatusReferenceProvided_ThenReturnsSuccess() async throws {

    guard let statusReference: StatusReference = .init(
      idx: 1,
      uriString: ConstantsTests.testStatusUrlString
    ) else {
      Issue.record("Cannot decode status reference")
      return
    }

    let tokenFetcher = StatusListTokenFetcher(
      verifier: VerifyStatusListTokenSignatureFactory.make()
    )
    
    let result = await tokenFetcher.getStatusClaims(
      format: .cwt,
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

  // MARK: - Expiration Precedence Tests (Draft 20 §7.1)

  /// Test that when status is VALID but referenced token is expired, the result is expiredToken.
  /// Draft 20 §7.1: Even if status list says VALID, an expired referenced token MUST be treated as expired.
  @Test
  func testGetStatus_WhenStatusValidButReferencedTokenExpired_ThenReturnsExpiredToken() async throws {
    let getStatus = GetStatus()

    // Create a mock fetch handler that returns a valid status list
    let mockFetchClaims: FetchClaimsHandler = { _, _, _ in
      // Return claims where status at index 0 is VALID (0x00)
      let claims = StatusListTokenClaims(
        subject: "https://example.com/status",
        issuedAt: Date().timeIntervalSince1970 - 3600,
        expirationTime: Date().timeIntervalSince1970 + 3600,
        timeToLive: nil,
        statusList: StatusList(
          bytesPerStatus: .one,
          compressedList: "eJxjYGBgAAAABAAB",  // Compressed zeros - all VALID
          aggregationUri: nil
        )
      )
      return .success(claims)
    }

    // Referenced token expired 1 hour ago
    let expiredTokenExp = Date().timeIntervalSince1970 - 3600

    let result = await getStatus.getStatus(
      index: 0,
      url: URL(string: "https://example.com/status")!,
      fetchClaims: mockFetchClaims,
      clockSkew: 0,
      referencedTokenExpiration: expiredTokenExp
    )

    switch result {
    case .success:
      Issue.record("Should have returned expiredToken error")
    case .failure(let error):
      #expect(error == .expiredToken)
    }
  }

  /// Test that when status is VALID and referenced token is NOT expired, the result is valid.
  @Test
  func testGetStatus_WhenStatusValidAndReferencedTokenNotExpired_ThenReturnsValid() async throws {
    let getStatus = GetStatus()

    let mockFetchClaims: FetchClaimsHandler = { _, _, _ in
      let claims = StatusListTokenClaims(
        subject: "https://example.com/status",
        issuedAt: Date().timeIntervalSince1970 - 3600,
        expirationTime: Date().timeIntervalSince1970 + 3600,
        timeToLive: nil,
        statusList: StatusList(
          bytesPerStatus: .one,
          compressedList: "eJxjYGBgAAAABAAB",  // Compressed zeros - all VALID
          aggregationUri: nil
        )
      )
      return .success(claims)
    }

    // Referenced token expires in 1 hour (not expired)
    let validTokenExp = Date().timeIntervalSince1970 + 3600

    let result = await getStatus.getStatus(
      index: 0,
      url: URL(string: "https://example.com/status")!,
      fetchClaims: mockFetchClaims,
      clockSkew: 0,
      referencedTokenExpiration: validTokenExp
    )

    switch result {
    case .success(let status):
      #expect(status == .valid)
    case .failure(let error):
      Issue.record("Should have returned valid status, got error: \(error)")
    }
  }

  /// Test that when status is INVALID (revoked), expiration precedence doesn't apply.
  /// The status should be returned as-is.
  @Test
  func testGetStatus_WhenStatusInvalid_ThenReturnsInvalidRegardlessOfExpiration() async throws {
    let getStatus = GetStatus()

    let mockFetchClaims: FetchClaimsHandler = { _, _, _ in
      // Using 8 bits per status where each byte is a direct status value.
      // For index 0 to be INVALID, the first byte should be 0x01.
      // zlib.compress(bytes([0x01])) -> eJxjBAAAAgAC in base64url
      let claims = StatusListTokenClaims(
        subject: "https://example.com/status",
        issuedAt: Date().timeIntervalSince1970 - 3600,
        expirationTime: Date().timeIntervalSince1970 + 3600,
        timeToLive: nil,
        statusList: StatusList(
          bytesPerStatus: .eight,  // 8 bits per status - each byte is a direct status value
          compressedList: "eJxjBAAAAgAC",  // zlib-compressed [0x01] = INVALID status at index 0
          aggregationUri: nil
        )
      )
      return .success(claims)
    }

    // Referenced token is not expired
    let validTokenExp = Date().timeIntervalSince1970 + 3600

    let result = await getStatus.getStatus(
      index: 0,
      url: URL(string: "https://example.com/status")!,
      fetchClaims: mockFetchClaims,
      clockSkew: 0,
      referencedTokenExpiration: validTokenExp
    )

    switch result {
    case .success(let status):
      #expect(status == .invalid)
    case .failure(let error):
      Issue.record("Should have returned invalid status, got error: \(error)")
    }
  }

  /// Test that when no referencedTokenExpiration is provided, expiration precedence is skipped.
  @Test
  func testGetStatus_WhenNoReferencedTokenExpiration_ThenReturnsStatusAsIs() async throws {
    let getStatus = GetStatus()

    let mockFetchClaims: FetchClaimsHandler = { _, _, _ in
      let claims = StatusListTokenClaims(
        subject: "https://example.com/status",
        issuedAt: Date().timeIntervalSince1970 - 3600,
        expirationTime: Date().timeIntervalSince1970 + 3600,
        timeToLive: nil,
        statusList: StatusList(
          bytesPerStatus: .one,
          compressedList: "eJxjYGBgAAAABAAB",  // Compressed zeros - all VALID
          aggregationUri: nil
        )
      )
      return .success(claims)
    }

    // No referenced token expiration provided (nil)
    let result = await getStatus.getStatus(
      index: 0,
      url: URL(string: "https://example.com/status")!,
      fetchClaims: mockFetchClaims,
      clockSkew: 0,
      referencedTokenExpiration: nil
    )

    switch result {
    case .success(let status):
      #expect(status == .valid)
    case .failure(let error):
      Issue.record("Should have returned valid status, got error: \(error)")
    }
  }

  /// Test that clock skew is respected in expiration precedence check.
  @Test
  func testGetStatus_WhenReferencedTokenExpiredButWithinClockSkew_ThenReturnsValid() async throws {
    let getStatus = GetStatus()

    let mockFetchClaims: FetchClaimsHandler = { _, _, _ in
      let claims = StatusListTokenClaims(
        subject: "https://example.com/status",
        issuedAt: Date().timeIntervalSince1970 - 3600,
        expirationTime: Date().timeIntervalSince1970 + 3600,
        timeToLive: nil,
        statusList: StatusList(
          bytesPerStatus: .one,
          compressedList: "eJxjYGBgAAAABAAB",
          aggregationUri: nil
        )
      )
      return .success(claims)
    }

    // Token expired 60 seconds ago
    let slightlyExpiredTokenExp = Date().timeIntervalSince1970 - 60
    // But we allow 300 seconds of clock skew
    let clockSkew: TimeInterval = 300

    let result = await getStatus.getStatus(
      index: 0,
      url: URL(string: "https://example.com/status")!,
      fetchClaims: mockFetchClaims,
      clockSkew: clockSkew,
      referencedTokenExpiration: slightlyExpiredTokenExp
    )

    switch result {
    case .success(let status):
      #expect(status == .valid)
    case .failure(let error):
      Issue.record("Should have returned valid status (within clock skew), got error: \(error)")
    }
  }
}
