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

// MARK: - Historical Resolution Tests (Draft 20 §8.4)

@Suite
struct HistoricalResolutionTests {

  // MARK: - buildHistoricalURL Tests

  @Test
  func testBuildHistoricalURL_WhenValidBaseURL_ThenAddsTimeParameter() {
    let baseURL = URL(string: "https://issuer.example/status/list")!
    let timestamp: TimeInterval = 1700000000 // Some Unix timestamp

    let result = HistoricalResolution.buildHistoricalURL(baseURL: baseURL, timestamp: timestamp)

    #expect(result != nil)
    #expect(result?.absoluteString.contains("time=") == true)
    #expect(result?.host == "issuer.example")
    #expect(result?.path == "/status/list")
  }

  @Test
  func testBuildHistoricalURL_WhenBaseURLHasExistingParams_ThenAddsTimeParameter() {
    let baseURL = URL(string: "https://issuer.example/status/list?foo=bar")!
    let timestamp: TimeInterval = 1700000000

    let result = HistoricalResolution.buildHistoricalURL(baseURL: baseURL, timestamp: timestamp)

    #expect(result != nil)
    #expect(result?.absoluteString.contains("time=") == true)
    #expect(result?.absoluteString.contains("foo=bar") == true)
  }

  @Test
  func testBuildHistoricalURL_WhenBaseURLAlreadyHasTimeParam_ThenReplacesIt() {
    let baseURL = URL(string: "https://issuer.example/status/list?time=oldvalue")!
    let timestamp: TimeInterval = 1700000000

    let result = HistoricalResolution.buildHistoricalURL(baseURL: baseURL, timestamp: timestamp)

    #expect(result != nil)
    // Should have exactly one time parameter, not two
    let queryItems = URLComponents(url: result!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let timeParams = queryItems.filter { $0.name == "time" }
    #expect(timeParams.count == 1)
    #expect(timeParams.first?.value?.contains("oldvalue") == false)
  }

  @Test
  func testBuildHistoricalURL_WhenTimestampProvided_ThenFormatsAsISO8601() {
    let baseURL = URL(string: "https://issuer.example/status/list")!
    // 2023-11-14T22:13:20.000Z
    let timestamp: TimeInterval = 1700000000

    let result = HistoricalResolution.buildHistoricalURL(baseURL: baseURL, timestamp: timestamp)

    #expect(result != nil)
    // The time parameter should contain ISO8601 formatted date
    let queryItems = URLComponents(url: result!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let timeValue = queryItems.first { $0.name == "time" }?.value
    #expect(timeValue != nil)
    #expect(timeValue?.contains("2023-11-14") == true || timeValue?.contains("2023-11-15") == true) // Depending on timezone
  }

  // MARK: - validateTimestampCoverage Tests

  @Test
  func testValidateTimestampCoverage_WhenTimestampWithinBounds_ThenSucceeds() throws {
    let now = Date().timeIntervalSince1970
    let claims = StatusListTokenClaims(
      subject: "https://example.com/status",
      issuedAt: now - 3600, // Issued 1 hour ago
      expirationTime: now + 3600, // Expires in 1 hour
      timeToLive: nil,
      statusList: StatusList(
        bytesPerStatus: .one,
        compressedList: "eJxjYGBgAAAABAAB",
        aggregationUri: nil
      )
    )

    // Request timestamp is exactly now - within iat and exp
    try HistoricalResolution.validateTimestampCoverage(
      claims: claims,
      requestedTimestamp: now
    )
  }

  @Test
  func testValidateTimestampCoverage_WhenTimestampEqualsIat_ThenSucceeds() throws {
    let now = Date().timeIntervalSince1970
    let iat = now - 3600
    let claims = StatusListTokenClaims(
      subject: "https://example.com/status",
      issuedAt: iat,
      expirationTime: now + 3600,
      timeToLive: nil,
      statusList: StatusList(
        bytesPerStatus: .one,
        compressedList: "eJxjYGBgAAAABAAB",
        aggregationUri: nil
      )
    )

    // Request timestamp equals iat (edge case)
    try HistoricalResolution.validateTimestampCoverage(
      claims: claims,
      requestedTimestamp: iat
    )
  }

  @Test
  func testValidateTimestampCoverage_WhenTimestampEqualsExp_ThenSucceeds() throws {
    let now = Date().timeIntervalSince1970
    let exp = now + 3600
    let claims = StatusListTokenClaims(
      subject: "https://example.com/status",
      issuedAt: now - 3600,
      expirationTime: exp,
      timeToLive: nil,
      statusList: StatusList(
        bytesPerStatus: .one,
        compressedList: "eJxjYGBgAAAABAAB",
        aggregationUri: nil
      )
    )

    // Request timestamp equals exp (edge case)
    try HistoricalResolution.validateTimestampCoverage(
      claims: claims,
      requestedTimestamp: exp
    )
  }

  @Test
  func testValidateTimestampCoverage_WhenTimestampBeforeIat_ThenThrows() {
    let now = Date().timeIntervalSince1970
    let iat = now - 3600
    let claims = StatusListTokenClaims(
      subject: "https://example.com/status",
      issuedAt: iat,
      expirationTime: now + 3600,
      timeToLive: nil,
      statusList: StatusList(
        bytesPerStatus: .one,
        compressedList: "eJxjYGBgAAAABAAB",
        aggregationUri: nil
      )
    )

    // Request timestamp is before iat (CDN returned wrong token)
    let requestedTime = iat - 7200 // 2 hours before iat
    #expect(throws: StatusError.self) {
      try HistoricalResolution.validateTimestampCoverage(
        claims: claims,
        requestedTimestamp: requestedTime
      )
    }
  }

  @Test
  func testValidateTimestampCoverage_WhenTimestampAfterExp_ThenThrows() {
    let now = Date().timeIntervalSince1970
    let exp = now + 3600
    let claims = StatusListTokenClaims(
      subject: "https://example.com/status",
      issuedAt: now - 3600,
      expirationTime: exp,
      timeToLive: nil,
      statusList: StatusList(
        bytesPerStatus: .one,
        compressedList: "eJxjYGBgAAAABAAB",
        aggregationUri: nil
      )
    )

    // Request timestamp is after exp
    let requestedTime = exp + 7200 // 2 hours after exp
    #expect(throws: StatusError.self) {
      try HistoricalResolution.validateTimestampCoverage(
        claims: claims,
        requestedTimestamp: requestedTime
      )
    }
  }

  @Test
  func testValidateTimestampCoverage_WhenNoExpAndTimestampAfterIat_ThenSucceeds() throws {
    let now = Date().timeIntervalSince1970
    let claims = StatusListTokenClaims(
      subject: "https://example.com/status",
      issuedAt: now - 3600,
      expirationTime: nil, // No expiration
      timeToLive: nil,
      statusList: StatusList(
        bytesPerStatus: .one,
        compressedList: "eJxjYGBgAAAABAAB",
        aggregationUri: nil
      )
    )

    // No exp means only iat constraint applies
    try HistoricalResolution.validateTimestampCoverage(
      claims: claims,
      requestedTimestamp: now + 999999
    )
  }

  @Test
  func testValidateTimestampCoverage_WhenClockSkewAllowsSlightlyBeforeIat_ThenSucceeds() throws {
    let now = Date().timeIntervalSince1970
    let iat = now - 3600
    let claims = StatusListTokenClaims(
      subject: "https://example.com/status",
      issuedAt: iat,
      expirationTime: now + 3600,
      timeToLive: nil,
      statusList: StatusList(
        bytesPerStatus: .one,
        compressedList: "eJxjYGBgAAAABAAB",
        aggregationUri: nil
      )
    )

    // Request timestamp is 60 seconds before iat, but 300 seconds of clock skew allowed
    let requestedTime = iat - 60
    try HistoricalResolution.validateTimestampCoverage(
      claims: claims,
      requestedTimestamp: requestedTime,
      clockSkew: 300
    )
  }

  @Test
  func testValidateTimestampCoverage_WhenClockSkewAllowsSlightlyAfterExp_ThenSucceeds() throws {
    let now = Date().timeIntervalSince1970
    let exp = now + 3600
    let claims = StatusListTokenClaims(
      subject: "https://example.com/status",
      issuedAt: now - 3600,
      expirationTime: exp,
      timeToLive: nil,
      statusList: StatusList(
        bytesPerStatus: .one,
        compressedList: "eJxjYGBgAAAABAAB",
        aggregationUri: nil
      )
    )

    // Request timestamp is 60 seconds after exp, but 300 seconds of clock skew allowed
    let requestedTime = exp + 60
    try HistoricalResolution.validateTimestampCoverage(
      claims: claims,
      requestedTimestamp: requestedTime,
      clockSkew: 300
    )
  }

  // MARK: - GetStatus.getHistoricalStatus Tests

  @Test
  func testGetHistoricalStatus_WhenTimestampCovered_ThenReturnsStatus() async {
    let getStatus = GetStatus()
    let now = Date().timeIntervalSince1970
    let historicalTime = now - 1800 // 30 minutes ago

    // Mock fetcher that returns claims covering the historical timestamp
    let mockFetchClaims: FetchClaimsHandler = { _, url, _ in
      // Verify the URL contains the time parameter
      #expect(url.absoluteString.contains("time="))

      let claims = StatusListTokenClaims(
        subject: "https://example.com/status",
        issuedAt: now - 3600, // Covers historicalTime
        expirationTime: now + 3600,
        timeToLive: nil,
        statusList: StatusList(
          bytesPerStatus: .one,
          compressedList: "eJxjYGBgAAAABAAB", // All VALID
          aggregationUri: nil
        )
      )
      return .success(claims)
    }

    let result = await getStatus.getHistoricalStatus(
      index: 0,
      url: URL(string: "https://example.com/status")!,
      fetchClaims: mockFetchClaims,
      clockSkew: 0,
      historicalTimestamp: historicalTime
    )

    switch result {
    case .success(let status):
      #expect(status == .valid)
    case .failure(let error):
      Issue.record("Should have succeeded, got error: \(error)")
    }
  }

  @Test
  func testGetHistoricalStatus_WhenTimestampNotCovered_ThenReturnsError() async {
    let getStatus = GetStatus()
    let now = Date().timeIntervalSince1970
    let historicalTime = now - 7200 // 2 hours ago

    // Mock fetcher that returns claims NOT covering the historical timestamp
    // (simulates CDN ignoring the time parameter)
    let mockFetchClaims: FetchClaimsHandler = { _, _, _ in
      let claims = StatusListTokenClaims(
        subject: "https://example.com/status",
        issuedAt: now - 3600, // iat is AFTER historicalTime!
        expirationTime: now + 3600,
        timeToLive: nil,
        statusList: StatusList(
          bytesPerStatus: .one,
          compressedList: "eJxjYGBgAAAABAAB",
          aggregationUri: nil
        )
      )
      return .success(claims)
    }

    let result = await getStatus.getHistoricalStatus(
      index: 0,
      url: URL(string: "https://example.com/status")!,
      fetchClaims: mockFetchClaims,
      clockSkew: 0,
      historicalTimestamp: historicalTime
    )

    switch result {
    case .success:
      Issue.record("Should have failed with historicalTimestampNotCovered")
    case .failure(let error):
      if case .historicalTimestampNotCovered = error {
        // Expected
      } else {
        Issue.record("Expected historicalTimestampNotCovered, got: \(error)")
      }
    }
  }

  @Test
  func testGetHistoricalStatus_WhenIssuerReturns404_ThenReturnsHistoricalResolutionNotSupported() async {
    let getStatus = GetStatus()
    let now = Date().timeIntervalSince1970

    // Mock fetcher that simulates 404 response
    let mockFetchClaims: FetchClaimsHandler = { _, _, _ in
      return .failure(.error("HTTP 404 Not Found"))
    }

    let result = await getStatus.getHistoricalStatus(
      index: 0,
      url: URL(string: "https://example.com/status")!,
      fetchClaims: mockFetchClaims,
      clockSkew: 0,
      historicalTimestamp: now - 3600
    )

    switch result {
    case .success:
      Issue.record("Should have failed with historicalResolutionNotSupported")
    case .failure(let error):
      #expect(error == .historicalResolutionNotSupported)
    }
  }

  @Test
  func testGetHistoricalStatus_WhenUsingStatusReference_ThenWorks() async {
    let getStatus = GetStatus()
    let now = Date().timeIntervalSince1970
    let historicalTime = now - 1800

    let mockFetchClaims: FetchClaimsHandler = { _, _, _ in
      let claims = StatusListTokenClaims(
        subject: "https://example.com/status",
        issuedAt: now - 3600,
        expirationTime: now + 3600,
        timeToLive: nil,
        statusList: StatusList(
          bytesPerStatus: .one,
          compressedList: "eJxjYGBgAAAABAAB",
          aggregationUri: nil
        )
      )
      return .success(claims)
    }

    let reference = StatusReference(idx: 0, uriString: "https://example.com/status")!

    let result = await getStatus.getHistoricalStatus(
      reference: reference,
      fetchClaims: mockFetchClaims,
      clockSkew: 0,
      historicalTimestamp: historicalTime
    )

    switch result {
    case .success(let status):
      #expect(status == .valid)
    case .failure(let error):
      Issue.record("Should have succeeded, got error: \(error)")
    }
  }

  @Test
  func testGetHistoricalStatus_WhenReferencedTokenExpired_ThenReturnsExpiredToken() async {
    let getStatus = GetStatus()
    let now = Date().timeIntervalSince1970
    let historicalTime = now - 1800

    let mockFetchClaims: FetchClaimsHandler = { _, _, _ in
      let claims = StatusListTokenClaims(
        subject: "https://example.com/status",
        issuedAt: now - 3600,
        expirationTime: now + 3600,
        timeToLive: nil,
        statusList: StatusList(
          bytesPerStatus: .one,
          compressedList: "eJxjYGBgAAAABAAB",
          aggregationUri: nil
        )
      )
      return .success(claims)
    }

    // Referenced token was expired at the historical time
    let expiredReferencedTokenExp = historicalTime - 3600

    let result = await getStatus.getHistoricalStatus(
      index: 0,
      url: URL(string: "https://example.com/status")!,
      fetchClaims: mockFetchClaims,
      clockSkew: 0,
      historicalTimestamp: historicalTime,
      referencedTokenExpiration: expiredReferencedTokenExp
    )

    switch result {
    case .success:
      Issue.record("Should have failed with expiredToken")
    case .failure(let error):
      #expect(error == .expiredToken)
    }
  }
}
